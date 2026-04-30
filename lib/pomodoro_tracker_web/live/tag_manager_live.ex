defmodule PomodoroTrackerWeb.TagManagerLive do
  @moduledoc """
  Tag management surface for CRUD and merge operations.
  """

  use PomodoroTrackerWeb, :live_view

  alias PomodoroTracker.{Tags, Vault}
  alias PomodoroTrackerWeb.DayLive, as: ExecuteLive

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Vault.Watcher.topic())
    end

    {:ok,
     socket
     |> assign(:page_title, "Tags")
     |> assign(:zone_filter, :personal)
     |> assign(:new_tag_query, "")
     |> assign(:selected_tags, MapSet.new())
     |> assign(:expanded_tags, MapSet.new())
     |> assign(:renaming_tag, nil)
     |> assign(:rename_value, "")
     |> assign(:delete_tag_dialog, nil)
     |> assign(:merge_dialog, nil)
     |> load_data()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    zone = parse_zone(params["zone"])
    {:noreply, socket |> assign(:zone_filter, zone) |> load_data()}
  end

  @impl true
  def handle_info(:vault_changed, socket), do: {:noreply, load_data(socket)}

  @impl true
  def handle_event("tags:new_change", %{"new_tag_query" => value}, socket) do
    {:noreply, assign(socket, :new_tag_query, value)}
  end

  def handle_event("tags:create", _, socket) do
    tag = Tags.normalize(socket.assigns.new_tag_query)

    if is_nil(tag) do
      {:noreply, put_flash(socket, :error, "Tag required")}
    else
      Vault.register_tags(socket.assigns.zone_filter, [tag])
      {:noreply, socket |> assign(:new_tag_query, "") |> put_flash(:info, "Added tag #{tag}") |> load_data()}
    end
  end

  def handle_event("tags:toggle_select", %{"tag" => tag}, socket) do
    tag = Tags.normalize(tag)

    next =
      if MapSet.member?(socket.assigns.selected_tags, tag) do
        MapSet.delete(socket.assigns.selected_tags, tag)
      else
        MapSet.put(socket.assigns.selected_tags, tag)
      end

    {:noreply, assign(socket, :selected_tags, next)}
  end

  def handle_event("tags:toggle_tasks", %{"tag" => tag}, socket) do
    tag = Tags.normalize(tag)

    next =
      if MapSet.member?(socket.assigns.expanded_tags, tag) do
        MapSet.delete(socket.assigns.expanded_tags, tag)
      else
        MapSet.put(socket.assigns.expanded_tags, tag)
      end

    {:noreply, assign(socket, :expanded_tags, next)}
  end

  def handle_event("tags:rename_open", %{"tag" => tag}, socket) do
    {:noreply, socket |> assign(:renaming_tag, tag) |> assign(:rename_value, tag_suffix(tag))}
  end

  def handle_event("tags:rename_change", %{"rename_value" => value}, socket) do
    {:noreply, assign(socket, :rename_value, value)}
  end

  def handle_event("tags:rename_cancel", _, socket) do
    {:noreply, socket |> assign(:renaming_tag, nil) |> assign(:rename_value, "")}
  end

  def handle_event("tags:rename_submit", %{"tag" => old_tag}, socket) do
    new_tag = rename_target(old_tag, socket.assigns.rename_value)

    case Vault.rename_tag(socket.assigns.zone_filter, old_tag, new_tag) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:renaming_tag, nil)
         |> assign(:rename_value, "")
         |> put_flash(:info, "Renamed #{old_tag} to #{new_tag}")
         |> load_data()}

      {:error, :invalid_tag} ->
        {:noreply, put_flash(socket, :error, "Invalid tag")}
    end
  end

  def handle_event("tags:delete_open", %{"tag" => tag}, socket) do
    preview = delete_tag_preview(socket.assigns.tasks, socket.assigns.tag_catalog, socket.assigns.zone_filter, tag)
    {:noreply, assign(socket, :delete_tag_dialog, preview)}
  end

  def handle_event("tags:delete_cancel", _, socket) do
    {:noreply, assign(socket, :delete_tag_dialog, nil)}
  end

  def handle_event("tags:delete_confirm", %{"tag" => tag}, socket) do
    case Vault.delete_tag(socket.assigns.zone_filter, tag) do
      {:ok, _meta} ->
        {:noreply,
         socket
         |> assign(:delete_tag_dialog, nil)
         |> put_flash(:info, "Deleted tag #{tag}")
         |> load_data()}

      {:error, :invalid_tag} ->
        {:noreply, put_flash(socket, :error, "Invalid tag")}
    end
  end

  def handle_event("tags:merge_open", _, socket) do
    selected = socket.assigns.selected_tags |> Enum.to_list() |> Enum.sort()

    if length(selected) < 2 do
      {:noreply, put_flash(socket, :error, "Select at least 2 tags")}
    else
      target_tag = hd(selected)
      dialog = merge_preview(socket.assigns.tasks, socket.assigns.zone_filter, socket.assigns.tag_catalog, selected, target_tag)
      {:noreply, assign(socket, :merge_dialog, dialog)}
    end
  end

  def handle_event("tags:merge_target_pick", %{"tag" => tag}, socket) do
    case socket.assigns.merge_dialog do
      %{source_tags: source_tags} ->
        dialog =
          merge_preview(
            socket.assigns.tasks,
            socket.assigns.zone_filter,
            socket.assigns.tag_catalog,
            source_tags,
            tag
          )

        {:noreply, assign(socket, :merge_dialog, dialog)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("tags:merge_target_change", %{"target_tag" => tag}, socket) do
    case socket.assigns.merge_dialog do
      %{source_tags: source_tags} ->
        dialog =
          merge_preview(
            socket.assigns.tasks,
            socket.assigns.zone_filter,
            socket.assigns.tag_catalog,
            source_tags,
            tag
          )

        {:noreply, assign(socket, :merge_dialog, dialog)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("tags:merge_cancel", _, socket) do
    {:noreply, assign(socket, :merge_dialog, nil)}
  end

  def handle_event("tags:merge_confirm", params, socket) do
    target_tag = Tags.normalize(params["target_tag"])

    source_tags =
      case socket.assigns.merge_dialog do
        %{source_tags: selected} -> selected
        _ -> socket.assigns.selected_tags |> Enum.to_list() |> Enum.sort()
      end

    cond do
      length(source_tags) < 2 ->
        {:noreply,
         socket
         |> assign(:merge_dialog, nil)
         |> put_flash(:error, "Select at least 2 tags")}

      is_nil(target_tag) ->
        {:noreply, put_flash(socket, :error, "Invalid merge target")}

      true ->
        case Vault.merge_tags(socket.assigns.zone_filter, source_tags, target_tag) do
          {:ok, _meta} ->
            {:noreply,
             socket
             |> assign(:merge_dialog, nil)
             |> assign(:selected_tags, MapSet.new())
             |> put_flash(:info, "Merged into #{target_tag}")
             |> load_data()}

          {:error, :invalid_tag} ->
            {:noreply, put_flash(socket, :error, "Invalid merge target")}
        end
    end
  end

  defp load_data(socket) do
    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    tag_registry = ExecuteLive.merged_tag_registry(tasks)
    zone = socket.assigns.zone_filter
    catalog = zone_catalog(tag_registry, tasks, zone)
    completion_counts = template_completion_counts(tasks)

    socket
    |> assign(:tasks, tasks)
    |> assign(:tag_registry, tag_registry)
    |> assign(:tag_catalog, catalog)
    |> assign(:completion_counts, completion_counts)
    |> assign(:selected_tags, MapSet.intersection(socket.assigns.selected_tags, MapSet.new(catalog)))
    |> assign(:expanded_tags, MapSet.intersection(socket.assigns.expanded_tags, MapSet.new(catalog)))
  end

  def tag_route(params) do
    query =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.map(fn {k, v} -> {k, if(is_atom(v), do: Atom.to_string(v), else: v)} end)
      |> URI.encode_query()

    if query == "", do: "/tags", else: "/tags?" <> query
  end

  def tag_rows(catalog) do
    catalog
    |> Enum.sort_by(&String.downcase/1)
  end

  def row_indent_class(tag) do
    case tag_depth(tag) do
      1 -> ""
      2 -> "pl-6"
      3 -> "pl-10"
      _depth -> "pl-12"
    end
  end

  def direct_task_count(tasks, zone, tag) do
    tasks
    |> Map.values()
    |> Enum.count(fn task ->
      task.zone == zone and tag in visible_task_tags(task)
    end)
  end

  def family_task_count(tasks, zone, tag) do
    if is_nil(tag) do
      0
    else
    tasks
    |> Map.values()
    |> Enum.count(fn task ->
      task.zone == zone and Enum.any?(visible_task_tags(task), fn task_tag -> Tags.matches?(tag, [task_tag]) end)
    end)
    end
  end

  def family_task_count_for_target(tasks, zone, tag) do
    family_task_count(tasks, zone, tag)
  end

  def linked_tasks(tasks, zone, tag) do
    tasks
    |> Map.values()
    |> Enum.filter(fn task ->
      task.zone == zone and
        Enum.any?(visible_task_tags(task), fn task_tag -> Tags.matches?(tag, [task_tag]) end)
    end)
    |> Enum.sort_by(fn task ->
      {task_kind_rank(task), String.downcase(task.title || ""), task.id}
    end)
  end

  def linked_task_kind(%{kind: :templates}), do: "recurrent"
  def linked_task_kind(%{from_template: from}) when is_binary(from), do: nil
  def linked_task_kind(_task), do: "one-off"

  def linked_task_last_done(nil), do: "Nunca"
  def linked_task_last_done(""), do: "Nunca"

  def linked_task_last_done(dt) when is_binary(dt) do
    days = Date.diff(Date.utc_today(), Date.from_iso8601!(String.slice(dt, 0, 10)))

    cond do
      days == 0 -> "Hoy"
      days == 1 -> "Ayer"
      days < 7 -> "#{days} días"
      true -> "#{div(days, 7)} sem"
    end
  end

  def linked_task_done_count(completion_counts, %{kind: :templates, id: id}) do
    Map.get(completion_counts, id, 0)
  end

  def linked_task_done_count(_completion_counts, _task), do: nil

  def descendant_count(catalog, tag) do
    Enum.count(catalog, fn candidate ->
      candidate != tag and String.starts_with?(candidate, tag <> ">")
    end)
  end

  def tag_suffix(tag) do
    tag
    |> String.split(">", trim: true)
    |> List.last()
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

  def delete_tag_preview(tasks, catalog, zone, tag) do
    normalized = Tags.normalize(tag)

    %{
      tag: normalized,
      tasks_affected: family_task_count(tasks, zone, normalized),
      descendants: descendant_count(catalog, normalized)
    }
  end

  def merge_preview(tasks, zone, catalog, source_tags, target_tag) do
    target_tag = Tags.normalize(target_tag)

    %{
      source_tags: source_tags |> Tags.normalize_many(),
      target_tag: target_tag,
      target_exists?: target_tag in catalog,
      target_existing_tasks: family_task_count_for_target(tasks, zone, target_tag),
      tasks_affected:
        source_tags
        |> Enum.map(&family_task_count(tasks, zone, &1))
        |> Enum.sum()
    }
  end

  defp parse_zone("work"), do: :work
  defp parse_zone("personal"), do: :personal
  defp parse_zone(_), do: :personal

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

  defp tag_depth(tag), do: String.split(tag, ">", trim: true) |> length()

  defp parent_tag(tag) do
    case String.split(tag, ">", trim: true) do
      [_single] -> nil
      parts -> parts |> Enum.drop(-1) |> Enum.join(">")
    end
  end

  defp task_kind_rank(%{kind: :templates}), do: 0
  defp task_kind_rank(%{from_template: from}) when is_binary(from), do: 2
  defp task_kind_rank(_task), do: 1

  defp template_completion_counts(tasks) do
    template_ids =
      tasks
      |> Map.values()
      |> Enum.filter(&(&1.kind == :templates))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    Vault.day_dates()
    |> Enum.reduce(%{}, fn date, acc ->
      case Vault.load_day(date) do
        {:ok, day} ->
          Enum.reduce(day.done || [], acc, fn done_id, counts ->
            case tasks[done_id] do
              %{from_template: template_id} ->
                if MapSet.member?(template_ids, template_id) do
                  Map.update(counts, template_id, 1, &(&1 + 1))
                else
                  counts
                end

              _ ->
                counts
            end
          end)

        _ ->
          acc
      end
    end)
  end
end
