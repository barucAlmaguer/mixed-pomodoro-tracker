defmodule PomodoroTracker.RecurrenceTest do
  use ExUnit.Case, async: true

  alias PomodoroTracker.Recurrence

  describe "normalize/1" do
    test "keeps supporting legacy daily and weekly strings" do
      assert Recurrence.normalize("daily") == %{type: :daily}
      assert Recurrence.normalize("weekdays") == %{type: :weekly, weekdays: [1, 2, 3, 4, 5]}
      assert Recurrence.normalize("weekly") == %{type: :weekly, weekdays: [1, 2, 3, 4, 5]}
      assert Recurrence.normalize("weekly:tue,thu") == %{type: :weekly, weekdays: [2, 4]}
      assert Recurrence.normalize("garbage") == nil
    end

    test "normalizes structured interval maps" do
      recurrence =
        Recurrence.normalize(%{
          "type" => "interval",
          "every" => 1,
          "unit" => "months",
          "anchor_date" => "2026-04-25",
          "anchor_mode" => "calendar",
          "lead" => %{"value" => 0, "unit" => "days"}
        })

      assert recurrence == %{
               type: :interval,
               every: 1,
               unit: :months,
               anchor_date: ~D[2026-04-25],
               anchor_mode: :calendar,
               lead: nil
             }
    end
  end

  describe "should_run?/3" do
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

    test "weekly defaults to weekdays" do
      assert Recurrence.should_run?("weekly", ~D[2026-04-20])
      assert Recurrence.should_run?("weekly", ~D[2026-04-24])
      refute Recurrence.should_run?("weekly", ~D[2026-04-25])
      refute Recurrence.should_run?("weekly", ~D[2026-04-26])
    end

    test "weekly with explicit days stays exact" do
      rule = "weekly:mon,wed,fri"
      assert Recurrence.should_run?(rule, ~D[2026-04-20])
      refute Recurrence.should_run?(rule, ~D[2026-04-21])
      assert Recurrence.should_run?(rule, ~D[2026-04-22])
      refute Recurrence.should_run?(rule, ~D[2026-04-23])
      assert Recurrence.should_run?(rule, ~D[2026-04-24])
      refute Recurrence.should_run?(rule, ~D[2026-04-25])
    end

    test "calendar intervals can pop early" do
      recurrence = %{
        "type" => "interval",
        "every" => 1,
        "unit" => "years",
        "anchor_date" => "2026-11-16",
        "anchor_mode" => "calendar",
        "lead" => %{"value" => 1, "unit" => "months"}
      }

      assert Recurrence.should_run?(recurrence, ~D[2026-10-16])
      refute Recurrence.should_run?(recurrence, ~D[2026-11-16])
    end

    test "completion intervals use last_completed_at as the reset point" do
      recurrence = %{
        "type" => "interval",
        "every" => 28,
        "unit" => "days",
        "anchor_date" => "2026-04-15",
        "anchor_mode" => "completion"
      }

      assert Recurrence.should_run?(recurrence, ~D[2026-05-13], %{last_completed_at: "2026-04-15"})

      refute Recurrence.should_run?(recurrence, ~D[2026-05-05], %{last_completed_at: "2026-04-15"})
    end

    test "completion intervals fall back to anchor_date when never completed" do
      recurrence = %{
        "type" => "interval",
        "every" => 1,
        "unit" => "months",
        "anchor_date" => "2026-05-05",
        "anchor_mode" => "completion"
      }

      assert Recurrence.should_run?(recurrence, ~D[2026-06-05], %{last_completed_at: nil})
      refute Recurrence.should_run?(recurrence, ~D[2026-05-05], %{last_completed_at: nil})
    end
  end
end
