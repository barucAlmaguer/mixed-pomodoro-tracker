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
     |> assign(:tag_filter, nil)
     |> assign(:new_task_form, nil)
     |> assign(:edit_form, nil)
     |> assign(:break_tag_filter, nil)
     |> assign(:today_collapsed, false)
     |> assign(:done_collapsed, true)
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

  def handle_event("timer:break", %{"kind" => kind}, socket) do
    Timer.start_break(String.to_existing_atom(kind))
    {:noreply, socket}
  end

  def handle_event("timer:pause", _, socket), do: (Timer.pause(); {:noreply, socket})
  def handle_event("timer:resume", _, socket), do: (Timer.resume(); {:noreply, socket})
  def handle_event("timer:reset", _, socket), do: (Timer.reset(); {:noreply, socket})
  def handle_event("timer:skip", _, socket), do: (Timer.skip(); {:noreply, socket})

  # ---------------------------------------------------------------------------
  # Filters + collapse
  # ---------------------------------------------------------------------------

  def handle_event("filter:zone", %{"zone" => zone}, socket) do
    {:noreply, assign(socket, :zone_filter, String.to_existing_atom(zone))}
  end

  def handle_event("filter:tag", %{"tag" => tag}, socket) do
    current = socket.assigns.tag_filter
    new = if current == tag, do: nil, else: tag
    {:noreply, assign(socket, :tag_filter, new)}
  end

  def handle_event("filter:break_tag", %{"tag" => tag}, socket) do
    current = socket.assigns.break_tag_filter
    new = if current == tag, do: nil, else: tag
    {:noreply, assign(socket, :break_tag_filter, new)}
  end

  def handle_event("toggle:today", _, socket) do
    {:noreply, assign(socket, :today_collapsed, not socket.assigns.today_collapsed)}
  end

  def handle_event("toggle:done", _, socket) do
    {:noreply, assign(socket, :done_collapsed, not socket.assigns.done_collapsed)}
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
  def phase_label(:long_break), do: "Long break"
  def phase_label(:idle), do: "Ready"

  def break_phase?(phase), do: phase in [:active_break, :passive_break, :long_break]

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
    candidates =
      tasks
      |> Map.values()
      |> Enum.filter(fn t ->
        t.kind in [:backlog, :templates] and
          t.zone == zone and
          t.id not in exclude_ids and
          (tag_filter == nil or tag_filter in (t.tags || []))
      end)

    instantiated =
      for %{kind: :backlog, from_template: ft} <- candidates, is_binary(ft), into: MapSet.new(), do: ft

    candidates
    |> Enum.reject(fn t -> t.kind == :templates and MapSet.member?(instantiated, t.id) end)
    |> Enum.sort_by(fn t -> {priority_rank(t.priority), sortable_title(t.title)} end)
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
      {if(t.id in day_order, do: 0, else: 1), priority_rank(t.priority), sortable_title(t.title)}
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
    |> Enum.reject(fn tag -> phase in [:passive_break, :long_break] and tag == "break" end)
    |> Enum.frequencies()
    |> Enum.reject(fn {_tag, count} -> total > 1 and count == total end)
    |> Enum.sort_by(fn {tag, _} -> tag end)
    |> Enum.map(&elem(&1, 0))
  end

  defp break_picker_candidates(tasks, phase, exclude_ids) do
    want_break = phase in [:passive_break, :long_break]

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
