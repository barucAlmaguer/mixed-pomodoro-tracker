defmodule PomodoroTracker.RecurrenceTest do
  use ExUnit.Case, async: true

  alias PomodoroTracker.Recurrence

  describe "should_run?/2" do
    test "nil and empty rules never run" do
      d = ~D[2026-04-26]
      refute Recurrence.should_run?(nil, d)
      refute Recurrence.should_run?("", d)
      refute Recurrence.should_run?("garbage", d)
    end

    test "daily runs every day" do
      for d <- [~D[2026-04-20], ~D[2026-04-25], ~D[2026-04-26]] do
        assert Recurrence.should_run?("daily", d)
      end
    end

    test "weekdays runs Mon-Fri only" do
      # 2026-04-20 is Mon, 25 Sat, 26 Sun, 27 Mon
      assert Recurrence.should_run?("weekdays", ~D[2026-04-20])
      refute Recurrence.should_run?("weekdays", ~D[2026-04-25])
      refute Recurrence.should_run?("weekdays", ~D[2026-04-26])
      assert Recurrence.should_run?("weekdays", ~D[2026-04-27])
    end

    test "weekly without days defaults to Monday" do
      assert Recurrence.should_run?("weekly", ~D[2026-04-20])
      refute Recurrence.should_run?("weekly", ~D[2026-04-21])
    end

    test "weekly:mon,wed,fri" do
      rule = "weekly:mon,wed,fri"
      assert Recurrence.should_run?(rule, ~D[2026-04-20])
      refute Recurrence.should_run?(rule, ~D[2026-04-21])
      assert Recurrence.should_run?(rule, ~D[2026-04-22])
      refute Recurrence.should_run?(rule, ~D[2026-04-23])
      assert Recurrence.should_run?(rule, ~D[2026-04-24])
      refute Recurrence.should_run?(rule, ~D[2026-04-25])
    end

    test "case + spacing tolerant" do
      assert Recurrence.should_run?("  Daily  ", ~D[2026-04-26])
      assert Recurrence.should_run?("Weekly:Mon, Wed", ~D[2026-04-20])
    end

    test "weekly with unknown day tokens returns unknown" do
      refute Recurrence.should_run?("weekly:funday", ~D[2026-04-20])
    end
  end

  describe "parse/1" do
    test "returns structured rules" do
      assert Recurrence.parse("daily") == :daily
      assert Recurrence.parse("weekdays") == :weekdays
      assert Recurrence.parse("weekly") == {:weekly, [1]}
      assert Recurrence.parse("weekly:tue,thu") == {:weekly, [2, 4]}
      assert Recurrence.parse("garbage") == :unknown
    end
  end
end
