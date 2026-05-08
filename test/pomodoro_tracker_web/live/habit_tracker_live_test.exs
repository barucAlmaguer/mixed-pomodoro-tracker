defmodule PomodoroTrackerWeb.HabitTrackerLiveTest do
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

  test "habits view aggregates parent tag activity and renders child cards", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "neck-work",
        title: "Neck work",
        tags: ["ejercicio>cuello"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "cardio",
        title: "Cardio",
        tags: ["ejercicio>cardio"]
      })

    {:ok, _} =
      Vault.save_day(%{
        date: ~D[2026-04-10],
        order: [],
        active: [],
        done: ["neck-work"],
        pomodoros: %{}
      })

    {:ok, _} =
      Vault.save_day(%{
        date: ~D[2026-04-11],
        order: [],
        active: [],
        done: ["cardio"],
        pomodoros: %{}
      })

    {:ok, view, _html} = live(conn, "/habits?zone=personal&tag=ejercicio&month=2026-04&year=2026")

    assert has_element?(view, "#habits-nav")
    assert has_element?(view, "#habits-nav-habits")
    assert render(view) =~ "Heatmap mensual"
    assert render(view) =~ "cuello"
    assert render(view) =~ "cardio"
    assert render(view) =~ "días activos en 2026: 2"
    assert render(view) =~ "ver tareas"
  end

  test "habits view can add an empty child tag under the selected parent", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "neck-work",
        title: "Neck work",
        tags: ["ejercicio>cuello"]
      })

    {:ok, view, _html} = live(conn, "/habits?zone=personal&tag=ejercicio")

    view
    |> form("form[phx-submit='habit:add_child']", %{"child_tag_query" => "coordinacion"})
    |> render_change()

    view
    |> form("form[phx-submit='habit:add_child']", %{"child_tag_query" => "coordinacion"})
    |> render_submit()

    assert "ejercicio>coordinacion" in Vault.list_registered_tags(:personal)
    assert render(view) =~ "coordinacion"
  end

  test "habits view can rename a child tag across registry and tasks", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "coord-drill",
        title: "Coord drill",
        tags: ["ejercicio>coordinacion"]
      })

    {:ok, view, _html} = live(conn, "/habits?zone=personal&tag=ejercicio")

    view
    |> element(~s([phx-click="habit:rename_open"][phx-value-tag="ejercicio>coordinacion"]))
    |> render_click()

    view
    |> form("form[phx-submit='habit:rename_submit'][phx-value-tag='ejercicio>coordinacion']", %{
      "rename_value" => "movilidad"
    })
    |> render_change()

    view
    |> form("form[phx-submit='habit:rename_submit'][phx-value-tag='ejercicio>coordinacion']", %{
      "rename_value" => "movilidad"
    })
    |> render_submit()

    [task] = Enum.filter(Vault.list_tasks(:personal, :backlog), &(&1.id == "coord-drill"))

    assert task.tags == ["ejercicio>movilidad"]
    assert "ejercicio>movilidad" in Vault.list_registered_tags(:personal)
    refute "ejercicio>coordinacion" in Vault.list_registered_tags(:personal)
    assert render(view) =~ "movilidad"
  end

  test "habits view can create a recurrent task directly under a branch tag", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "neck-work",
        title: "Neck work",
        tags: ["ejercicio>cuello"]
      })

    {:ok, view, _html} = live(conn, "/habits?zone=personal&tag=ejercicio")

    view
    |> element(~s([phx-click="habit:new_task_open"][phx-value-tag="ejercicio>cuello"]))
    |> render_click()

    view
    |> form("form[phx-submit='habit:new_task_submit']", %{
      "task" => %{
        "title" => "Bano perras",
        "priority" => "med",
        "recurrence_type" => "daily",
        "body" => ""
      }
    })
    |> render_change()

    view
    |> form("form[phx-submit='habit:new_task_submit']", %{
      "task" => %{
        "title" => "Bano perras",
        "priority" => "med",
        "recurrence_type" => "daily",
        "body" => ""
      }
    })
    |> render_submit()

    [task] = Enum.filter(Vault.list_tasks(:personal, :templates), &(&1.id == "bano-perras"))
    assert task.tags == ["ejercicio>cuello"]
    assert task.recurrence.type == :daily
  end

  test "habits view can delete a mistagged child tag and strip it from tasks", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "groom-dogs",
        title: "Groom dogs",
        tags: ["perras>acicalar"]
      })

    {:ok, view, _html} = live(conn, "/habits?zone=personal&tag=perras")

    view
    |> element(~s([phx-click="habit:delete_tag_open"][phx-value-tag="perras>acicalar"]))
    |> render_click()

    assert render(view) =~ "1 tareas perderían este tag"

    view
    |> element(~s([phx-click="habit:delete_tag_confirm"][phx-value-tag="perras>acicalar"]))
    |> render_click()

    [task] = Enum.filter(Vault.list_tasks(:personal, :backlog), &(&1.id == "groom-dogs"))

    assert task.tags == []
    refute "perras>acicalar" in Vault.list_registered_tags(:personal)
  end

  defp make_tmp_vaults do
    base = Path.join(System.tmp_dir!(), "pomo-habits-#{System.unique_integer([:positive])}")
    work = Path.join(base, "work")
    personal = Path.join(base, "personal")

    for root <- [work, personal],
        kind <- ["templates", "backlog", "days", "sessions", "settings"] do
      File.mkdir_p!(Path.join([root, "pomodoro-tracker", kind]))
    end

    {work, personal}
  end
end
