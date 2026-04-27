defmodule PomodoroTrackerWeb.DayLivePomodoroAttributionTest do
  use PomodoroTrackerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PomodoroTracker.{Timer, Vault}

  setup do
    Timer.reset()
    {tmp_work, tmp_personal} = make_tmp_vaults()
    prior_vaults = Application.get_env(:pomodoro_tracker, :vaults)
    prior_hours = Application.get_env(:pomodoro_tracker, :work_hours)

    Application.put_env(:pomodoro_tracker, :vaults,
      work: tmp_work,
      personal: tmp_personal,
      subdir: "pomodoro-tracker"
    )

    Application.put_env(:pomodoro_tracker, :work_hours,
      start: 0,
      stop: 24,
      weekdays: [1, 2, 3, 4, 5, 6, 7]
    )

    on_exit(fn ->
      Timer.reset()
      Application.put_env(:pomodoro_tracker, :vaults, prior_vaults)
      Application.put_env(:pomodoro_tracker, :work_hours, prior_hours)
      File.rm_rf!(Path.dirname(tmp_work))
    end)

    :ok
  end

  test "work pomodoro can start without active task and becomes mixed once a personal task is assigned",
       %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "fold-laundry",
        title: "Fold laundry",
        priority: "med",
        tags: ["hogar"]
      })

    {:ok, _} =
      Vault.save_day(%{
        date: Date.utc_today(),
        order: ["fold-laundry"],
        active: [],
        done: [],
        pomodoros: %{}
      })

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s(button[phx-click="timer:start_work"]))
    |> render_click()

    assert %{phase: :work, task_ids: [], zones: [:work]} = Timer.state()

    view
    |> element(~s(button[phx-click="day:toggle_active"][phx-value-id="fold-laundry"]))
    |> render_click()

    assert Enum.sort(Timer.state().zones) == [:personal, :work]

    view
    |> element(~s(button[phx-click="timer:skip"]))
    |> render_click()

    [session] = Vault.list_sessions()
    assert session.phase == :work
    assert session.tasks == ["fold-laundry"]
    assert Enum.sort(session.zones) == [:personal, :work]

    {:ok, day} = Vault.load_day()
    assert day.pomodoros["fold-laundry"] == 1
  end

  test "active break only classifies as personal once a personal task is actually selected",
       %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "stretch-neck",
        title: "Stretch neck",
        priority: "low",
        tags: ["salud"]
      })

    {:ok, _} =
      Vault.save_day(%{
        date: Date.utc_today(),
        order: ["stretch-neck"],
        active: [],
        done: [],
        pomodoros: %{}
      })

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s(button[phx-click="timer:break"][phx-value-kind="active_break"]))
    |> render_click()

    assert %{phase: :active_break, zones: []} = Timer.state()

    view
    |> element(~s(button[phx-click="day:toggle_active"][phx-value-id="stretch-neck"]), "pick")
    |> render_click()

    assert Timer.state().zones == [:personal]

    view
    |> element(~s(button[phx-click="timer:skip"]))
    |> render_click()

    [session] = Vault.list_sessions()
    assert session.phase == :active_break
    assert session.tasks == ["stretch-neck"]
    assert session.zones == [:personal]
  end

  defp make_tmp_vaults do
    base =
      Path.join(System.tmp_dir!(), "pomo-attribution-#{System.unique_integer([:positive])}")

    work = Path.join(base, "work")
    personal = Path.join(base, "personal")

    for root <- [work, personal],
        kind <- ["templates", "backlog", "days", "sessions"] do
      File.mkdir_p!(Path.join([root, "pomodoro-tracker", kind]))
    end

    {work, personal}
  end
end
