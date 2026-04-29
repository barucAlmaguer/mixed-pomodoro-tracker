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

  test "planner renders unified inventory and product navigation", %{conn: conn} do
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
    refute has_element?(view, "#planner-templates")
    assert render(view) =~ "Planning Inventory"
    assert render(view) =~ "Stretch neck"
    assert render(view) =~ "template"
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
    |> element(~s(button[phx-click="filter:zone"][phx-value-zone="work"]))
    |> render_click()

    view
    |> element(~s(button[title="Add to today"][phx-value-id="fix-build"]))
    |> render_click()

    {:ok, day} = Vault.load_day()
    assert "fix-build" in day.order
  end

  test "planner surfaces parent filter chips and child rows for nested tags", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "stretch-neck",
        title: "Stretch neck",
        tags: ["ejercicio>cuello"]
      })

    {:ok, view, _html} = live(conn, "/planner")

    view
    |> element(~s(button[phx-click="filter:zone"][phx-value-zone="personal"]))
    |> render_click()

    assert has_element?(view, ~s(button[phx-click="filter:tag"][phx-value-tag="ejercicio"]))

    view
    |> element(~s(button[phx-click="filter:tag"][phx-value-tag="ejercicio"]))
    |> render_click()

    assert render(view) =~ "tags ejercicio:"

    assert has_element?(
             view,
             ~s(button[phx-click="filter:tag"][phx-value-tag="ejercicio>cuello"])
           )

    assert render(view) =~ "Stretch neck"
  end

  test "planner does not show duplicate template when today's instance already exists", %{
    conn: conn
  } do
    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "stretch-neck",
        title: "Stretch neck",
        tags: ["ejercicio>cuello"]
      })

    {:ok, new_id} =
      Vault.instantiate_template(%{
        kind: :templates,
        id: "stretch-neck",
        zone: :personal,
        frontmatter: %{"title" => "Stretch neck", "tags" => ["ejercicio>cuello"]},
        body: ""
      })

    {:ok, day} = Vault.load_day()
    {:ok, _} = Vault.save_day(%{day | order: [new_id]})

    {:ok, view, _html} = live(conn, "/planner")

    view
    |> element(~s(button[phx-click="filter:zone"][phx-value-zone="personal"]))
    |> render_click()

    refute has_element?(view, ~s(button[title="Add to today"][phx-value-id="stretch-neck"]))
    assert render(view) =~ "Stretch neck"
  end

  test "planner creates nested tags and registers them in yaml", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/planner")

    view
    |> element(~s(button[phx-click="filter:zone"][phx-value-zone="personal"]))
    |> render_click()

    view
    |> element(
      ~s(button[phx-click="new:open"][phx-value-kind="backlog"][phx-value-zone="personal"])
    )
    |> render_click()

    view
    |> form("form[phx-submit='new:submit']", %{
      "task" => %{
        "title" => "Eye exercises",
        "priority" => "med",
        "tag_query" => "ejercicio>ojos"
      }
    })
    |> render_change()

    view
    |> element(~s(button[phx-click="new:add_tag"]))
    |> render_click()

    view
    |> form("form[phx-submit='new:submit']", %{
      "task" => %{
        "title" => "Eye exercises",
        "priority" => "med",
        "tag_query" => ""
      }
    })
    |> render_submit()

    tasks = Vault.list_tasks(:personal, :backlog)
    assert Enum.any?(tasks, &(&1.id == "eye-exercises" and &1.tags == ["ejercicio>ojos"]))

    assert Vault.list_registered_tags(:personal) == ["ejercicio>ojos"]
  end

  test "planner multi-tag filtering combines parent and flat tags", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "groom-dogs",
        title: "Acicalar perritas",
        tags: ["perritos>aseo", "patio"]
      })

    {:ok, view, _html} = live(conn, "/planner")

    view
    |> element(~s(button[phx-click="filter:zone"][phx-value-zone="personal"]))
    |> render_click()

    view
    |> element(~s(button[phx-click="filter:tag"][phx-value-tag="perritos"]))
    |> render_click()

    view
    |> element(~s(button[phx-click="filter:tag"][phx-value-tag="patio"]))
    |> render_click()

    assert render(view) =~ "Acicalar perritas"
  end

  test "finished one-off tasks are hidden from planning inventory and shown in archive", %{
    conn: conn
  } do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "done-once",
        title: "Already done",
        priority: "med",
        tags: ["hogar"]
      })

    {:ok, day} = Vault.load_day()
    {:ok, _} = Vault.save_day(%{day | order: [], done: ["done-once"]})

    {:ok, view, _html} = live(conn, "/planner")

    view
    |> element(~s(button[phx-click="filter:zone"][phx-value-zone="personal"]))
    |> render_click()

    refute has_element?(view, ~s(button[title="Add to today"][phx-value-id="done-once"]))

    view
    |> element(~s(button[phx-click="archive:show"]))
    |> render_click()

    view
    |> element(~s(button[phx-click="archive:state_filter"][phx-value-state="finished"]))
    |> render_click()

    assert render(view) =~ "Already done"
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
