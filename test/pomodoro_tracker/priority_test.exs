defmodule PomodoroTracker.PriorityTest do
  use ExUnit.Case, async: true

  alias PomodoroTracker.Priority

  defp task(id, due_at) do
    %{id: id, title: id, zone: :personal, priority: nil, tags: [], due_at: due_at}
  end

  describe "due_soon/3" do
    test "returns tasks within threshold sorted by due time" do
      now = ~N[2026-04-26 09:00:00]

      tasks = [
        task("a", "2026-04-26T11:00:00"),
        task("b", "2026-04-26T10:00:00"),
        task("c", "2026-04-27T10:00:00"),
        task("d", nil)
      ]

      [{first, mins_a}, {second, mins_b}] = Priority.due_soon(tasks, now, 120)
      assert first.id == "b"
      assert mins_a == 60
      assert second.id == "a"
      assert mins_b == 120
    end

    test "places overdue tasks first" do
      now = ~N[2026-04-26 11:30:00]

      tasks = [
        task("late", "2026-04-26T11:00:00"),
        task("upcoming", "2026-04-26T12:00:00")
      ]

      [{late, late_mins}, {upcoming, _}] = Priority.due_soon(tasks, now, 120)
      assert late.id == "late"
      assert late_mins == -30
      assert upcoming.id == "upcoming"
    end

    test "ignores tasks with no due_at or unparseable due_at" do
      now = ~N[2026-04-26 09:00:00]
      tasks = [task("nope", nil), task("garbage", "tomorrow"), task("ok", "2026-04-26T10:00:00")]
      [{ok, _}] = Priority.due_soon(tasks, now, 120)
      assert ok.id == "ok"
    end

    test "supports date-only due (treats as end of day)" do
      now = ~N[2026-04-26 09:00:00]
      [{t, mins}] = Priority.due_soon([task("eod", "2026-04-26")], now, 24 * 60)
      assert t.id == "eod"
      assert mins > 0
    end
  end

  describe "humanize_minutes/1" do
    test "formats various durations" do
      assert Priority.humanize_minutes(0) == "vence ya"
      assert Priority.humanize_minutes(45) == "45m"
      assert Priority.humanize_minutes(60) == "1h"
      assert Priority.humanize_minutes(90) == "1h 30m"
      assert Priority.humanize_minutes(-15) == "15m tarde"
      assert Priority.humanize_minutes(-90) == "1h tarde"
    end
  end
end
