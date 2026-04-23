defmodule PomodoroTracker.Vault do
  @moduledoc """
  Reads and writes tasks, day plans, and session logs as Markdown files with
  YAML frontmatter inside two Obsidian vaults (work + personal).

  Each vault has a `pomodoro-tracker/` subdir with:

    templates/  - task templates (reusable definitions)
    backlog/    - discovered but not-yet-scheduled tasks
    days/       - YYYY-MM-DD.md, today's ordered plan
    sessions/   - YYYY-MM-DD.md, append-only pomodoro log
  """

  require Logger

  @type zone :: :work | :personal
  @type task :: %{
          id: String.t(),
          title: String.t(),
          zone: zone,
          priority: String.t() | nil,
          tags: [String.t()],
          source: String.t() | nil,
          source_id: String.t() | nil,
          related: [String.t()],
          recurrence: String.t() | nil,
          duration_hint: String.t() | nil,
          kind: :template | :backlog,
          path: String.t(),
          body: String.t()
        }

  # ---------------------------------------------------------------------------
  # Paths
  # ---------------------------------------------------------------------------

  def vault_root(:work), do: get_in(vaults(), [:work])
  def vault_root(:personal), do: get_in(vaults(), [:personal])

  def subdir(zone), do: Path.join(vault_root(zone), vaults()[:subdir])

  def dir(zone, kind)
      when kind in [:templates, :backlog, :days, :sessions],
      do: Path.join(subdir(zone), Atom.to_string(kind))

  defp vaults, do: Application.fetch_env!(:pomodoro_tracker, :vaults)

  # ---------------------------------------------------------------------------
  # Listing tasks
  # ---------------------------------------------------------------------------

  @doc "Returns all tasks (templates + backlog) across both zones."
  def list_all_tasks do
    for zone <- [:work, :personal],
        kind <- [:templates, :backlog],
        task <- list_tasks(zone, kind) do
      task
    end
  end

  def list_tasks(zone, kind) when kind in [:templates, :backlog] do
    dir = dir(zone, kind)
    File.mkdir_p!(dir)

    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.flat_map(fn path ->
      case read_task(path, zone, kind) do
        {:ok, task} -> [task]
        {:error, reason} ->
          Logger.warning("skip #{path}: #{inspect(reason)}")
          []
      end
    end)
  end

  def read_task(path, zone, kind) do
    with {:ok, raw} <- File.read(path),
         {:ok, fm, body} <- parse_frontmatter(raw) do
      id = fm["id"] || Path.basename(path, ".md")

      task = %{
        id: id,
        title: fm["title"] || id,
        zone: zone,
        priority: fm["priority"],
        tags: fm["tags"] || [],
        source: fm["source"],
        source_id: fm["source_id"],
        related: fm["related"] || [],
        recurrence: fm["recurrence"],
        duration_hint: fm["duration_hint"],
        from_template: fm["from_template"],
        kind: kind,
        path: path,
        body: body,
        frontmatter: fm
      }

      {:ok, task}
    end
  end

  # ---------------------------------------------------------------------------
  # Writing tasks
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new task file in the given zone/kind. `attrs` must include
  `:id` and `:title`. Returns `{:ok, path}` or `{:error, reason}`.
  """
  def create_task(zone, kind, attrs) when kind in [:templates, :backlog] do
    id = Map.fetch!(attrs, :id)
    path = Path.join(dir(zone, kind), "#{id}.md")

    if File.exists?(path) do
      {:error, :already_exists}
    else
      write_task_file(path, attrs)
      {:ok, path}
    end
  end

  @doc """
  Creates a task file if it doesn't exist — used by sync to avoid duplicates.
  Returns `:created | :exists`.
  """
  def upsert_task(zone, kind, attrs) when kind in [:templates, :backlog] do
    id = Map.fetch!(attrs, :id)
    path = Path.join(dir(zone, kind), "#{id}.md")

    if File.exists?(path) do
      :exists
    else
      write_task_file(path, attrs)
      :created
    end
  end

  def delete_task(path) do
    File.rm(path)
  end

  defp write_task_file(path, attrs) do
    body = Map.get(attrs, :body, "")
    fm = attrs |> Map.drop([:body]) |> stringify_keys()

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render(fm, body))
  end

  # ---------------------------------------------------------------------------
  # Day plan
  # ---------------------------------------------------------------------------

  @doc "Path for today's plan (lives in personal vault — single source of truth)."
  def day_path(date \\ Date.utc_today()) do
    Path.join(dir(:personal, :days), "#{Date.to_iso8601(date)}.md")
  end

  def load_day(date \\ Date.utc_today()) do
    path = day_path(date)

    case File.read(path) do
      {:ok, raw} ->
        case parse_frontmatter(raw) do
          {:ok, fm, _body} ->
            {:ok,
             %{
               date: date,
               order: fm["order"] || [],
               active: fm["active"] || [],
               done: fm["done"] || [],
               pomodoros: fm["pomodoros"] || %{},
               path: path
             }}

          err ->
            err
        end

      {:error, :enoent} ->
        {:ok,
         %{date: date, order: [], active: [], done: [], pomodoros: %{}, path: path}}

      other ->
        other
    end
  end

  def save_day(%{date: date, order: order, active: active, pomodoros: pomos} = day) do
    path = Map.get(day, :path, day_path(date))

    fm = %{
      "date" => Date.to_iso8601(date),
      "order" => order,
      "active" => active,
      "done" => Map.get(day, :done, []),
      "pomodoros" => pomos
    }

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render(fm, ""))
    {:ok, path}
  end

  @doc """
  Updates a task file in place. `attrs` is a map of frontmatter keys to merge
  (e.g. `%{title: "New", priority: "high", related: [...]}`) plus an optional
  `:body` key.
  """
  def update_task(path, attrs) do
    with {:ok, raw} <- File.read(path),
         {:ok, fm, body} <- parse_frontmatter(raw) do
      body_attrs = Map.take(attrs, [:body])
      frontmatter_attrs = Map.drop(attrs, [:body])

      new_fm =
        fm
        |> Map.merge(stringify_keys(frontmatter_attrs))

      new_body = Map.get(body_attrs, :body, body)

      File.write!(path, render(new_fm, new_body))
      :ok
    end
  end

  @doc """
  Instantiates a template into a dated backlog task. Idempotent: if today's
  instance already exists, returns its id without rewriting.

  Returns `{:ok, new_id}`.
  """
  def instantiate_template(%{kind: :templates} = tpl, date \\ Date.utc_today()) do
    date_suffix = date |> Date.to_iso8601() |> String.replace("-", "")
    new_id = "#{tpl.id}-#{date_suffix}"
    path = Path.join(dir(tpl.zone, :backlog), "#{new_id}.md")

    if File.exists?(path) do
      {:ok, new_id}
    else
      attrs =
        tpl.frontmatter
        |> Map.drop(["id"])
        |> Map.merge(%{
          "id" => new_id,
          "from_template" => tpl.id,
          "created_at" => Date.to_iso8601(date)
        })

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, render(attrs, tpl.body || ""))
      {:ok, new_id}
    end
  end

  @doc """
  Copies a backlog task into a template with the same id. If a template with
  that id already exists, returns `{:error, :already_exists}`.
  """
  def promote_to_template(%{kind: :backlog} = task) do
    path = Path.join(dir(task.zone, :templates), "#{task.id}.md")

    if File.exists?(path) do
      {:error, :already_exists}
    else
      fm =
        task.frontmatter
        |> Map.drop(["from_template", "created_at", "source", "source_id"])

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, render(fm, task.body || ""))
      {:ok, path}
    end
  end

  # ---------------------------------------------------------------------------
  # Session log (append-only)
  # ---------------------------------------------------------------------------

  def log_session(entry, date \\ Date.utc_today()) do
    path = Path.join(dir(:personal, :sessions), "#{Date.to_iso8601(date)}.md")
    File.mkdir_p!(Path.dirname(path))

    unless File.exists?(path) do
      File.write!(path, "# Sessions #{Date.to_iso8601(date)}\n\n")
    end

    line =
      "- #{entry[:at] || DateTime.utc_now() |> DateTime.to_iso8601()} " <>
        "#{entry[:phase]} " <>
        "#{entry[:minutes]}min " <>
        "tasks=#{Enum.join(entry[:tasks] || [], ",")}\n"

    File.write!(path, line, [:append])
  end

  # ---------------------------------------------------------------------------
  # Frontmatter parsing / rendering
  # ---------------------------------------------------------------------------

  @fm_re ~r/\A---\r?\n(.*?)\r?\n---\r?\n?(.*)\z/s

  def parse_frontmatter(raw) do
    case Regex.run(@fm_re, raw, capture: :all_but_first) do
      [yaml, body] ->
        case YamlElixir.read_from_string(yaml) do
          {:ok, fm} when is_map(fm) -> {:ok, fm, body}
          {:ok, nil} -> {:ok, %{}, body}
          {:error, reason} -> {:error, {:yaml, reason}}
        end

      nil ->
        {:ok, %{}, raw}
    end
  end

  def render(fm, body) when is_map(fm) do
    "---\n" <> to_yaml(fm) <> "---\n" <> body
  end

  # Minimal YAML emitter — enough for our task schema. Keeps output stable and
  # Obsidian-friendly. Avoids dep on a writer library.
  defp to_yaml(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map_join(fn {k, v} -> emit_entry(to_string(k), v, 0) end)
  end

  defp emit_entry(key, value, indent) do
    pad = String.duplicate("  ", indent)

    cond do
      is_list(value) ->
        if value == [] do
          "#{pad}#{key}: []\n"
        else
          "#{pad}#{key}:\n" <>
            Enum.map_join(value, fn item -> "#{pad}  - #{scalar(item)}\n" end)
        end

      is_map(value) ->
        if map_size(value) == 0 do
          "#{pad}#{key}: {}\n"
        else
          "#{pad}#{key}:\n" <>
            Enum.map_join(value, fn {k, v} -> emit_entry(to_string(k), v, indent + 1) end)
        end

      true ->
        "#{pad}#{key}: #{scalar(value)}\n"
    end
  end

  defp scalar(nil), do: "null"
  defp scalar(v) when is_boolean(v), do: to_string(v)
  defp scalar(v) when is_number(v), do: to_string(v)

  defp scalar(v) when is_binary(v) do
    cond do
      v == "" -> ~s("")
      String.contains?(v, [":", "#", "\n", "\"", "'", "[", "]", "{", "}", ","]) -> inspect(v)
      v =~ ~r/^\s|\s$/ -> inspect(v)
      true -> v
    end
  end

  defp scalar(v), do: inspect(v)

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(v) when is_map(v), do: stringify_keys(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v), do: Atom.to_string(v)
  defp stringify_value(v), do: v
end
