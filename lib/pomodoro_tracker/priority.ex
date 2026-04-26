defmodule PomodoroTracker.Priority do
  @moduledoc """
  Surfaces tasks that need attention soon based on `due_at` and (later)
  `lead_time_minutes`. Pure functions so they're easy to test and call from
  views.

  The `due_at` field on a task frontmatter is an ISO 8601 datetime string,
  parsed with `NaiveDateTime.from_iso8601/1` (local time, no timezone math —
  matches the rest of the app which already runs on local time).
  """

  @default_threshold_minutes 120

  @doc """
  Returns tasks from `tasks_in_today` whose due_at is within `threshold_minutes`
  of `now`, sorted ascending by due time. Already-overdue tasks come first.
  """
  def due_soon(
        tasks_in_today,
        %NaiveDateTime{} = now,
        threshold_minutes \\ @default_threshold_minutes
      ) do
    tasks_in_today
    |> Enum.flat_map(fn t ->
      case parse_due(t.due_at) do
        nil -> []
        dt -> [{t, NaiveDateTime.diff(dt, now, :minute)}]
      end
    end)
    |> Enum.filter(fn {_t, mins} -> mins <= threshold_minutes end)
    |> Enum.sort_by(fn {_t, mins} -> mins end)
  end

  @doc """
  Human-readable "in 1h 23m" / "vence ya" / "5m tarde" string.
  """
  def humanize_minutes(mins) when is_integer(mins) do
    cond do
      mins < -60 ->
        "#{div(-mins, 60)}h tarde"

      mins < 0 ->
        "#{-mins}m tarde"

      mins == 0 ->
        "vence ya"

      mins < 60 ->
        "#{mins}m"

      true ->
        h = div(mins, 60)
        m = rem(mins, 60)
        if m == 0, do: "#{h}h", else: "#{h}h #{m}m"
    end
  end

  defp parse_due(nil), do: nil
  defp parse_due(""), do: nil

  defp parse_due(str) when is_binary(str) do
    case NaiveDateTime.from_iso8601(str) do
      {:ok, dt} -> dt
      _ -> parse_due_date_only(str)
    end
  end

  defp parse_due(_), do: nil

  defp parse_due_date_only(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> NaiveDateTime.new!(d, ~T[23:59:00])
      _ -> nil
    end
  end
end
