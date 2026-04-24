defmodule PomodoroTrackerWeb.DayLive do
  use PomodoroTrackerWeb, :live_view

  alias PomodoroTracker.{Timer, Vault}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Timer.topic())
      Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Vault.Watcher.topic())
      :timer.send_interval(1000, self(), :tick_clock)
    end

    {:ok,
     socket
     |> assign(:page_title, "Today")
     |> assign(:now, NaiveDateTime.from_erl!(:calendar.local_time()))
     |> assign(:timer, Timer.state())
     |> assign(:zone_filter, :auto)
     |> assign(:tag_filter, MapSet.new())
     |> assign(:new_task_form, nil)
     |> assign(:edit_form, nil)
     |> assign(:break_tag_filter, nil)
     |> assign(:today_collapsed, false)
     |> assign(:unfinished_collapsed, true)
     |> assign(:archive_visible, false)
     |> assign(:archive, nil)
     |> assign(:archive_state_filter, :unfinished)
     |> assign(:archive_zone_filter, :all)
     |> assign(:show_off_hour_work, false)
     |> load_vault()}
  end

  # ---------------------------------------------------------------------------
  # PubSub + clock
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:timer, state}, socket) do
    socket =
      if break_phase?(socket.assigns.timer.phase) and not break_phase?(state.phase) do
        assign(socket, :break_tag_filter, nil)
      else
        socket
      end

    {:noreply, assign(socket, :timer, state)}
  end
  def handle_info(:vault_changed, socket), do: {:noreply, load_vault(socket)}

  def handle_info(:tick_clock, socket) do
    {:noreply, assign(socket, :now, NaiveDateTime.from_erl!(:calendar.local_time()))}
  end

  # ---------------------------------------------------------------------------
  # Timer
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("timer:start_work", _, socket) do
    day = socket.assigns.day
    tasks = socket.assigns.tasks

    task_ids =
      case day.active do
        [] -> Enum.take(day.order, 1)
        active -> active
      end

    zone =
      case task_ids do
        [first | _] -> tasks[first].zone
        _ -> if work_hours?(socket.assigns.now), do: :work, else: :personal
      end

    if task_ids == [] do
      {:noreply, put_flash(socket, :error, "Add a task to today first")}
    else
      Timer.start_work(zone, task_ids)
      {:noreply, socket}
    end
  end

  def handle_event("timer:break", %{"kind" => kind} = params, socket) do
    override =
      case params["minutes"] do
        m when is_binary(m) and m != "" -> String.to_integer(m)
        _ -> nil
      end

    Timer.start_break(String.to_existing_atom(kind), override)
    {:noreply, socket}
  end

  def handle_event("timer:pause", _, socket), do: (Timer.pause(); {:noreply, socket})
  def handle_event("timer:resume", _, socket), do: (Timer.resume(); {:noreply, socket})
  def handle_event("timer:reset", _, socket), do: (Timer.reset(); {:noreply, socket})
  def handle_event("timer:skip", _, socket), do: (Timer.skip(); {:noreply, socket})

  def handle_event("timer:adjust", %{"delta" => delta}, socket) do
    Timer.adjust(String.to_integer(delta) * 1000)
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Filters + collapse
  # ---------------------------------------------------------------------------

  def handle_event("filter:zone", %{"zone" => zone}, socket) do
    {:noreply, assign(socket, :zone_filter, String.to_existing_atom(zone))}
  end

  def handle_event("filter:tag", %{"tag" => tag}, socket) do
    current = socket.assigns.tag_filter

    new =
      if MapSet.member?(current, tag),
        do: MapSet.delete(current, tag),
        else: MapSet.put(current, tag)

    {:noreply, assign(socket, :tag_filter, new)}
  end

  def handle_event("filter:clear_tags", _, socket) do
    {:noreply, assign(socket, :tag_filter, MapSet.new())}
  end

  def handle_event("filter:break_tag", %{"tag" => tag}, socket) do
    current = socket.assigns.break_tag_filter
    new = if current == tag, do: nil, else: tag
    {:noreply, assign(socket, :break_tag_filter, new)}
  end

  def handle_event("toggle:today", _, socket) do
    {:noreply, assign(socket, :today_collapsed, not socket.assigns.today_collapsed)}
  end

  def handle_event("toggle:unfinished", _, socket) do
    {:noreply, assign(socket, :unfinished_collapsed, not socket.assigns.unfinished_collapsed)}
  end

  def handle_event("toggle:off_hour_work", _, socket) do
    {:noreply, assign(socket, :show_off_hour_work, not socket.assigns.show_off_hour_work)}
  end

  def handle_event("archive:show", _, socket) do
    {:noreply,
     socket
     |> assign(:archive_visible, true)
     |> assign(:archive, load_archive())}
  end

  def handle_event("archive:hide", _, socket) do
    {:noreply, socket |> assign(:archive_visible, false) |> assign(:archive, nil)}
  end

  def handle_event("archive:state_filter", %{"state" => s}, socket) do
    {:noreply, assign(socket, :archive_state_filter, String.to_existing_atom(s))}
  end

  def handle_event("archive:zone_filter", %{"zone" => z}, socket) do
    {:noreply, assign(socket, :archive_zone_filter, String.to_existing_atom(z))}
  end

  def handle_event("unfinished:dismiss", %{"id" => id}, socket) do
    dismiss_from_recent(id, 7)
    {:noreply, load_vault(socket)}
  end

  # ---------------------------------------------------------------------------
  # Day plan
  # ---------------------------------------------------------------------------

  def handle_event("day:add", %{"id" => id}, socket) do
    case socket.assigns.tasks[id] do
      %{kind: :templates} = tpl ->
        {:ok, new_id} = Vault.instantiate_template(tpl)
        day = socket.assigns.day
        new_day = if new_id in day.order or new_id in day.done,
                    do: day,
                    else: %{day | order: day.order ++ [new_id]}

        Vault.save_day(new_day)
        {:noreply, socket |> assign(:day, new_day) |> load_vault()}

      _ ->
        update_day(socket, fn day ->
          if id in day.order or id in day.done,
            do: day,
            else: %{day | order: day.order ++ [id]}
        end)
    end
  end

  def handle_event("day:remove", %{"id" => id}, socket) do
    update_day(socket, fn day ->
      %{
        day
        | order: List.delete(day.order, id),
          active: List.delete(day.active, id)
      }
    end)
  end

  def handle_event("day:move", %{"id" => id, "dir" => dir}, socket) do
    update_day(socket, fn day -> %{day | order: move(day.order, id, dir)} end)
  end

  def handle_event("day:toggle_active", %{"id" => id}, socket) do
    resolved =
      case socket.assigns.tasks[id] do
        %{kind: :templates} = tpl ->
          {:ok, new_id} = Vault.instantiate_template(tpl)
          new_id

        _ ->
          id
      end

    update_day(socket, fn day ->
      cond do
        resolved in day.active ->
          %{day | active: List.delete(day.active, resolved)}

        length(day.active) >= 2 ->
          day

        true ->
          order = if resolved in day.order, do: day.order, else: day.order ++ [resolved]
          %{day | active: day.active ++ [resolved], order: order}
      end
    end)
  end

  def handle_event("day:finish", %{"id" => id}, socket) do
    update_day(socket, fn day ->
      %{
        day
        | active: List.delete(day.active, id),
          order: List.delete(day.order, id),
          done: day.done ++ [id]
      }
    end)
  end

  def handle_event("day:unfinish", %{"id" => id}, socket) do
    update_day(socket, fn day ->
      %{day | done: List.delete(day.done, id), order: day.order ++ [id]}
    end)
  end

  # ---------------------------------------------------------------------------
  # New task (controlled form)
  # ---------------------------------------------------------------------------

  def handle_event("new:open", %{"kind" => kind, "zone" => zone}, socket) do
    {:noreply,
     assign(socket, :new_task_form, %{
       kind: String.to_existing_atom(kind),
       zone: String.to_existing_atom(zone),
       title: "",
       priority: "med",
       tags: "",
       is_break: false,
       add_to_today: true
     })}
  end

  def handle_event("new:close", _, socket), do: {:noreply, assign(socket, :new_task_form, nil)}

  def handle_event("new:change", %{"task" => p}, socket) do
    form = socket.assigns.new_task_form

    form = %{
      form
      | title: p["title"] || "",
        priority: p["priority"] || "med",
        tags: p["tags"] || "",
        is_break: p["is_break"] == "true",
        add_to_today: p["add_to_today"] == "true"
    }

    {:noreply, assign(socket, :new_task_form, form)}
  end

  def handle_event("new:submit", _params, socket) do
    form = socket.assigns.new_task_form
    title = String.trim(form.title)

    if title == "" do
      {:noreply, put_flash(socket, :error, "Title required")}
    else
      id = slugify(title)
      tags = parse_tags(form.tags, form.is_break)

      attrs = %{
        id: id,
        title: title,
        zone: form.zone,
        priority: form.priority,
        tags: tags,
        created_at: Date.utc_today() |> Date.to_iso8601()
      }

      case Vault.create_task(form.zone, form.kind, attrs) do
        {:ok, _path} ->
          socket =
            if form.add_to_today do
              day = socket.assigns.day
              Vault.save_day(%{day | order: day.order ++ [id]})
              socket
            else
              socket
            end

          {:noreply, socket |> assign(:new_task_form, nil) |> load_vault()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not create: #{inspect(reason)}")}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edit existing task (controlled form)
  # ---------------------------------------------------------------------------

  def handle_event("edit:open", %{"id" => id}, socket) do
    t = socket.assigns.tasks[id]

    if t do
      form = %{
        id: id,
        path: t.path,
        kind: t.kind,
        from_template: t.from_template,
        title: t.title,
        priority: t.priority || "med",
        tags: Enum.join(t.tags || [], ", "),
        related: Enum.join(t.related || [], "\n"),
        body: t.body || "",
        is_break: "break" in (t.tags || [])
      }

      {:noreply, assign(socket, :edit_form, form)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit:close", _, socket), do: {:noreply, assign(socket, :edit_form, nil)}

  def handle_event("edit:change", %{"task" => p}, socket) do
    f = socket.assigns.edit_form

    f = %{
      f
      | title: p["title"] || "",
        priority: p["priority"] || "med",
        tags: p["tags"] || "",
        related: p["related"] || "",
        body: p["body"] || "",
        is_break: p["is_break"] == "true"
    }

    {:noreply, assign(socket, :edit_form, f)}
  end

  def handle_event("edit:submit", _params, socket) do
    f = socket.assigns.edit_form

    attrs = %{
      title: f.title,
      priority: f.priority,
      tags: parse_tags(f.tags, f.is_break),
      related: parse_lines(f.related),
      body: f.body
    }

    case Vault.update_task(f.path, attrs) do
      :ok ->
        {:noreply, socket |> assign(:edit_form, nil) |> load_vault()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Update failed: #{inspect(reason)}")}
    end
  end

  def handle_event("edit:delete", _, socket) do
    f = socket.assigns.edit_form

    if f do
      Vault.delete_task(f.path)

      day = socket.assigns.day

      new_day = %{
        day
        | order: List.delete(day.order, f.id),
          active: List.delete(day.active, f.id),
          done: List.delete(day.done, f.id)
      }

      if new_day != day, do: Vault.save_day(new_day)

      {:noreply,
       socket
       |> assign(:edit_form, nil)
       |> assign(:day, new_day)
       |> load_vault()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit:promote", _, socket) do
    f = socket.assigns.edit_form
    task = socket.assigns.tasks[f.id]

    case task && Vault.promote_to_template(task) do
      {:ok, _path} ->
        {:noreply,
         socket
         |> put_flash(:info, "Promoted #{task.title} to template")
         |> load_vault()}

      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "Template with this id already exists")}

      _ ->
        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp load_vault(socket) do
    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    {:ok, day} = Vault.load_day()

    {order, a?} = migrate_template_ids(day.order, tasks)
    {active, b?} = migrate_template_ids(day.active, tasks)
    {done, c?} = migrate_template_ids(day.done || [], tasks)

    tasks =
      if a? or b? or c?,
        do: Vault.list_all_tasks() |> Map.new(&{&1.id, &1}),
        else: tasks

    order = Enum.filter(order, &Map.has_key?(tasks, &1))
    active = Enum.filter(active, &Map.has_key?(tasks, &1))
    done = Enum.filter(done, &Map.has_key?(tasks, &1))

    day = %{day | order: order, active: active, done: done}
    if a? or b? or c?, do: Vault.save_day(day)

    socket
    |> assign(:tasks, tasks)
    |> assign(:day, day)
  end

  defp migrate_template_ids(ids, tasks) do
    Enum.map_reduce(ids, false, fn id, any? ->
      case tasks[id] do
        %{kind: :templates} = tpl ->
          {:ok, new_id} = Vault.instantiate_template(tpl)
          {new_id, true}

        _ ->
          {id, any?}
      end
    end)
  end

  defp update_day(socket, fun) do
    new_day = fun.(socket.assigns.day)
    Vault.save_day(new_day)
    {:noreply, assign(socket, :day, new_day)}
  end

  defp move(list, id, "up") do
    idx = Enum.find_index(list, &(&1 == id))
    if idx in [nil, 0], do: list, else: swap(list, idx, idx - 1)
  end

  defp move(list, id, "down") do
    idx = Enum.find_index(list, &(&1 == id))
    if idx == nil or idx == length(list) - 1, do: list, else: swap(list, idx, idx + 1)
  end

  defp move(list, id, "top") do
    if id in list, do: [id | List.delete(list, id)], else: list
  end

  defp move(list, id, "bottom") do
    if id in list, do: List.delete(list, id) ++ [id], else: list
  end

  defp swap(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)
    list |> List.replace_at(i, b) |> List.replace_at(j, a)
  end

  defp parse_tags(str, is_break?) do
    base = parse_lines(str, ",")
    cond do
      is_break? and "break" not in base -> base ++ ["break"]
      not is_break? -> Enum.reject(base, &(&1 == "break"))
      true -> base
    end
  end

  defp parse_lines(str, sep \\ "\n")
  defp parse_lines(nil, _sep), do: []
  defp parse_lines("", _sep), do: []

  defp parse_lines(str, sep) when is_binary(str) do
    str |> String.split(sep) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 60)
  end

  # ---------------------------------------------------------------------------
  # View helpers
  # ---------------------------------------------------------------------------

  def work_hours?(%NaiveDateTime{} = dt) do
    cfg = Application.fetch_env!(:pomodoro_tracker, :work_hours)
    wday = Date.day_of_week(NaiveDateTime.to_date(dt))
    dt.hour >= cfg[:start] and dt.hour < cfg[:stop] and wday in cfg[:weekdays]
  end

  # Timeline strip across the top: 7am (left) to 8pm (right).
  # Weekdays split 7-9am personal, 9am-6pm work, 6pm-8pm personal.
  # Weekends are fully personal.
  @timeline_start_min 7 * 60
  @timeline_end_min 20 * 60
  @timeline_span_min 13 * 60

  def day_timeline(%NaiveDateTime{} = now) do
    weekend? = Date.day_of_week(NaiveDateTime.to_date(now)) in [6, 7]
    now_min = now.hour * 60 + now.minute

    zones =
      if weekend? do
        [%{start: 0.0, width: 100.0, color: "bg-blue-500/70"}]
      else
        m_end = (9 * 60 - @timeline_start_min) / @timeline_span_min * 100
        w_end = (18 * 60 - @timeline_start_min) / @timeline_span_min * 100

        [
          %{start: 0.0, width: m_end, color: "bg-blue-500/70"},
          %{start: m_end, width: w_end - m_end, color: "bg-red-500/70"},
          %{start: w_end, width: 100 - w_end, color: "bg-blue-500/70"}
        ]
      end

    %{
      zones: zones,
      now_pct: clamp((now_min - @timeline_start_min) / @timeline_span_min * 100, 0, 100),
      in_range?: now_min >= @timeline_start_min and now_min <= @timeline_end_min
    }
  end

  defp clamp(x, lo, _hi) when x < lo, do: lo
  defp clamp(x, _lo, hi) when x > hi, do: hi
  defp clamp(x, _lo, _hi), do: x

  @doc """
  Background follows current situation (timer first, then time of day).
  Break → always blue. Work interval → zone of current task. Idle → by clock.
  """
  def situation_bg(timer, now) do
    cond do
      timer.phase == :work and timer.zone == :work -> "bg-red-950"
      timer.phase == :work and timer.zone == :personal -> "bg-blue-950"
      timer.phase in [:active_break, :passive_break, :long_break] -> "bg-blue-950"
      work_hours?(now) -> "bg-red-950"
      true -> "bg-blue-950"
    end
  end

  def backlog_zone(now, zone_filter) do
    case zone_filter do
      :auto -> if work_hours?(now), do: :work, else: :personal
      other -> other
    end
  end

  def zone_card_class(:work), do: "bg-red-900/40 border-red-700/50"
  def zone_card_class(:personal), do: "bg-blue-900/40 border-blue-700/50"

  def fmt_time(ms) when ms > 0 do
    total = div(ms, 1000)
    mins = div(total, 60)
    secs = rem(total, 60)
    "#{pad(mins)}:#{pad(secs)}"
  end

  def fmt_time(_), do: "00:00"

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  def phase_label(:work), do: "Work"
  def phase_label(:active_break), do: "Active break"
  def phase_label(:passive_break), do: "Break"
  def phase_label(:idle), do: "Ready"

  def next_break_minutes(timer), do: Timer.default_break_minutes(timer.rounds_completed)

  @doc """
  Dots lit in the 4-pomodoro cycle indicator.
  After the 4th work interval, show all 4 lit until the next work starts,
  instead of wrapping back to 0 (which looks like the cycle reset early).
  """
  def rounds_lit(%{rounds_completed: n, phase: phase}) do
    cond do
      n == 0 -> 0
      rem(n, 4) == 0 and phase != :work -> 4
      true -> rem(n, 4)
    end
  end

  def work_minutes, do: Application.fetch_env!(:pomodoro_tracker, :pomodoro)[:work_minutes]

  def break_phase?(phase), do: phase in [:active_break, :passive_break]

  @doc "During break: work-zone tasks are deferred ('up next'). Outside break: none."
  def upnext_ids(active, tasks) do
    Enum.filter(active, fn id ->
      case tasks[id] do
        %{zone: :work} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Tasks shown in the 'doing now' card. Outside break: all active tasks.
  During break: only personal-zone active (the ones you picked for this break).
  """
  def now_ids(active, tasks, phase) do
    if break_phase?(phase) do
      Enum.filter(active, fn id ->
        case tasks[id] do
          %{zone: :personal} -> true
          _ -> false
        end
      end)
    else
      active
    end
  end

  def count_with_tag(tasks, tag) do
    Enum.count(tasks, fn {_id, t} -> t.kind == :backlog and tag in (t.tags || []) end)
  end

  def filtered_backlog(tasks, zone, tag_filter, exclude_ids) do
    tasks
    |> backlog_candidates(zone, exclude_ids)
    |> Enum.filter(fn t -> MapSet.subset?(tag_filter, MapSet.new(t.tags || [])) end)
    |> Enum.sort_by(fn t -> {priority_rank(t.priority), sortable_title(t.title)} end)
  end

  @doc """
  Tags present across the backlog candidates — rendered as filter chips.
  Hides tags shared by 100% of candidates (filtering would be a no-op).
  """
  def backlog_tags(tasks, zone, exclude_ids) do
    candidates = backlog_candidates(tasks, zone, exclude_ids)
    total = length(candidates)

    candidates
    |> Enum.flat_map(fn t -> t.tags || [] end)
    |> Enum.frequencies()
    |> Enum.reject(fn {_tag, count} -> total > 1 and count == total end)
    |> Enum.sort_by(fn {tag, _} -> tag end)
    |> Enum.map(&elem(&1, 0))
  end

  defp backlog_candidates(tasks, zone, exclude_ids) do
    candidates =
      tasks
      |> Map.values()
      |> Enum.filter(fn t ->
        t.kind in [:backlog, :templates] and
          t.zone == zone and
          t.id not in exclude_ids
      end)

    instantiated =
      for %{kind: :backlog, from_template: ft} <- candidates,
          is_binary(ft),
          into: MapSet.new(),
          do: ft

    Enum.reject(candidates, fn t ->
      t.kind == :templates and MapSet.member?(instantiated, t.id)
    end)
  end

  @doc """
  Tasks offered during a break. Active break → personal WITHOUT `break` tag
  (quick chores). Passive break → personal WITH `break` tag (rest).

  Templates whose instance already exists are hidden (dedupe). Tasks already
  on today's plan rank above everything else so you see them first.
  """
  def break_picker_tasks(tasks, phase, exclude_ids, day_order, tag_filter) do
    tasks
    |> break_picker_candidates(phase, exclude_ids)
    |> Enum.filter(fn t -> tag_filter == nil or tag_filter in (t.tags || []) end)
    |> Enum.sort_by(fn t ->
      case Enum.find_index(day_order, &(&1 == t.id)) do
        nil -> {1, priority_rank(t.priority), sortable_title(t.title)}
        idx -> {0, idx, ""}
      end
    end)
  end

  @doc """
  Tags present across the break picker candidates, for rendering filter chips.
  Excludes the implicit `break` tag during passive break (every item has it)
  and any tag shared by 100% of candidates (filtering would be a no-op).
  """
  def break_picker_tags(tasks, phase, exclude_ids) do
    candidates = break_picker_candidates(tasks, phase, exclude_ids)
    total = length(candidates)

    candidates
    |> Enum.flat_map(fn t -> t.tags || [] end)
    |> Enum.reject(fn tag -> phase == :passive_break and tag == "break" end)
    |> Enum.frequencies()
    |> Enum.reject(fn {_tag, count} -> total > 1 and count == total end)
    |> Enum.sort_by(fn {tag, _} -> tag end)
    |> Enum.map(&elem(&1, 0))
  end

  defp break_picker_candidates(tasks, phase, exclude_ids) do
    want_break = phase == :passive_break

    candidates =
      tasks
      |> Map.values()
      |> Enum.filter(fn t ->
        t.zone == :personal and
          t.id not in exclude_ids and
          want_break == ("break" in (t.tags || []))
      end)

    instantiated =
      for %{kind: :backlog, from_template: ft} <- candidates,
          is_binary(ft),
          into: MapSet.new(),
          do: ft

    Enum.reject(candidates, fn t ->
      t.kind == :templates and MapSet.member?(instantiated, t.id)
    end)
  end

  defp priority_rank("high"), do: 0
  defp priority_rank("med"), do: 1
  defp priority_rank("low"), do: 2
  defp priority_rank(_), do: 3

  defp sortable_title(title) when is_binary(title) do
    title |> String.normalize(:nfd) |> String.downcase()
  end

  defp sortable_title(_), do: ""

  # ---------------------------------------------------------------------------
  # Today split + counts
  # ---------------------------------------------------------------------------

  @doc "IDs still open today (order minus done), optionally hiding work-zone."
  def today_pending_ids(day, tasks, hide_work?) do
    done_set = MapSet.new(day.done || [])

    day.order
    |> Enum.reject(&MapSet.member?(done_set, &1))
    |> Enum.reject(fn id ->
      hide_work? and
        (case tasks[id] do
           %{zone: :work} -> true
           _ -> false
         end)
    end)
  end

  @doc "Finished-today IDs newest-first (day.done is appended chronologically)."
  def today_done_ids(day), do: Enum.reverse(day.done || [])

  @doc "Zone counters for today: %{work: %{done, total}, personal: %{done, total}}."
  def zone_counts(day, tasks) do
    done_set = MapSet.new(day.done || [])
    all = Enum.uniq(day.order ++ (day.done || []))

    Enum.reduce(
      all,
      %{work: %{done: 0, total: 0}, personal: %{done: 0, total: 0}},
      fn id, acc ->
        case tasks[id] do
          %{zone: zone} when zone in [:work, :personal] ->
            acc
            |> update_in([zone, :total], &(&1 + 1))
            |> (fn a ->
                  if MapSet.member?(done_set, id),
                    do: update_in(a, [zone, :done], &(&1 + 1)),
                    else: a
                end).()

          _ ->
            acc
        end
      end
    )
  end

  def has_work_in_pending?(day, tasks) do
    done_set = MapSet.new(day.done || [])

    Enum.any?(day.order, fn id ->
      not MapSet.member?(done_set, id) and
        (case tasks[id] do
           %{zone: :work} -> true
           _ -> false
         end)
    end)
  end

  @doc """
  Auto-hide work tasks from Today's pending list when we're outside work
  hours and the user hasn't explicitly opted in via the banner.
  """
  def auto_hide_work?(now, show_off_hour_work?) do
    not work_hours?(now) and not show_off_hour_work?
  end

  # ---------------------------------------------------------------------------
  # Unfinished (last 7 days) + archive (older / done)
  # ---------------------------------------------------------------------------

  @unfinished_window_days 7

  @doc """
  Returns [{date, task}] for tasks that were planned but never finished
  in the last 7 days (excluding today). Deduped across days by id, using
  the most recent unfinished date.
  """
  def unfinished_recent(tasks, current_day) do
    today = Date.utc_today()
    current_ids = MapSet.new(current_day.order ++ (current_day.done || []))

    1..@unfinished_window_days
    |> Enum.flat_map(fn days_ago ->
      date = Date.add(today, -days_ago)

      case PomodoroTracker.Vault.load_day(date) do
        {:ok, day} ->
          done_set = MapSet.new(day.done || [])

          day.order
          |> Enum.reject(&MapSet.member?(done_set, &1))
          |> Enum.map(fn id -> {id, date} end)

        _ ->
          []
      end
    end)
    |> Enum.reduce(%{}, fn {id, date}, acc ->
      Map.update(acc, id, date, fn prev ->
        if Date.compare(date, prev) == :gt, do: date, else: prev
      end)
    end)
    |> Enum.filter(fn {id, _} ->
      Map.has_key?(tasks, id) and not MapSet.member?(current_ids, id)
    end)
    |> Enum.map(fn {id, date} -> {date, Map.fetch!(tasks, id)} end)
    |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
  end

  @doc """
  Walks past day files outside the 7-day window, collects their unfinished
  and finished task ids, and returns an archive structure. Only called when
  the user clicks 'Ver archivadas'.
  """
  def load_archive do
    today = Date.utc_today()
    cutoff = Date.add(today, -@unfinished_window_days)

    tasks = PomodoroTracker.Vault.list_all_tasks() |> Map.new(&{&1.id, &1})

    {unfinished, finished} =
      PomodoroTracker.Vault.day_dates()
      |> Enum.filter(fn d -> Date.compare(d, cutoff) == :lt end)
      |> Enum.reduce({%{}, %{}}, fn date, {unf, fin} ->
        case PomodoroTracker.Vault.load_day(date) do
          {:ok, day} ->
            done_set = MapSet.new(day.done || [])

            unf =
              day.order
              |> Enum.reject(&MapSet.member?(done_set, &1))
              |> Enum.filter(&Map.has_key?(tasks, &1))
              |> Enum.reduce(unf, fn id, acc ->
                Map.update(acc, id, date, fn prev ->
                  if Date.compare(date, prev) == :gt, do: date, else: prev
                end)
              end)

            fin =
              (day.done || [])
              |> Enum.filter(&Map.has_key?(tasks, &1))
              |> Enum.reduce(fin, fn id, acc ->
                Map.update(acc, id, date, fn prev ->
                  if Date.compare(date, prev) == :gt, do: date, else: prev
                end)
              end)

            {unf, fin}

          _ ->
            {unf, fin}
        end
      end)

    %{tasks: tasks, unfinished: unfinished, finished: finished}
  end

  @doc "Removes the given task id from the order of every day file in the window."
  def dismiss_from_recent(id, days) do
    today = Date.utc_today()

    for n <- 1..days do
      date = Date.add(today, -n)

      case PomodoroTracker.Vault.load_day(date) do
        {:ok, day} ->
          if id in day.order do
            PomodoroTracker.Vault.save_day(%{day | order: List.delete(day.order, id)})
          end

        _ ->
          :ok
      end
    end

    :ok
  end

  def archive_entries(archive, state_filter, zone_filter) do
    base =
      case state_filter do
        :unfinished -> archive.unfinished
        :finished -> archive.finished
      end

    base
    |> Enum.filter(fn {id, _date} ->
      case archive.tasks[id] do
        nil -> false
        %{zone: zone} -> zone_filter == :all or zone == zone_filter
      end
    end)
    |> Enum.map(fn {id, date} -> {date, archive.tasks[id]} end)
    |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
  end

  def short_url(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when is_binary(host) ->
        tail = (path || "") |> String.split("/") |> List.last() |> to_string()
        if tail == "", do: host, else: "#{host}/…/#{tail}"

      _ ->
        url
    end
  end
end
