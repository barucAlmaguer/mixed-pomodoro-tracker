defmodule PomodoroTracker.CadenceTest do
  use ExUnit.Case, async: false

  alias PomodoroTracker.{Cadence, Vault}

  setup do
    {tmp_work, tmp_personal} = make_tmp_vaults()

    prior = Application.get_env(:pomodoro_tracker, :vaults)

    Application.put_env(:pomodoro_tracker, :vaults,
      work: tmp_work,
      personal: tmp_personal,
      subdir: "pomodoro-tracker"
    )

    on_exit(fn ->
      Application.put_env(:pomodoro_tracker, :vaults, prior)
      File.rm_rf!(Path.dirname(tmp_work))
    end)

    :ok
  end

  defp make_tmp_vaults do
    base = Path.join(System.tmp_dir!(), "pomo-cadence-#{System.unique_integer([:positive])}")
    work = Path.join(base, "work")
    personal = Path.join(base, "personal")
    File.mkdir_p!(Path.join(work, "pomodoro-tracker/templates"))
    File.mkdir_p!(Path.join(work, "pomodoro-tracker/backlog"))
    File.mkdir_p!(Path.join(work, "pomodoro-tracker/days"))
    File.mkdir_p!(Path.join(personal, "pomodoro-tracker/templates"))
    File.mkdir_p!(Path.join(personal, "pomodoro-tracker/backlog"))
    File.mkdir_p!(Path.join(personal, "pomodoro-tracker/days"))
    {work, personal}
  end

  defp template(zone, id, title, attrs) do
    fm =
      %{
        "id" => id,
        "title" => title,
        "zone" => Atom.to_string(zone),
        "tags" => []
      }
      |> Map.merge(Map.new(attrs, fn {k, v} -> {to_string(k), v} end))

    Vault.create_task(zone, :templates, fm |> Map.new(fn {k, v} -> {String.to_atom(k), v} end))
  end

  test "auto-injects daily templates and writes cadence_ran_for marker" do
    {:ok, _} =
      template(:personal, "feed-dogs-am", "Dar de comer perritos AM", recurrence: "daily")

    {:ok, _} = template(:personal, "rare-task", "Tarea ad-hoc", [])

    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    {:ok, day} = Vault.load_day(~D[2026-04-26])

    new_day = Cadence.ensure_run!(day, tasks, ~D[2026-04-26])

    assert new_day.cadence_ran_for == "2026-04-26"
    assert "feed-dogs-am-20260426" in new_day.order
    refute "rare-task" in new_day.order
    assert "feed-dogs-am-20260426" in new_day.auto_injected
  end

  test "is idempotent on second run" do
    {:ok, _} =
      template(:personal, "feed-dogs-am", "Dar de comer perritos AM", recurrence: "daily")

    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    {:ok, day} = Vault.load_day(~D[2026-04-26])

    once = Cadence.ensure_run!(day, tasks, ~D[2026-04-26])
    twice = Cadence.ensure_run!(once, tasks, ~D[2026-04-26])

    assert once.order == twice.order
    assert once.auto_injected == twice.auto_injected
  end

  test "respects user-removed tasks within the same day (does not re-inject)" do
    {:ok, _} =
      template(:personal, "feed-dogs-am", "Dar de comer perritos AM", recurrence: "daily")

    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    {:ok, day} = Vault.load_day(~D[2026-04-26])

    after_run = Cadence.ensure_run!(day, tasks, ~D[2026-04-26])
    user_removed = %{after_run | order: List.delete(after_run.order, "feed-dogs-am-20260426")}
    Vault.save_day(user_removed)

    {:ok, reloaded} = Vault.load_day(~D[2026-04-26])
    final = Cadence.ensure_run!(reloaded, tasks, ~D[2026-04-26])

    refute "feed-dogs-am-20260426" in final.order
  end

  test "weekly:mon does not run on Tuesday" do
    {:ok, _} = template(:personal, "stretch", "Stretch", recurrence: "weekly:mon")

    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    # 2026-04-21 is a Tuesday
    {:ok, day} = Vault.load_day(~D[2026-04-21])
    new_day = Cadence.ensure_run!(day, tasks, ~D[2026-04-21])

    refute Enum.any?(new_day.order, &String.starts_with?(&1, "stretch-"))
  end
end
