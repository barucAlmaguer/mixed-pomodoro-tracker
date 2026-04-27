defmodule PomodoroTrackerWeb.PlannerLiveTest do
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

  test "planner renders real templates and product navigation", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "stretch-neck",
        title: "Stretch neck",
        tags: ["ejercicio", "ejercicio>cuello"],
        recurrence: "daily"
      })

    {:ok, view, _html} = live(conn, "/planner")

    assert has_element?(view, "#planner-nav")
    assert has_element?(view, "#planner-nav-execute")
    assert has_element?(view, "#planner-nav-plan")
    assert render(view) =~ "Stretch neck"
  end

  test "planner can add backlog work into today", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:work, :backlog, %{
        id: "fix-build",
        title: "Fix build",
        priority: "high",
        tags: ["review"]
      })

    {:ok, view, _html} = live(conn, "/planner")

    view
    |> element(~s(button[title="Add to today"][phx-value-id="fix-build"]))
    |> render_click()

    {:ok, day} = Vault.load_day()
    assert "fix-build" in day.order
  end

  test "execute view links out to planner and no longer renders backlog header", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#open-planner-cta")
    assert render(view) =~ "Planning Lives In Plan"
  end

  defp make_tmp_vaults do
    base = Path.join(System.tmp_dir!(), "pomo-planner-#{System.unique_integer([:positive])}")
    work = Path.join(base, "work")
    personal = Path.join(base, "personal")

    for root <- [work, personal],
        kind <- ["templates", "backlog", "days", "sessions"] do
      File.mkdir_p!(Path.join([root, "pomodoro-tracker", kind]))
    end

    {work, personal}
  end
end
