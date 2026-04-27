defmodule PomodoroTrackerWeb.DayLiveHistoryTest do
  use PomodoroTrackerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PomodoroTracker.{Timer, Vault}

  setup do
    Timer.reset()
    {tmp_work, tmp_personal} = make_tmp_vaults()
    prior = Application.get_env(:pomodoro_tracker, :vaults)

    Application.put_env(:pomodoro_tracker, :vaults,
      work: tmp_work,
      personal: tmp_personal,
      subdir: "pomodoro-tracker"
    )

    on_exit(fn ->
      Timer.reset()
      Application.put_env(:pomodoro_tracker, :vaults, prior)
      File.rm_rf!(Path.dirname(tmp_work))
    end)

    :ok
  end

  test "historical day is readonly and can bring task to today without rewriting history", %{
    conn: conn
  } do
    yesterday = Date.add(Date.utc_today(), -1)

    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "carry-me",
        title: "Carry me forward",
        priority: "med",
        tags: ["hogar"]
      })

    {:ok, _} =
      Vault.save_day(%{
        date: yesterday,
        order: ["carry-me"],
        active: ["carry-me"],
        done: [],
        pomodoros: %{}
      })

    {:ok, view, _html} = live(conn, "/?date=#{Date.to_iso8601(yesterday)}")

    assert render(view) =~ "Readonly historical day"
    refute render(view) =~ "Start work"

    view
    |> element(~s([phx-click="day:bring_to_today"][phx-value-id="carry-me"]))
    |> render_click()

    {:ok, historical_day} = Vault.load_day(yesterday)
    {:ok, today_day} = Vault.load_day()

    assert "carry-me" in historical_day.order
    assert "carry-me" in today_day.order
  end

  test "historical day can cancel a pending task without deleting the task file", %{conn: conn} do
    yesterday = Date.add(Date.utc_today(), -1)

    {:ok, _} =
      Vault.create_task(:work, :backlog, %{
        id: "cancel-me",
        title: "Cancel me in history",
        priority: "high",
        tags: ["review"]
      })

    {:ok, _} =
      Vault.save_day(%{
        date: yesterday,
        order: ["cancel-me"],
        active: ["cancel-me"],
        done: [],
        pomodoros: %{}
      })

    {:ok, view, _html} = live(conn, "/?date=#{Date.to_iso8601(yesterday)}")

    view
    |> element(~s([phx-click="day:cancel_historical"][phx-value-id="cancel-me"]))
    |> render_click()

    {:ok, historical_day} = Vault.load_day(yesterday)

    refute "cancel-me" in historical_day.order
    refute "cancel-me" in historical_day.active
    assert File.exists?(Path.join(Vault.dir(:work, :backlog), "cancel-me.md"))
  end

  defp make_tmp_vaults do
    base = Path.join(System.tmp_dir!(), "pomo-history-#{System.unique_integer([:positive])}")
    work = Path.join(base, "work")
    personal = Path.join(base, "personal")

    for root <- [work, personal],
        kind <- ["templates", "backlog", "days", "sessions"] do
      File.mkdir_p!(Path.join([root, "pomodoro-tracker", kind]))
    end

    {work, personal}
  end
end
