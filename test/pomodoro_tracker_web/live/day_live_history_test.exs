defmodule PomodoroTrackerWeb.DayLiveHistoryTest do
  use PomodoroTrackerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PomodoroTracker.{Clock, Timer, Vault}
  alias PomodoroTrackerWeb.DayLive

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
    yesterday = Date.add(Clock.today(), -1)

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

    assert render(view) =~ "Readonly review"
    assert render(view) =~ "Seeing: Yesterday"
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
    yesterday = Date.add(Clock.today(), -1)

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

  test "today can move a task to tomorrow and persist dragged count", %{conn: conn} do
    tomorrow = Date.add(Clock.today(), 1)

    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "carry-forward",
        title: "Carry forward",
        priority: "med",
        tags: ["hogar"]
      })

    {:ok, _} =
      Vault.save_day(%{
        date: Clock.today(),
        order: ["carry-forward"],
        active: ["carry-forward"],
        done: [],
        pomodoros: %{}
      })

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s([phx-click="day:defer_to_tomorrow"][phx-value-id="carry-forward"]))
    |> render_click()

    {:ok, today_day} = Vault.load_day()
    {:ok, tomorrow_day} = Vault.load_day(tomorrow)
    [task] = Enum.filter(Vault.list_tasks(:personal, :backlog), &(&1.id == "carry-forward"))

    refute "carry-forward" in today_day.order
    refute "carry-forward" in today_day.active
    assert "carry-forward" in tomorrow_day.order
    assert task.dragged_forward_count == 1

    {:ok, tomorrow_view, _html} = live(conn, "/?date=#{Date.to_iso8601(tomorrow)}")
    assert render(tomorrow_view) =~ "1↪"
  end

  test "execute suggestions surface lead-window recurrents and today plus opens ad-hoc modal", %{
    conn: conn
  } do
    now = NaiveDateTime.from_erl!(:calendar.local_time())
    zone = DayLive.backlog_zone(now, :auto)

    {:ok, _} =
      Vault.create_task(zone, :templates, %{
        id: "agendar-dentista",
        title: "Agendar dentista",
        priority: "high",
        recurrence: %{
          type: "interval",
          every: 1,
          unit: "months",
          anchor_date: Date.to_iso8601(Date.add(Clock.today(), 2)),
          anchor_mode: "calendar",
          lead: %{value: 3, unit: "days"}
        }
      })

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s(button[phx-click="toggle:suggestions"]))
    |> render_click()

    html = render(view)
    assert html =~ "Agendar dentista"
    assert html =~ "toca en 2 días"

    view
    |> element(~s(button[title="Nueva tarea ad-hoc"]))
    |> render_click()

    assert render(view) =~ "New backlog task · #{zone}"
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
