defmodule PomodoroTrackerWeb.RecurrentPlannerLive do
  @moduledoc """
  Planning surface for recurrents, backlog, and archived tasks.
  """

  use PomodoroTrackerWeb, :live_view

  alias PomodoroTracker.{Cadence, Tags, Vault}
  alias PomodoroTrackerWeb.DayLive, as: ExecuteLive

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Vault.Watcher.topic())
      :timer.send_interval(1000, self(), :tick_clock)
    end

    {:ok,
     socket
     |> assign(:page_title, "Plan")
     |> assign(:zone_filter, :auto)
     |> assign(:tag_filter, MapSet.new())
     |> assign(:archive_visible, false)
     |> assign(:archive, nil)
     |> assign(:archive_state_filter, :unfinished)
     |> assign(:archive_zone_filter, :all)
     |> assign(:new_task_form, nil)
     |> assign(:edit_form, nil)
     |> assign(:now, NaiveDateTime.from_erl!(:calendar.local_time()))
     |> load_data()}
  end

  @impl true
  def handle_info(:vault_changed, socket), do: {:noreply, load_data(socket)}

  def handle_info(:tick_clock, socket) do
    {:noreply, assign(socket, :now, NaiveDateTime.from_erl!(:calendar.local_time()))}
  end

  @impl true
  def handle_event("toggle:template", %{"id" => id}, socket) do
    tasks = socket.assigns.tasks
    task = tasks[id]

    new_task =
      if task && task.kind == :templates do
        updated = %{task | paused: !task.paused}
        Vault.save_task(updated)
        updated
      else
        task
      end

    new_tasks = Map.put(tasks, id, new_task)

    {:noreply,
     socket
     |> assign(:tasks, new_tasks)
     |> assign(:tag_registry, ExecuteLive.merged_tag_registry(new_tasks))}
  end

  def handle_event("filter:zone", %{"zone" => zone}, socket) do
    {:noreply, assign(socket, :zone_filter, String.to_existing_atom(zone))}
  end

  def handle_event("filter:tag", %{"tag" => tag}, socket) do
    tag = Tags.normalize(tag)
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

  def handle_event("day:add", %{"id" => id}, socket) do
    case socket.assigns.tasks[id] do
      %{kind: :templates} = tpl ->
        {:ok, new_id} = Vault.instantiate_template(tpl)
        day = socket.assigns.day

        new_day =
          if new_id in day.order or new_id in day.done,
            do: day,
            else: %{day | order: day.order ++ [new_id]}

        Vault.save_day(new_day)
        {:noreply, socket |> assign(:day, new_day) |> load_data()}

      _ ->
        update_day(socket, fn day ->
          if id in day.order or id in day.done,
            do: day,
            else: %{day | order: day.order ++ [id]}
        end)
    end
  end

  def handle_event("new:open", %{"kind" => kind, "zone" => zone}, socket) do
    kind = String.to_existing_atom(kind)
    zone = String.to_existing_atom(zone)

    {:noreply,
     assign(
       socket,
       :new_task_form,
       ExecuteLive.task_form_defaults(kind, zone, %{add_to_today: false})
     )}
  end

  def handle_event("new:close", _, socket), do: {:noreply, assign(socket, :new_task_form, nil)}

  def handle_event("new:change", %{"task" => p}, socket) do
    {:noreply,
     assign(
       socket,
       :new_task_form,
       ExecuteLive.apply_task_form_params(socket.assigns.new_task_form, p)
     )}
  end

  def handle_event("new:toggle_tag", %{"tag" => tag}, socket) do
    {:noreply, update_form_tags(socket, :new_task_form, &toggle_tag(&1, tag))}
  end

  def handle_event("new:add_tag", _, socket) do
    {:noreply, update_form_tags(socket, :new_task_form, &merge_query_tags/1)}
  end

  def handle_event("new:toggle_weekday", %{"day" => day}, socket) do
    {:noreply,
     update_form_tags(socket, :new_task_form, &ExecuteLive.toggle_task_form_weekday(&1, day))}
  end

  def handle_event("new:submit", _params, socket) do
    form = socket.assigns.new_task_form
    title = String.trim(form.title)

    if title == "" do
      {:noreply, put_flash(socket, :error, "Title required")}
    else
      id = slugify(title)
      tags = materialized_tags(form)

      attrs = %{
        id: id,
        title: title,
        zone: form.zone,
        priority: form.priority,
        tags: tags,
        created_at: Date.utc_today() |> Date.to_iso8601()
      }

      attrs = ExecuteLive.maybe_put_task_recurrence(attrs, form)

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

          {:noreply, socket |> assign(:new_task_form, nil) |> load_data()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not create: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("edit:open", %{"id" => id}, socket) do
    t = socket.assigns.tasks[id]

    if t do
      {:noreply, assign(socket, :edit_form, ExecuteLive.task_form_from_task(t))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit:close", _, socket), do: {:noreply, assign(socket, :edit_form, nil)}

  def handle_event("edit:change", %{"task" => p}, socket) do
    {:noreply,
     assign(socket, :edit_form, ExecuteLive.apply_task_form_params(socket.assigns.edit_form, p))}
  end

  def handle_event("edit:toggle_tag", %{"tag" => tag}, socket) do
    {:noreply, update_form_tags(socket, :edit_form, &toggle_tag(&1, tag))}
  end

  def handle_event("edit:add_tag", _, socket) do
    {:noreply, update_form_tags(socket, :edit_form, &merge_query_tags/1)}
  end

  def handle_event("edit:toggle_weekday", %{"day" => day}, socket) do
    {:noreply,
     update_form_tags(socket, :edit_form, &ExecuteLive.toggle_task_form_weekday(&1, day))}
  end

  def handle_event("edit:submit", _params, socket) do
    f = socket.assigns.edit_form

    attrs = %{
      title: f.title,
      priority: f.priority,
      tags: materialized_tags(f),
      related: parse_lines(f.related),
      body: f.body
    }

    attrs = ExecuteLive.maybe_put_task_recurrence(attrs, f)

    case Vault.update_task(f.path, attrs) do
      :ok ->
        {:noreply, socket |> assign(:edit_form, nil) |> load_data()}

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
       |> load_data()}
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
         |> put_flash(:info, "Promoted #{task.title} to recurrente")
         |> load_data()}

      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "Recurrente with this id already exists")}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_data(socket) do
    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    {:ok, day} = Vault.load_day()
    day = Cadence.ensure_run!(day, tasks)
    task_history = ExecuteLive.task_history_index(tasks)

    hidden_ids =
      task_history
      |> Enum.flat_map(fn
        {id, %{state: :finished}} ->
          case tasks[id] do
            %{kind: :templates} -> []
            _ -> [id]
          end

        _ ->
          []
      end)
      |> MapSet.new()

    socket
    |> assign(:day, day)
    |> assign(:tasks, tasks)
    |> assign(:task_history, task_history)
    |> assign(:planner_hidden_ids, hidden_ids)
    |> assign(:tag_registry, ExecuteLive.merged_tag_registry(tasks))
  end

  defp update_day(socket, fun) do
    new_day = fun.(socket.assigns.day)
    Vault.save_day(new_day)
    {:noreply, assign(socket, :day, new_day)}
  end

  defp update_form_tags(socket, form_key, fun) do
    case socket.assigns[form_key] do
      nil ->
        socket

      form ->
        assign(socket, form_key, fun.(form))
    end
  end

  defp toggle_tag(form, tag) do
    tag = Tags.normalize(tag)

    tags =
      if tag in form.tags do
        List.delete(form.tags, tag)
      else
        Tags.normalize_many(form.tags ++ [tag])
      end

    %{form | tags: tags}
  end

  defp merge_query_tags(form) do
    query_tags = Tags.parse_input(form.tag_query)
    %{form | tags: Tags.normalize_many(form.tags ++ query_tags), tag_query: ""}
  end

  defp materialized_tags(form) do
    form.tags
    |> Tags.normalize_many()
    |> Tags.with_break(form.is_break)
  end

  defp visible_task_tags(tags) do
    tags
    |> Tags.normalize_many()
    |> Enum.reject(&(&1 == "break"))
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

  defdelegate zone_card_class(zone), to: ExecuteLive
  defdelegate backlog_zone(now, zone_filter), to: ExecuteLive
  defdelegate backlog_tags(tasks, zone, exclude_ids), to: ExecuteLive
  defdelegate filtered_backlog(tasks, zone, tag_filter, exclude_ids), to: ExecuteLive
  defdelegate load_archive(), to: ExecuteLive
  defdelegate archive_entries(archive, state_filter, zone_filter), to: ExecuteLive
  defdelegate tag_suggestions(tag_registry, tasks, zone), to: ExecuteLive
  defdelegate task_history_index(tasks), to: ExecuteLive
  defdelegate today_pending_ids(day, tasks, hide_work?), to: ExecuteLive
  defdelegate zone_counts(day, tasks), to: ExecuteLive
  defdelegate unfinished_recent(tasks, current_day), to: ExecuteLive
  defdelegate due_soon_for_today(day, tasks, now), to: ExecuteLive

  # View helpers
  defdelegate recurrence_label(rule), to: ExecuteLive
  defdelegate recurrence_compact(rule), to: ExecuteLive

  def last_done_ago(task, _tasks) do
    case task.last_completed_at do
      nil ->
        "Nunca"

      dt ->
        days = Date.diff(Date.utc_today(), Date.from_iso8601!(String.slice(dt, 0, 10)))

        cond do
          days == 0 -> "Hoy"
          days == 1 -> "Ayer"
          days < 7 -> "#{days} días"
          true -> "#{div(days, 7)} sem"
        end
    end
  end

  def weekly_status(_task, _tasks) do
    # Returns emoji dots for last 7 days: ✅ done, ⏸️ paused/skip, ○ pending
    # Simplified - would need actual history data
    "○○○○○○○"
  end

  def streak_count(task) do
    # Simplified streak calculation
    task.streak || 0
  end

  def planner_tag_rows(tasks, zone, exclude_ids, tag_filter, hidden_ids \\ MapSet.new()) do
    candidates = planner_inventory(tasks, zone, MapSet.new(), exclude_ids, hidden_ids)
    catalog = planner_tag_catalog(candidates)
    selected = tag_filter |> Enum.to_list() |> Tags.normalize_many()

    [%{key: :root, label: "tags:", chips: root_tag_chips(catalog)}] ++
      Enum.flat_map(selected, fn selected_tag ->
        children = direct_children(catalog, selected_tag)

        if children == [] do
          []
        else
          [
            %{
              key: selected_tag,
              label: "tags #{short_tag_label(selected_tag)}:",
              chips:
                Enum.map(children, fn child ->
                  %{
                    full: child,
                    label: child_suffix(selected_tag, child)
                  }
                end)
            }
          ]
        end
      end)
  end

  def planner_kind_label(%{kind: :templates}), do: "recurrent"
  def planner_kind_label(%{from_template: from}) when is_binary(from), do: "instance"
  def planner_kind_label(_task), do: "one-off"

  def planner_kind_class(%{kind: :templates}), do: "bg-emerald-400/20 text-emerald-100"

  def planner_kind_class(%{from_template: from}) when is_binary(from),
    do: "bg-amber-400/20 text-amber-100"

  def planner_kind_class(_task), do: "bg-white/10 text-white/70"

  def planner_state_label(%{kind: :templates, paused: true}), do: "paused"
  def planner_state_label(%{kind: :templates}), do: "active"
  def planner_state_label(_task), do: nil

  def planner_state_class("paused"), do: "bg-white/10 text-white/60"
  def planner_state_class("active"), do: "bg-emerald-500/20 text-emerald-200"

  def planner_meta_badge(nil), do: nil
  def planner_meta_badge(""), do: nil
  def planner_meta_badge(value), do: value

  def planner_display_tags(task) do
    task.tags
    |> visible_task_tags()
    |> Enum.take(4)
  end

  def show_template_metrics?(task), do: task.kind == :templates

  def show_template_pause_badge?(task), do: task.kind == :templates and task.paused

  def created_label(%{frontmatter: %{"created_at" => created_at}}) when is_binary(created_at),
    do: created_at

  def created_label(_task), do: nil

  def created_relative(task) do
    case created_label(task) do
      nil ->
        nil

      created_at ->
        case Date.from_iso8601(created_at) do
          {:ok, date} ->
            days = Date.diff(Date.utc_today(), date)

            cond do
              days <= 0 -> "creada: hoy"
              days == 1 -> "creada: ayer"
              days < 7 -> "creada: hace #{days} días"
              true -> "creada: hace #{div(days, 7)} sem"
            end

          _ ->
            nil
        end
    end
  end

  def priority_icon_class("high"), do: "text-red-300"
  def priority_icon_class("med"), do: "text-amber-300"
  def priority_icon_class("low"), do: "text-white/35"
  def priority_icon_class(_), do: "text-white/20"

  def priority_icon("high"), do: "↑"
  def priority_icon("med"), do: "="
  def priority_icon("low"), do: "↓"
  def priority_icon(_), do: "·"

  def row_chip_class(chip, tag_filter) do
    if MapSet.member?(tag_filter, chip.full) do
      "bg-amber-300 text-slate-950"
    else
      "bg-white/5 text-white/70 hover:bg-white/10 hover:text-white"
    end
  end

  defp planner_tag_catalog(tasks) do
    tasks
    |> Enum.flat_map(fn task -> visible_task_tags(task.tags || []) end)
    |> Tags.expand_catalog()
  end

  def planner_today_tasks(day, tasks) do
    day
    |> today_pending_ids(tasks, false)
    |> Enum.flat_map(fn id ->
      case tasks[id] do
        nil -> []
        task -> [task]
      end
    end)
  end

  def planner_suggestions(tasks, day, zone, tag_filter, hidden_ids \\ MapSet.new()) do
    planner_inventory(tasks, zone, tag_filter, day.order ++ (day.done || []), hidden_ids)
  end

  def planner_inventory(tasks, zone, tag_filter, exclude_ids, hidden_ids \\ MapSet.new()) do
    tasks
    |> filtered_backlog(zone, tag_filter, exclude_ids)
    |> Enum.reject(&MapSet.member?(hidden_ids, &1.id))
  end

  defp root_tag_chips(catalog) do
    children_map = children_map(catalog)

    catalog
    |> Enum.filter(&(tag_depth(&1) == 1))
    |> Enum.sort_by(fn tag ->
      has_children? = Map.get(children_map, tag, []) != []
      {if(has_children?, do: 0, else: 1), String.downcase(tag)}
    end)
    |> Enum.map(fn tag -> %{full: tag, label: tag} end)
  end

  defp direct_children(catalog, parent) do
    catalog
    |> children_map()
    |> Map.get(parent, [])
  end

  defp children_map(catalog) do
    Enum.reduce(catalog, %{}, fn tag, acc ->
      case parent_tag(tag) do
        nil ->
          Map.put_new(acc, tag, [])

        parent ->
          acc
          |> Map.update(parent, [tag], fn children -> Enum.uniq([tag | children]) end)
          |> Map.put_new(tag, [])
      end
    end)
    |> Enum.into(%{}, fn {parent, children} ->
      {parent, Enum.sort_by(children, &String.downcase/1)}
    end)
  end

  defp parent_tag(tag) do
    case String.split(tag, ">", trim: true) do
      [_single] -> nil
      parts -> parts |> Enum.drop(-1) |> Enum.join(">")
    end
  end

  defp child_suffix(parent, child) do
    child
    |> String.replace_prefix(parent <> ">", "")
  end

  defp short_tag_label(tag) do
    tag
    |> String.split(">", trim: true)
    |> List.last()
  end

  defp tag_depth(tag) do
    tag
    |> String.split(">", trim: true)
    |> length()
  end
end
