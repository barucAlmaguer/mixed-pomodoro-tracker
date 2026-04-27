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
  @type pilar :: :salud | :sustento | :limites | :hogar | :pasatiempos | nil
  @type session :: %{
          phase: :work | :active_break | :passive_break | :long_break,
          minutes: integer(),
          tasks: [String.t()],
          zones: [zone],
          at: NaiveDateTime.t() | nil,
          started_at: NaiveDateTime.t() | nil,
          ended_at: NaiveDateTime.t() | nil
        }
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
          kind: :templates | :backlog,
          path: String.t(),
          body: String.t(),
          # Recurrent planner fields
          pilar: pilar,
          paused: boolean(),
          streak: integer(),
          last_completed_at: String.t() | nil,
          # Priority fields
          due_at: String.t() | nil,
          lead_time_minutes: integer() | nil
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
        {:ok, task} ->
          [task]

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
        due_at: fm["due_at"],
        lead_time_minutes: fm["lead_time_minutes"],
        kind: kind,
        path: path,
        body: body,
        frontmatter: fm,
        # Recurrent planner fields
        pilar: parse_pilar(fm["pilar"]),
        paused: fm["paused"] || false,
        streak: fm["streak"] || 0,
        last_completed_at: fm["last_completed_at"]
      }

      {:ok, task}
    end
  end

  defp parse_pilar(nil), do: nil

  defp parse_pilar(s) when is_binary(s) do
    case String.downcase(s) do
      "salud" -> :salud
      "sustento" -> :sustento
      "limites" -> :limites
      "limites de trabajo" -> :limites
      "hogar" -> :hogar
      "tareas del hogar" -> :hogar
      "pasatiempos" -> :pasatiempos
      _ -> nil
    end
  end

  defp parse_pilar(atom) when is_atom(atom), do: atom

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
    fm = attrs |> Map.drop([:body, :frontmatter]) |> stringify_keys()

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render(fm, body))
  end

  @doc """
  Updates an existing task file. Preserves fields not explicitly changed.
  """
  def save_task(%{path: path} = task) do
    # Read current file to preserve anything not in the task map
    {:ok, current_fm, _current_body} =
      case File.read(path) do
        {:ok, raw} -> parse_frontmatter(raw)
        _ -> {:ok, %{}, ""}
      end

    # Merge current frontmatter with new fields
    new_fm =
      current_fm
      |> Map.merge(stringify_keys(Map.drop(task, [:path, :body, :frontmatter, :kind, :zone])))
      |> Map.merge(%{
        "id" => task.id,
        "title" => task.title
      })

    body = Map.get(task, :body, "")
    File.write!(path, render(new_fm, body))
    :ok
  end

  # ---------------------------------------------------------------------------
  # Day plan
  # ---------------------------------------------------------------------------

  @doc "Path for today's plan (lives in personal vault — single source of truth)."
  def day_path(date \\ Date.utc_today()) do
    Path.join(dir(:personal, :days), "#{Date.to_iso8601(date)}.md")
  end

  @doc "All dates we have day files for, newest first."
  def day_dates do
    dir = dir(:personal, :days)
    File.mkdir_p!(dir)

    dir
    |> File.ls!()
    |> Enum.flat_map(fn name ->
      case Regex.run(~r/^(\d{4}-\d{2}-\d{2})\.md$/, name, capture: :all_but_first) do
        [iso] ->
          case Date.from_iso8601(iso) do
            {:ok, d} -> [d]
            _ -> []
          end

        _ ->
          []
      end
    end)
    |> Enum.sort({:desc, Date})
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
               auto_injected: fm["auto_injected"] || [],
               cadence_ran_for: fm["cadence_ran_for"],
               path: path
             }}

          err ->
            err
        end

      {:error, :enoent} ->
        {:ok,
         %{
           date: date,
           order: [],
           active: [],
           done: [],
           pomodoros: %{},
           auto_injected: [],
           cadence_ran_for: nil,
           path: path
         }}

      other ->
        other
    end
  end

  def save_day(%{date: date, order: order, active: active, pomodoros: pomos} = day) do
    path = Map.get(day, :path, day_path(date))

    fm =
      %{
        "date" => Date.to_iso8601(date),
        "order" => order,
        "active" => active,
        "done" => Map.get(day, :done, []),
        "pomodoros" => pomos
      }
      |> maybe_put("auto_injected", Map.get(day, :auto_injected, []))
      |> maybe_put("cadence_ran_for", Map.get(day, :cadence_ran_for))

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render(fm, ""))
    {:ok, path}
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, []), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

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
      [
        "-",
        "at=#{format_session_time(entry[:at] || entry[:ended_at] || NaiveDateTime.local_now())}",
        "phase=#{entry[:phase]}",
        "minutes=#{entry[:minutes]}",
        "started_at=#{format_session_time(entry[:started_at])}",
        "ended_at=#{format_session_time(entry[:ended_at])}",
        "zones=#{Enum.join(entry[:zones] || [], ",")}",
        "tasks=#{Enum.join(entry[:tasks] || [], ",")}"
      ]
      |> Enum.join(" ")
      |> Kernel.<>("\n")

    File.write!(path, line, [:append])
  end

  @doc "List parsed session log entries for a given date."
  @spec list_sessions(Date.t()) :: [session]
  def list_sessions(date \\ Date.utc_today()) do
    path = Path.join(dir(:personal, :sessions), "#{Date.to_iso8601(date)}.md")

    case File.read(path) do
      {:ok, raw} ->
        raw
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, "- "))
        |> Enum.flat_map(fn line ->
          case parse_session_line(line) do
            nil -> []
            session -> [session]
          end
        end)
        |> Enum.sort_by(
          fn session ->
            session.started_at || session.ended_at || ~N[0000-01-01 00:00:00]
          end,
          fn left, right -> NaiveDateTime.compare(left, right) != :gt end
        )

      {:error, :enoent} ->
        []

      {:error, _reason} ->
        []
    end
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

  defp format_session_time(nil), do: ""
  defp format_session_time(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)

  defp parse_session_line("- " <> rest) do
    if String.contains?(rest, "phase=") do
      parse_kv_session(rest)
    else
      parse_legacy_session(rest)
    end
  end

  defp parse_session_line(_), do: nil

  defp parse_kv_session(rest) do
    fields =
      rest
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reduce(%{}, fn token, acc ->
        case String.split(token, "=", parts: 2) do
          [key, value] -> Map.put(acc, key, value)
          _ -> acc
        end
      end)

    phase = parse_session_phase(fields["phase"])
    minutes = parse_session_minutes(fields["minutes"])
    ended_at = parse_session_time(fields["ended_at"] || fields["at"])
    started_at = parse_session_time(fields["started_at"]) || derive_started_at(ended_at, minutes)

    %{
      at: parse_session_time(fields["at"]) || ended_at,
      phase: phase,
      minutes: minutes,
      tasks: parse_csv(fields["tasks"]),
      zones: parse_zones(fields["zones"]),
      started_at: started_at,
      ended_at: ended_at
    }
  end

  defp parse_legacy_session(rest) do
    case Regex.run(
           ~r/^(?<at>\S+)\s+(?<phase>[a-z_]+)\s+(?<minutes>\d+)min(?:\s+tasks=(?<tasks>.*))?$/,
           rest,
           capture: :all_names
         ) do
      [at, phase, minutes, tasks] ->
        ended_at = parse_session_time(at)
        minutes_int = parse_session_minutes(minutes)

        %{
          at: ended_at,
          phase: parse_session_phase(phase),
          minutes: minutes_int,
          tasks: parse_csv(tasks),
          zones: [],
          started_at: derive_started_at(ended_at, minutes_int),
          ended_at: ended_at
        }

      _ ->
        nil
    end
  end

  defp parse_session_phase(nil), do: :work

  defp parse_session_phase(phase) when is_binary(phase) do
    case phase do
      "work" -> :work
      "active_break" -> :active_break
      "passive_break" -> :passive_break
      "long_break" -> :long_break
      _ -> :work
    end
  end

  defp parse_session_minutes(nil), do: 0
  defp parse_session_minutes(""), do: 0

  defp parse_session_minutes(minutes) when is_binary(minutes) do
    case Integer.parse(minutes) do
      {value, _} -> value
      _ -> 0
    end
  end

  defp parse_session_time(nil), do: nil
  defp parse_session_time(""), do: nil

  defp parse_session_time(value) when is_binary(value) do
    cond do
      match?({:ok, _}, NaiveDateTime.from_iso8601(value)) ->
        {:ok, ndt} = NaiveDateTime.from_iso8601(value)
        ndt

      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        {:ok, dt, _offset} = DateTime.from_iso8601(value)
        DateTime.to_naive(dt)

      true ->
        nil
    end
  end

  defp derive_started_at(nil, _minutes), do: nil

  defp derive_started_at(%NaiveDateTime{} = ended_at, minutes) when is_integer(minutes) do
    NaiveDateTime.add(ended_at, -minutes * 60, :second)
  end

  defp parse_csv(nil), do: []
  defp parse_csv(""), do: []

  defp parse_csv(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_zones(value) do
    value
    |> parse_csv()
    |> Enum.flat_map(fn
      "work" -> [:work]
      "personal" -> [:personal]
      _ -> []
    end)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(v) when is_map(v), do: stringify_keys(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)

  defp stringify_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: Atom.to_string(v)

  defp stringify_value(v), do: v
end
