defmodule PomodoroTrackerWeb.HabitTrackerLive do
  @moduledoc """
  Habit tracking surface aggregated by hierarchical tags.
  """

  use PomodoroTrackerWeb, :live_view

  alias PomodoroTracker.{Tags, Vault}
  alias PomodoroTrackerWeb.DayLive, as: ExecuteLive

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Vault.Watcher.topic())
    end

    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, "Habits")
     |> assign(:zone_filter, :personal)
     |> assign(:scale, :daily)
     |> assign(:selected_tag, nil)
     |> assign(:month, Date.beginning_of_month(today))
     |> assign(:year, today.year)
     |> assign(:task_sections_open, MapSet.new())
     |> assign(:child_tag_query, "")
     |> assign(:renaming_tag, nil)
     |> assign(:rename_value, "")
     |> assign(:task_form, nil)
     |> assign(:delete_tag_dialog, nil)
     |> load_data()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    today = Date.utc_today()
    zone = parse_zone(params["zone"])
    scale = parse_scale(params["scale"])
    month = parse_month(params["month"], today)
    year = parse_year(params["year"], today.year)

    {:noreply,
     socket
     |> assign(:zone_filter, zone)
     |> assign(:scale, scale)
     |> assign(:selected_tag, Tags.normalize(params["tag"]))
     |> assign(:month, month)
     |> assign(:year, year)
     |> load_data()}
  end

  @impl true
  def handle_info(:vault_changed, socket), do: {:noreply, load_data(socket)}

  @impl true
  def handle_event("habit:add_child_change", %{"child_tag_query" => value}, socket) do
    {:noreply, assign(socket, :child_tag_query, value)}
  end

  def handle_event("habit:toggle_tasks", %{"tag" => tag}, socket) do
    tag = Tags.normalize(tag)

    next =
      if MapSet.member?(socket.assigns.task_sections_open, tag) do
        MapSet.delete(socket.assigns.task_sections_open, tag)
      else
        MapSet.put(socket.assigns.task_sections_open, tag)
      end

    {:noreply, assign(socket, :task_sections_open, next)}
  end

  def handle_event("habit:add_child", _, socket) do
    zone = socket.assigns.zone_filter
    parent = socket.assigns.selected_tag
    suffix = String.trim(socket.assigns.child_tag_query || "")

    cond do
      is_nil(parent) ->
        {:noreply, socket}

      suffix == "" ->
        {:noreply, put_flash(socket, :error, "Child tag required")}

      true ->
        new_tag = build_child_tag(parent, suffix)
        Vault.register_tags(zone, [new_tag])

        {:noreply,
         socket
         |> assign(:child_tag_query, "")
         |> put_flash(:info, "Added tag #{new_tag}")
         |> load_data()}
    end
  end

  def handle_event("habit:rename_open", %{"tag" => tag}, socket) do
    {:noreply,
     socket
     |> assign(:renaming_tag, tag)
     |> assign(:rename_value, tag_suffix(tag))}
  end

  def handle_event("habit:rename_cancel", _, socket) do
    {:noreply, socket |> assign(:renaming_tag, nil) |> assign(:rename_value, "")}
  end

  def handle_event("habit:rename_change", %{"rename_value" => value}, socket) do
    {:noreply, assign(socket, :rename_value, value)}
  end

  def handle_event("habit:rename_submit", %{"tag" => old_tag}, socket) do
    zone = socket.assigns.zone_filter
    new_tag = rename_target(old_tag, socket.assigns.rename_value || "")

    case Vault.rename_tag(zone, old_tag, new_tag) do
      {:ok, _} ->
        selected_tag =
          if socket.assigns.selected_tag == old_tag, do: new_tag, else: socket.assigns.selected_tag

        {:noreply,
         socket
         |> assign(:selected_tag, selected_tag)
         |> assign(:renaming_tag, nil)
         |> assign(:rename_value, "")
         |> put_flash(:info, "Renamed #{old_tag} to #{new_tag}")
         |> load_data()}

      {:error, :invalid_tag} ->
        {:noreply, put_flash(socket, :error, "Invalid tag name")}
    end
  end

  def handle_event("habit:new_task_open", %{"tag" => tag}, socket) do
    zone = socket.assigns.zone_filter

    form =
      ExecuteLive.task_form_defaults(:templates, zone, %{
        tags: [tag],
        habit_tag: tag,
        recurrence_type: "daily"
      })

    {:noreply, assign(socket, :task_form, form)}
  end

  def handle_event("habit:new_task_close", _, socket) do
    {:noreply, assign(socket, :task_form, nil)}
  end

  def handle_event("habit:new_task_change", %{"task" => params}, socket) do
    {:noreply, assign(socket, :task_form, ExecuteLive.apply_task_form_params(socket.assigns.task_form, params))}
  end

  def handle_event("habit:new_task_toggle_weekday", %{"day" => day}, socket) do
    {:noreply, assign(socket, :task_form, ExecuteLive.toggle_task_form_weekday(socket.assigns.task_form, day))}
  end

  def handle_event("habit:new_task_submit", _, socket) do
    form = socket.assigns.task_form
    title = String.trim(form.title || "")

    cond do
      is_nil(form) ->
        {:noreply, socket}

      title == "" ->
        {:noreply, put_flash(socket, :error, "Title required")}

      true ->
        id = slugify(title)
        attrs =
          %{
            id: id,
            title: title,
            zone: form.zone,
            priority: form.priority,
            tags: Tags.normalize_many([form.habit_tag]),
            body: form.body || "",
            related: [],
            on_done: []
          }
          |> ExecuteLive.maybe_put_task_recurrence(form)

        case Vault.create_task(form.zone, :templates, attrs) do
          {:ok, _path} ->
            {:noreply,
             socket
             |> assign(:task_form, nil)
             |> put_flash(:info, "Created task #{title}")
             |> load_data()}

          {:error, :already_exists} ->
            {:noreply, put_flash(socket, :error, "A task with that id already exists")}
        end
    end
  end

  def handle_event("habit:delete_tag_open", %{"tag" => tag}, socket) do
    tag = Tags.normalize(tag)
    preview = delete_tag_preview(socket.assigns.tasks, socket.assigns.tag_catalog, socket.assigns.zone_filter, tag)
    {:noreply, assign(socket, :delete_tag_dialog, preview)}
  end

  def handle_event("habit:delete_tag_cancel", _, socket) do
    {:noreply, assign(socket, :delete_tag_dialog, nil)}
  end

  def handle_event("habit:delete_tag_confirm", %{"tag" => tag}, socket) do
    case Vault.delete_tag(socket.assigns.zone_filter, tag) do
      {:ok, _meta} ->
        selected_tag =
          if socket.assigns.selected_tag == tag or String.starts_with?(socket.assigns.selected_tag || "", tag <> ">") do
            parent_tag(tag)
          else
            socket.assigns.selected_tag
          end

        {:noreply,
         socket
         |> assign(:selected_tag, selected_tag)
         |> assign(:delete_tag_dialog, nil)
         |> put_flash(:info, "Deleted tag #{tag}")
         |> load_data()}

      {:error, :invalid_tag} ->
        {:noreply, put_flash(socket, :error, "Invalid tag")}
    end
  end

  defp load_data(socket) do
    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    tag_registry = ExecuteLive.merged_tag_registry(tasks)
    zone = socket.assigns.zone_filter
    catalog = zone_catalog(tag_registry, tasks, zone)
    top_tags = root_tags(catalog)
    selected_tag = normalize_selected_tag(socket.assigns.selected_tag, catalog, top_tags)
    activity = habit_activity(tasks, zone)
    task_activity = task_habit_activity(tasks, zone)

    socket
    |> assign(:tasks, tasks)
    |> assign(:tag_registry, tag_registry)
    |> assign(:tag_catalog, catalog)
    |> assign(:top_tags, top_tags)
    |> assign(:selected_tag, selected_tag)
    |> assign(:activity, activity)
    |> assign(:task_activity, task_activity)
  end

  defp normalize_selected_tag(nil, _catalog, [first | _]), do: first
  defp normalize_selected_tag(nil, _catalog, []), do: nil

  defp normalize_selected_tag(tag, catalog, top_tags) do
    tag = Tags.normalize(tag)

    cond do
      is_nil(tag) and top_tags != [] -> hd(top_tags)
      tag in catalog -> tag
      true -> List.first(top_tags)
    end
  end

  defp parse_zone("work"), do: :work
  defp parse_zone("personal"), do: :personal
  defp parse_zone(_), do: :personal

  defp parse_scale("weekly"), do: :weekly
  defp parse_scale("daily"), do: :daily
  defp parse_scale(_), do: :daily

  defp parse_month(nil, today), do: Date.beginning_of_month(today)
  defp parse_month("", today), do: Date.beginning_of_month(today)

  defp parse_month(raw, today) do
    with [year, month] <- String.split(raw, "-", parts: 2),
         {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {:ok, date} <- Date.new(year, month, 1) do
      date
    else
      _ -> Date.beginning_of_month(today)
    end
  end

  defp parse_year(nil, fallback), do: fallback
  defp parse_year("", fallback), do: fallback

  defp parse_year(raw, fallback) do
    case Integer.parse(raw) do
      {year, ""} -> year
      _ -> fallback
    end
  end

  def habit_route(params) do
    query =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.map(fn {k, v} -> {k, query_value(v)} end)
      |> URI.encode_query()

    if query == "", do: "/habits", else: "/habits?" <> query
  end

  def selected_month_label(%Date{} = month), do: Calendar.strftime(month, "%B %Y")
  def selected_year_label(year) when is_integer(year), do: Integer.to_string(year)

  def previous_month(%Date{} = month), do: month |> Date.add(-1) |> Date.beginning_of_month()
  def next_month(%Date{} = month), do: month |> Date.end_of_month() |> Date.add(1)

  def year_daily_total(activity, tag, year) do
    activity
    |> daily_counts_for(tag)
    |> Enum.count(fn {date, count} -> date.year == year and count > 0 end)
  end

  def child_tags(catalog, selected_tag) when is_binary(selected_tag) do
    direct_children(catalog, selected_tag)
  end

  def child_tags(_catalog, _selected_tag), do: []

  def branch_tags(_catalog, nil), do: []

  def branch_tags(catalog, selected_tag) do
    [selected_tag | direct_children(catalog, selected_tag)]
  end

  def month_columns(activity, tag, %Date{} = month) when is_binary(tag) do
    counts = daily_counts_for(activity, tag)
    first = Date.beginning_of_month(month)
    last = Date.end_of_month(month)
    start_date = Date.add(first, -(Date.day_of_week(first) - 1))
    end_date = Date.add(last, 7 - Date.day_of_week(last))

    date_range(start_date, end_date)
    |> Enum.chunk_every(7)
    |> Enum.map(fn week ->
      Enum.map(week, fn date ->
        count = Map.get(counts, date, 0)

        %{
          date: date,
          count: count,
          current_month?: date.month == month.month and date.year == month.year,
          future?: Date.compare(date, Date.utc_today()) == :gt,
          title: month_cell_title(tag, date, count)
        }
      end)
    end)
  end

  def month_columns(_activity, _tag, _month), do: []

  def task_month_columns(task_activity, task, %Date{} = month) do
    task
    |> task_daily_counts(task_activity)
    |> counts_month_columns(task.title || task.id, month)
  end

  def task_month_columns(_task_activity, _task, _month), do: []

  def year_week_columns(activity, tag, year) when is_binary(tag) do
    counts = daily_counts_for(activity, tag)
    first = Date.new!(year, 1, 1)
    last = Date.new!(year, 12, 31)
    start_date = Date.add(first, -(Date.day_of_week(first) - 1))
    end_date = Date.add(last, 7 - Date.day_of_week(last))

    date_range(start_date, end_date)
    |> Enum.chunk_every(7)
    |> Enum.map(fn week ->
      week_start = hd(week)
      week_end = List.last(week)

      count =
        Enum.reduce(week, 0, fn date, total ->
          total + Map.get(counts, date, 0)
        end)

      %{
        start_date: week_start,
        end_date: week_end,
        count: count,
        current_year?: Enum.any?(week, &(&1.year == year)),
        future?: Date.compare(week_start, Date.utc_today()) == :gt,
        title: week_cell_title(tag, week_start, week_end, count)
      }
    end)
    |> Enum.chunk_every(4)
  end

  def year_week_columns(_activity, _tag, _year), do: []

  def task_year_week_columns(task_activity, task, year) when is_integer(year) do
    task
    |> task_daily_counts(task_activity)
    |> counts_year_week_columns(task.title || task.id, year)
  end

  def task_year_week_columns(_task_activity, _task, _year), do: []

  def heat_cell_class(%{count: count, current_month?: true}) when count > 0,
    do: "bg-blue-400 shadow-[0_0_0_1px_rgba(147,197,253,0.22)]"

  def heat_cell_class(%{count: _count, current_month?: false, future?: true}),
    do: "bg-white/[0.03]"

  def heat_cell_class(%{count: count, current_month?: false}) when count > 0,
    do: "bg-blue-400/40"

  def heat_cell_class(%{future?: true}), do: "bg-white/[0.04]"
  def heat_cell_class(_cell), do: "bg-white/[0.10]"

  def week_cell_class(%{count: count, current_year?: true}) when count > 0,
    do: "bg-blue-400 shadow-[0_0_0_1px_rgba(147,197,253,0.22)]"

  def week_cell_class(%{count: count, current_year?: false}) when count > 0,
    do: "bg-blue-400/35"

  def week_cell_class(%{future?: true}), do: "bg-white/[0.04]"
  def week_cell_class(_cell), do: "bg-white/[0.10]"

  def habit_activity(tasks, zone) do
    Vault.day_dates()
    |> Enum.reduce(%{}, fn date, acc ->
      case Vault.load_day(date) do
        {:ok, day} ->
          Enum.reduce(day.done || [], acc, fn id, acc2 ->
            case tasks[id] do
              %{zone: ^zone} = task ->
                task
                |> visible_task_tags()
                |> Tags.expand_catalog()
                |> Enum.reduce(acc2, fn tag, tag_acc ->
                  update_in(tag_acc, [Access.key(tag, %{}), Access.key(date, 0)], &((&1 || 0) + 1))
                end)

              _ ->
                acc2
            end
          end)

        _ ->
          acc
      end
    end)
  end

  def task_total_done(task_activity, task) do
    task
    |> task_daily_counts(task_activity)
    |> Map.values()
    |> Enum.sum()
  end

  def task_last_done(task_activity, task) do
    task
    |> task_daily_counts(task_activity)
    |> Enum.filter(fn {_date, count} -> count > 0 end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.max_by(&Date.to_gregorian_days/1, fn -> nil end)
  end

  def rename_target(old_tag, raw_value) do
    value = Tags.normalize(raw_value)

    cond do
      is_nil(value) ->
        old_tag

      String.contains?(value, ">") ->
        value

      true ->
        case parent_tag(old_tag) do
          nil -> value
          parent -> parent <> ">" <> value
        end
    end
  end

  defp daily_counts_for(activity, tag) do
    Map.get(activity, tag, %{})
  end

  defp zone_catalog(tag_registry, tasks, zone) do
    discovered =
      tasks
      |> Map.values()
      |> Enum.filter(&(&1.zone == zone))
      |> Enum.flat_map(&visible_task_tags/1)

    tag_registry
    |> Map.get(zone, [])
    |> Tags.registry_seed(discovered)
    |> Tags.expand_catalog()
  end

  defp visible_task_tags(task) do
    task.tags
    |> Tags.normalize_many()
    |> Enum.reject(&(&1 == "break"))
  end

  defp root_tags(catalog) do
    catalog
    |> Enum.filter(&(tag_depth(&1) == 1))
    |> Enum.sort_by(&String.downcase/1)
  end

  defp direct_children(catalog, parent) do
    catalog
    |> Enum.filter(fn tag ->
      parent_tag(tag) == parent
    end)
    |> Enum.sort_by(&String.downcase/1)
  end

  defp parent_tag(tag) do
    case String.split(tag, ">", trim: true) do
      [_single] -> nil
      parts -> parts |> Enum.drop(-1) |> Enum.join(">")
    end
  end

  def tag_suffix(tag) do
    tag
    |> String.split(">", trim: true)
    |> List.last()
  end

  defp tag_depth(tag), do: String.split(tag, ">", trim: true) |> length()

  def child_count(catalog, tag) do
    direct_children(catalog, tag) |> length()
  end

  def descendant_count(catalog, tag) do
    catalog
    |> Enum.count(fn candidate ->
      candidate != tag and String.starts_with?(candidate, tag <> ">")
    end)
  end

  def direct_tag_tasks(tasks, zone, tag) when is_binary(tag) do
    tasks
    |> Map.values()
    |> Enum.filter(fn task ->
      task.zone == zone and tag in visible_task_tags(task)
    end)
    |> Enum.group_by(&task_family_key/1)
    |> Enum.map(fn {_family, family} -> Enum.min_by(family, &{direct_task_kind_rank(&1), String.downcase(&1.title || &1.id), &1.id}) end)
    |> Enum.sort_by(fn task ->
      {direct_task_kind_rank(task), String.downcase(task.title || task.id)}
    end)
  end

  def direct_tag_tasks(_tasks, _zone, _tag), do: []

  def task_section_open?(open_set, tag), do: MapSet.member?(open_set, tag)

  def direct_task_kind_label(%{kind: :templates, recurrence: nil}), do: "manual"
  def direct_task_kind_label(%{kind: :templates}), do: "recurrente"
  def direct_task_kind_label(%{from_template: from}) when is_binary(from), do: "instancia"
  def direct_task_kind_label(_task), do: "one-off"

  def direct_task_kind_class(%{kind: :templates, recurrence: nil}), do: "bg-white/10 text-white/65"
  def direct_task_kind_class(%{kind: :templates}), do: "bg-blue-400/20 text-blue-100"
  def direct_task_kind_class(%{from_template: from}) when is_binary(from), do: "bg-amber-400/20 text-amber-100"
  def direct_task_kind_class(_task), do: "bg-white/10 text-white/65"

  def delete_tag_preview(tasks, catalog, zone, tag) do
    affected_tasks =
      tasks
      |> Map.values()
      |> Enum.filter(fn task ->
        task.zone == zone and Enum.any?(visible_task_tags(task), fn t -> t == tag or String.starts_with?(t, tag <> ">") end)
      end)

    %{
      tag: tag,
      tasks_affected: length(affected_tasks),
      descendants: descendant_count(catalog, tag)
    }
  end

  def build_child_tag(parent, suffix) do
    suffix =
      suffix
      |> String.replace(">", " ")
      |> Tags.normalize()

    parent <> ">" <> suffix
  end

  defp date_range(start_date, end_date) do
    0..Date.diff(end_date, start_date)
    |> Enum.map(&Date.add(start_date, &1))
  end

  defp month_cell_title(tag, date, count) do
    "#{tag} · #{Date.to_iso8601(date)} · #{count_label(count)}"
  end

  defp week_cell_title(tag, start_date, end_date, count) do
    "#{tag} · #{Date.to_iso8601(start_date)} → #{Date.to_iso8601(end_date)} · #{count_label(count)}"
  end

  defp count_label(1), do: "1 done"
  defp count_label(count), do: "#{count} done"

  defp query_value(%Date{} = value), do: Date.to_iso8601(value) |> String.slice(0, 7)
  defp query_value(value) when is_atom(value), do: Atom.to_string(value)
  defp query_value(value), do: value

  defp direct_task_kind_rank(%{kind: :templates, recurrence: nil}), do: 1
  defp direct_task_kind_rank(%{kind: :templates}), do: 0
  defp direct_task_kind_rank(%{from_template: from}) when is_binary(from), do: 2
  defp direct_task_kind_rank(_task), do: 3

  defp task_habit_activity(tasks, zone) do
    Vault.day_dates()
    |> Enum.reduce(%{}, fn date, acc ->
      case Vault.load_day(date) do
        {:ok, day} ->
          Enum.reduce(day.done || [], acc, fn id, acc2 ->
            case tasks[id] do
              %{zone: ^zone} = task ->
                key = task_family_key(task)
                update_in(acc2, [Access.key(key, %{}), Access.key(date, 0)], &((&1 || 0) + 1))

              _ ->
                acc2
            end
          end)

        _ ->
          acc
      end
    end)
  end

  defp task_family_key(%{kind: :templates, id: id}), do: {:template, id}
  defp task_family_key(%{from_template: template_id}) when is_binary(template_id), do: {:template, template_id}
  defp task_family_key(%{id: id}), do: {:task, id}

  defp task_daily_counts(task, task_activity) do
    Map.get(task_activity, task_family_key(task), %{})
  end

  defp counts_month_columns(counts, label, %Date{} = month) do
    first = Date.beginning_of_month(month)
    last = Date.end_of_month(month)
    start_date = Date.add(first, -(Date.day_of_week(first) - 1))
    end_date = Date.add(last, 7 - Date.day_of_week(last))

    date_range(start_date, end_date)
    |> Enum.chunk_every(7)
    |> Enum.map(fn week ->
      Enum.map(week, fn date ->
        count = Map.get(counts, date, 0)

        %{
          date: date,
          count: count,
          current_month?: date.month == month.month and date.year == month.year,
          future?: Date.compare(date, Date.utc_today()) == :gt,
          title: month_cell_title(label, date, count)
        }
      end)
    end)
  end

  defp counts_year_week_columns(counts, label, year) when is_integer(year) do
    first = Date.new!(year, 1, 1)
    last = Date.new!(year, 12, 31)
    start_date = Date.add(first, -(Date.day_of_week(first) - 1))
    end_date = Date.add(last, 7 - Date.day_of_week(last))

    date_range(start_date, end_date)
    |> Enum.chunk_every(7)
    |> Enum.map(fn week ->
      week_start = hd(week)
      week_end = List.last(week)

      count =
        Enum.reduce(week, 0, fn date, total ->
          total + Map.get(counts, date, 0)
        end)

      %{
        start_date: week_start,
        end_date: week_end,
        count: count,
        current_year?: Enum.any?(week, &(&1.year == year)),
        future?: Date.compare(week_start, Date.utc_today()) == :gt,
        title: week_cell_title(label, week_start, week_end, count)
      }
    end)
    |> Enum.chunk_every(4)
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 60)
  end
end
