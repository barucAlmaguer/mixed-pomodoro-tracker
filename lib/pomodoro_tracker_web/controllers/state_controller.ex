defmodule PomodoroTrackerWeb.StateController do
  @moduledoc """
  Read-only JSON endpoint for the menubar / external clients (Hammerspoon,
  scripts). Returns the live snapshot of timer + today + next deadline so
  small clients don't need to mount a LiveView socket.
  """

  use PomodoroTrackerWeb, :controller

  alias PomodoroTracker.{Cadence, Priority, Timer, Vault}

  def show(conn, _params) do
    now = NaiveDateTime.from_erl!(:calendar.local_time())

    tasks_list = Vault.list_all_tasks()
    tasks = Map.new(tasks_list, &{&1.id, &1})
    {:ok, day} = Vault.load_day()
    day = Cadence.ensure_run!(day, tasks, NaiveDateTime.to_date(now))

    timer = Timer.state()

    pending =
      day.order
      |> Enum.reject(&(&1 in (day.done || [])))
      |> Enum.flat_map(&task_summary(&1, tasks, day))

    [first_due | _] =
      day.order
      |> Enum.flat_map(fn id ->
        case tasks[id] do
          nil -> []
          t -> [t]
        end
      end)
      |> Priority.due_soon(now)
      |> Kernel.++([nil])

    json(conn, %{
      now: NaiveDateTime.to_iso8601(now),
      timer: %{
        phase: timer.phase,
        zone: timer.zone,
        running: timer.running,
        remaining_ms: timer.remaining_ms,
        duration_ms: timer.duration_ms,
        task_ids: timer.task_ids
      },
      day: %{
        date: Date.to_iso8601(day.date),
        pending_count: length(pending),
        done_count: length(day.done || []),
        active: day.active,
        pending: pending
      },
      next_due: format_due(first_due)
    })
  end

  defp task_summary(id, tasks, day) do
    case tasks[id] do
      nil ->
        []

      t ->
        [
          %{
            id: t.id,
            title: t.title,
            zone: t.zone,
            priority: t.priority,
            due_at: t.due_at,
            pomodoros: Map.get(day.pomodoros, t.id, 0),
            auto_injected: t.id in (day.auto_injected || [])
          }
        ]
    end
  end

  defp format_due(nil), do: nil

  defp format_due({t, mins}) do
    %{
      id: t.id,
      title: t.title,
      due_at: t.due_at,
      minutes: mins,
      humanized: Priority.humanize_minutes(mins)
    }
  end
end
