defmodule PomodoroTracker.TemplateLinks do
  @moduledoc """
  Directed acyclic graph of reusable template follow-ups.

  Relationships are stored canonically as `on_done` on the source template.
  Reverse links (`started_by`) are derived from that graph but editable from
  the UI by rewriting the outgoing edges of the involved templates.
  """

  @type graph :: %{optional(String.t()) => MapSet.t(String.t())}

  def on_done_ids(%{on_done: ids}) when is_list(ids), do: normalize_ids(ids)
  def on_done_ids(%{frontmatter: %{"on_done" => ids}}) when is_list(ids), do: normalize_ids(ids)
  def on_done_ids(_task), do: []

  def candidate_templates(tasks, current_id \\ nil) do
    tasks
    |> Map.values()
    |> Enum.filter(&(&1.kind == :templates))
    |> Enum.reject(&(&1.id == current_id))
    |> Enum.sort_by(fn task -> {String.downcase(task.title || task.id), task.id} end)
  end

  def started_by_ids(tasks, template_id) when is_map(tasks) and is_binary(template_id) do
    tasks
    |> graph()
    |> Enum.flat_map(fn {source_id, targets} ->
      if MapSet.member?(targets, template_id), do: [source_id], else: []
    end)
    |> Enum.sort()
  end

  def graph(tasks) when is_map(tasks) do
    tasks
    |> Map.values()
    |> Enum.filter(&(&1.kind == :templates))
    |> Enum.reduce(%{}, fn task, acc ->
      Map.put(acc, task.id, MapSet.new(on_done_ids(task)))
    end)
  end

  @doc """
  Rewrites the template graph using the edited `on_done` and `started_by`
  selections for a single template. Returns the subset of templates whose
  outgoing edges changed, or `{:error, :cycle}` if the graph would stop being a
  DAG.
  """
  def rewrite(tasks, template_id, on_done_ids, started_by_ids)
      when is_map(tasks) and is_binary(template_id) do
    base_graph = graph(tasks)
    template_ids = base_graph |> Map.keys() |> Enum.uniq() |> Enum.sort()
    graph = Map.put_new(base_graph, template_id, MapSet.new())
    outgoing = MapSet.new(normalize_ids(on_done_ids))
    incoming = MapSet.new(normalize_ids(started_by_ids))

    cond do
      MapSet.member?(outgoing, template_id) or MapSet.member?(incoming, template_id) ->
        {:error, :cycle}

      true ->
        known_ids = graph |> Map.keys() |> MapSet.new()
        refs = MapSet.union(outgoing, incoming)
        unknown = MapSet.difference(refs, known_ids) |> MapSet.to_list() |> Enum.sort()

        if unknown != [] do
          {:error, {:missing_templates, unknown}}
        else
          updated_graph =
            Enum.reduce(template_ids, Map.put(graph, template_id, outgoing), fn other_id, acc ->
              if other_id == template_id do
                acc
              else
                current = Map.get(acc, other_id, MapSet.new()) |> MapSet.delete(template_id)

                next =
                  if MapSet.member?(incoming, other_id),
                    do: MapSet.put(current, template_id),
                    else: current

                Map.put(acc, other_id, next)
              end
            end)

          if dag?(updated_graph) do
            updates =
              updated_graph
              |> Enum.reduce(%{}, fn {id, targets}, acc ->
                normalized = targets |> MapSet.to_list() |> Enum.sort()

                previous =
                  Map.get(base_graph, id, MapSet.new()) |> MapSet.to_list() |> Enum.sort()

                if normalized == previous do
                  acc
                else
                  Map.put(acc, id, normalized)
                end
              end)

            {:ok, updates}
          else
            {:error, :cycle}
          end
        end
    end
  end

  def relation_error_message(:cycle), do: "Task chains must stay acyclic."

  def relation_error_message({:missing_templates, ids}) do
    "Missing linked templates: " <> Enum.join(ids, ", ")
  end

  def relation_error_message(_), do: "Could not save task chain links."

  defp normalize_ids(ids) when is_list(ids) do
    ids
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp dag?(graph) do
    nodes = Map.keys(graph)

    Enum.all?(nodes, fn node ->
      dfs_acyclic?(node, graph, MapSet.new(), MapSet.new())
    end)
  end

  defp dfs_acyclic?(node, graph, visited, stack) do
    cond do
      MapSet.member?(stack, node) ->
        false

      MapSet.member?(visited, node) ->
        true

      true ->
        next_visited = MapSet.put(visited, node)
        next_stack = MapSet.put(stack, node)

        graph
        |> Map.get(node, MapSet.new())
        |> Enum.all?(fn child ->
          dfs_acyclic?(child, graph, next_visited, next_stack)
        end)
    end
  end
end
