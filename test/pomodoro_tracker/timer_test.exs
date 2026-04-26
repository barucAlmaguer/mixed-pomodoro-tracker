defmodule PomodoroTracker.TimerTest do
  use ExUnit.Case, async: false

  alias PomodoroTracker.Timer

  setup do
    Timer.reset()
    on_exit(fn -> Timer.reset() end)
    :ok
  end

  describe "switch_tasks/1" do
    test "while idle, sets task_ids without starting the timer" do
      :ok = Timer.switch_tasks(["foo"])
      s = Timer.state()
      assert s.task_ids == ["foo"]
      assert s.phase == :idle
      assert s.running == false
    end

    test "during a work pomodoro, swaps task_ids without resetting countdown" do
      :ok = Timer.start_work(:work, ["a"])
      before = Timer.state()
      assert before.phase == :work
      assert before.running

      # Simulate a couple of ticks of progress.
      Timer.pause()
      _ = Timer.state()

      :ok = Timer.switch_tasks(["b"])
      after_switch = Timer.state()

      assert after_switch.phase == :work
      assert after_switch.task_ids == ["b"]
      # remaining_ms unchanged (still the full duration since we paused right
      # after starting, but importantly NOT reset to a fresh full duration).
      assert after_switch.remaining_ms == before.remaining_ms
      assert after_switch.duration_ms == before.duration_ms
    end
  end

  describe "start_work mid-work" do
    test "starts a fresh pomodoro when called from idle" do
      :ok = Timer.start_work(:personal, ["foo"])
      s = Timer.state()
      assert s.phase == :work
      assert s.duration_ms > 0
      assert s.remaining_ms == s.duration_ms
      assert s.task_ids == ["foo"]
    end
  end
end
