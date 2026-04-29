defmodule PomodoroTracker.Cadence do
  @moduledoc """
  Auto-injects recurring template instances into the day plan.

  Idempotent per day: writes a `cadence_ran_for: YYYY-MM-DD` marker in the day
  file so we don't re-inject tasks the user explicitly removed.

  Tasks that were auto-injected get listed in `auto_injected:` so the UI can
  render a 🔁 marker.
  """

  alias PomodoroTracker.{Recurrence, Vault}

  @doc """
  Ensures cadence has run for today. Returns the (possibly updated) `day`
  struct. Persists changes to disk if anything was injected.

  `tasks` is a map of id → task for templates+backlog (matches DayLive's
  `assigns.tasks`). The function reads templates from there to avoid a second
  vault scan.
  """
  def ensure_run!(day, tasks, date \\ Date.utc_today()) do
    if Map.get(day, :cadence_ran_for) == Date.to_iso8601(date) do
      day
    else
      inject_for_today!(day, tasks, date)
    end
  end

  defp inject_for_today!(day, tasks, date) do
    existing = MapSet.new(day.order ++ (day.done || []))

    {new_order, new_auto, instantiated_any?} =
      tasks
      |> Map.values()
      |> Enum.filter(&template_for?(&1, date))
      |> Enum.reduce({day.order, day_auto_injected(day), false}, fn tpl, {order, auto, _any?} ->
        {:ok, instance_id} = Vault.instantiate_template(tpl, date)

        cond do
          MapSet.member?(existing, instance_id) ->
            {order, auto, false}

          instance_id in order ->
            {order, auto, true}

          true ->
            {order ++ [instance_id], [instance_id | auto], true}
        end
      end)

    new_day =
      day
      |> Map.put(:order, new_order)
      |> Map.put(:auto_injected, Enum.uniq(new_auto))
      |> Map.put(:cadence_ran_for, Date.to_iso8601(date))

    if instantiated_any? or new_day.cadence_ran_for != Map.get(day, :cadence_ran_for) do
      Vault.save_day(new_day)
    end

    new_day
  end

  defp template_for?(%{kind: :templates, paused: true}, _date), do: false

  defp template_for?(%{kind: :templates, recurrence: rule} = template, date),
    do: Recurrence.should_run?(rule, date, template)

  defp template_for?(_, _), do: false

  defp day_auto_injected(day), do: List.wrap(Map.get(day, :auto_injected, []))
end
