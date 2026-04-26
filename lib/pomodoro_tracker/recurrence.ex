defmodule PomodoroTracker.Recurrence do
  @moduledoc """
  Pure logic for "should this template run on a given date?".

  Recurrence rules live in template frontmatter as a single string:

      recurrence: daily
      recurrence: weekdays
      recurrence: weekly:mon,wed,fri
      recurrence: weekly                 # treated as 'mondays'

  Anything else (or missing) means the template is one-shot — never auto-injected.
  Future rules like `every:12h` or `times_per_day:2` will be added when needed.
  """

  @weekday_atoms %{
    "mon" => 1,
    "tue" => 2,
    "wed" => 3,
    "thu" => 4,
    "fri" => 5,
    "sat" => 6,
    "sun" => 7
  }

  @doc """
  Returns true if the template should be auto-injected on `date`.
  `rule` is the raw frontmatter string (or nil).
  """
  def should_run?(nil, _date), do: false
  def should_run?("", _date), do: false

  def should_run?(rule, %Date{} = date) when is_binary(rule) do
    weekday = Date.day_of_week(date)

    case parse(rule) do
      :daily -> true
      :weekdays -> weekday in 1..5
      {:weekly, days} -> weekday in days
      :unknown -> false
    end
  end

  @doc "Parses a recurrence rule into a structured term."
  def parse(rule) when is_binary(rule) do
    case String.trim(rule) |> String.downcase() do
      "daily" ->
        :daily

      "weekdays" ->
        weekday_only_for_legacy()

      "weekly" ->
        {:weekly, [1]}

      "weekly:" <> days ->
        days
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.flat_map(fn d -> Map.get(@weekday_atoms, d, []) |> List.wrap() end)
        |> case do
          [] -> :unknown
          list -> {:weekly, Enum.sort(list)}
        end

      _ ->
        :unknown
    end
  end

  defp weekday_only_for_legacy, do: :weekdays
end
