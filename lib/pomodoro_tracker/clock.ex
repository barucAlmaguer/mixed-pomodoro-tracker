defmodule PomodoroTracker.Clock do
  @moduledoc """
  Local wall-clock helpers for date-sensitive product behavior.

  The app is used as a personal local-first tool, so product concepts like
  "today" should follow the machine's local date instead of UTC rollover.
  """

  def now do
    NaiveDateTime.from_erl!(:calendar.local_time())
  end

  def today do
    now()
    |> NaiveDateTime.to_date()
  end
end
