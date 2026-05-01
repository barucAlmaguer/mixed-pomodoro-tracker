defmodule PomodoroTrackerWeb.DayLiveFollowUpsTest do
  use PomodoroTrackerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PomodoroTracker.{Clock, Timer, Vault}

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

  test "finishing a template instance creates its follow-up instance", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "patinar",
        title: "Patinar",
        on_done: ["banarse"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "banarse",
        title: "Bañarse"
      })

    [patinar] = Enum.filter(Vault.list_tasks(:personal, :templates), &(&1.id == "patinar"))
    {:ok, patinar_id} = Vault.instantiate_template(patinar)
    {:ok, day} = Vault.load_day()
    {:ok, _} = Vault.save_day(%{day | order: [patinar_id]})

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s(button[phx-click="day:toggle_active"][phx-value-id="#{patinar_id}"]), "Start")
    |> render_click()

    view
    |> element(~s(button[phx-click="day:finish"][phx-value-id="#{patinar_id}"]), "Finish")
    |> render_click()

    {:ok, reloaded} = Vault.load_day()
    assert "banarse-#{today_suffix()}" in reloaded.order
  end

  test "today list shows then label for tasks with follow-ups", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "patinar",
        title: "Patinar",
        priority: "med",
        on_done: ["banarse", "orear-protecciones"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "banarse",
        title: "Bañarse"
      })

    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "orear-protecciones",
        title: "Orear protecciones"
      })

    [patinar] = Enum.filter(Vault.list_tasks(:personal, :templates), &(&1.id == "patinar"))
    {:ok, patinar_id} = Vault.instantiate_template(patinar)
    {:ok, day} = Vault.load_day()
    {:ok, _} = Vault.save_day(%{day | order: [patinar_id]})

    {:ok, view, _html} = live(conn, "/")

    html = render(view)
    assert html =~ "then: banarse,orear-protecciones"
    refute html =~ "· med"
  end

  test "finishing a template instance reuses an already pending follow-up", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "patinar",
        title: "Patinar",
        on_done: ["banarse"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "banarse",
        title: "Bañarse"
      })

    [patinar] = Enum.filter(Vault.list_tasks(:personal, :templates), &(&1.id == "patinar"))
    [banarse] = Enum.filter(Vault.list_tasks(:personal, :templates), &(&1.id == "banarse"))
    {:ok, patinar_id} = Vault.instantiate_template(patinar)
    {:ok, banarse_id} = Vault.instantiate_template(banarse)
    {:ok, day} = Vault.load_day()
    {:ok, _} = Vault.save_day(%{day | order: [patinar_id, banarse_id]})

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s(button[phx-click="day:toggle_active"][phx-value-id="#{patinar_id}"]), "Start")
    |> render_click()

    view
    |> element(~s(button[phx-click="day:finish"][phx-value-id="#{patinar_id}"]), "Finish")
    |> render_click()

    {:ok, reloaded} = Vault.load_day()
    assert Enum.count(reloaded.order, &String.starts_with?(&1, "banarse-")) == 1
    assert banarse_id in reloaded.order
  end

  test "finishing a template instance recreates a done follow-up with a suffixed id", %{
    conn: conn
  } do
    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "patinar",
        title: "Patinar",
        on_done: ["banarse"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :templates, %{
        id: "banarse",
        title: "Bañarse"
      })

    [patinar] = Enum.filter(Vault.list_tasks(:personal, :templates), &(&1.id == "patinar"))
    [banarse] = Enum.filter(Vault.list_tasks(:personal, :templates), &(&1.id == "banarse"))
    {:ok, patinar_id} = Vault.instantiate_template(patinar)
    {:ok, banarse_id} = Vault.instantiate_template(banarse)
    {:ok, day} = Vault.load_day()
    {:ok, _} = Vault.save_day(%{day | order: [patinar_id], done: [banarse_id]})

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s(button[phx-click="day:toggle_active"][phx-value-id="#{patinar_id}"]), "Start")
    |> render_click()

    view
    |> element(~s(button[phx-click="day:finish"][phx-value-id="#{patinar_id}"]), "Finish")
    |> render_click()

    {:ok, reloaded} = Vault.load_day()
    assert "banarse-#{today_suffix()}-2" in reloaded.order
  end

  defp today_suffix do
    Clock.today() |> Date.to_iso8601() |> String.replace("-", "")
  end

  defp make_tmp_vaults do
    base = Path.join(System.tmp_dir!(), "pomo-followups-#{System.unique_integer([:positive])}")
    work = Path.join(base, "work")
    personal = Path.join(base, "personal")

    for root <- [work, personal],
        kind <- ["templates", "backlog", "days", "sessions", "settings"] do
      File.mkdir_p!(Path.join([root, "pomodoro-tracker", kind]))
    end

    {work, personal}
  end
end
