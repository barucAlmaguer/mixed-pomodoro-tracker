defmodule PomodoroTrackerWeb.StrengthLiveTest do
  use PomodoroTrackerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PomodoroTracker.{Clock, Strength, Timer, Vault}

  setup do
    Timer.reset()
    {work, personal} = make_tmp_vaults()
    prior = Application.get_env(:pomodoro_tracker, :vaults)

    Application.put_env(:pomodoro_tracker, :vaults,
      work: work,
      personal: personal,
      subdir: "pomodoro-tracker"
    )

    on_exit(fn ->
      Timer.reset()
      Application.put_env(:pomodoro_tracker, :vaults, prior)
      File.rm_rf!(Path.dirname(work))
    end)

    :ok
  end

  test "Scenario: Navegar entre las seis vistas del plan", %{conn: conn} do
    # Given I open the Fuerza de Papá plan
    {:ok, view, _html} = live(conn, "/fuerza")

    # When I touch a tab for Hoy, Escalera, Metas, Ejercicios, Rutinas or Movilidad
    view |> element("button[phx-click='strength:tab'][phx-value-tab='rutinas']") |> render_click()

    # Then the selected view is shown and plan state is preserved
    assert has_element?(view, "#strength-routines")
  end

  test "Scenario: Registrar fuerza como hábito personal", %{conn: conn} do
    # Given I select muscles trained today or yesterday
    {:ok, view, _html} = live(conn, "/fuerza")

    view
    |> element("button[phx-click='strength:log_muscle'][phx-value-muscle='core']")
    |> render_click()

    # When I save the session
    view |> element("button[phx-click='strength:save_session']") |> render_click()

    # Then the activity is stored in the personal vault with its exercise tags
    [session] = Strength.list_sessions()
    assert session.date == Date.to_iso8601(Clock.today())
    [task] = Enum.filter(Vault.list_tasks(:personal, :backlog), &(&1.id == session.id))
    assert "ejercicio>fuerza-papa" in task.tags
    assert "ejercicio>fuerza-papa>core" in task.tags
  end

  test "Scenario: Consultar metas y ejercicios funcionales", %{conn: conn} do
    # Given I am in Metas or Ejercicios
    {:ok, view, _html} = live(conn, "/fuerza")
    view |> element("button[phx-value-tab='metas']") |> render_click()

    # When I open a card
    view |> element("button[phx-click='strength:toggle'][phx-value-id='jug']") |> render_click()

    # Then I see muscles, technique, video, and the functional relationship
    assert render(view) =~ "Músculos que lo hacen posible"
    assert render(view) =~ "Ejercicios que lo construyen"
  end

  test "Scenario: Proyectar la carga de la semana", %{conn: conn} do
    # Given I choose a weekly alternation and training days
    {:ok, view, _html} = live(conn, "/fuerza")
    view |> element("button[phx-value-tab='rutinas']") |> render_click()

    # When I enable or disable a day
    for index <- 0..2,
        do:
          view
          |> element("button[phx-click='strength:day'][phx-value-index='#{index}']")
          |> render_click()

    # Then load, heatmap, and series ranking recalculate
    assert render(view) =~ "Semana vacía"
  end

  test "Scenario: Elegir ejercicios según dolor o prioridad", %{conn: conn} do
    # Given I mark muscles to avoid or prioritize
    {:ok, view, _html} = live(conn, "/fuerza")

    view
    |> element("button[phx-click='strength:cycle_mark'][phx-value-muscle='core']")
    |> render_click()

    # When I consult exercises for today
    html = render(view)

    # Then blocked exercises are excluded and matching ones are prioritized
    assert html =~ "Mejor no hoy"
    refute html =~ "Dead bug</button>"
  end

  test "el mapa corporal superpone músculos planos al maniquí 3D", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/fuerza")

    view |> element("button[phx-click='strength:show_body']") |> render_click()

    assert has_element?(view, "#strength-filter[phx-hook='StrengthBody']")
    assert has_element?(view, "#strength-filter [data-role='canvas']")
    assert has_element?(view, "#strength-filter[data-visual-model='mannequin-overlay']")
    refute has_element?(view, "#strength-filter [data-role='muscle-planes']")
  end

  test "Scenario: Revisar historial muscular reciente", %{conn: conn} do
    # Given sessions exist in the last seven days
    {:ok, _} = Strength.save_session(Clock.today(), ["core", "glutes"])

    # When I open Hoy
    {:ok, view, _html} = live(conn, "/fuerza")

    # Then I see the recency map and registered sessions
    assert render(view) =~ "Músculos usados · últimos 7 días"
    assert render(view) =~ "Core anti-flexión"
  end

  test "Scenario: Filtrar y consultar drills de movilidad", %{conn: conn} do
    # Given I am in Movilidad
    {:ok, view, _html} = live(conn, "/fuerza")
    view |> element("button[phx-value-tab='movilidad']") |> render_click()

    # When I select a joint
    view
    |> element("button[phx-click='strength:joint'][phx-value-joint='wrist']")
    |> render_click()

    # Then I only see pertinent drills by phase and their technique
    assert render(view) =~ "Flujo de muñecas"
    refute render(view) =~ "Flexor de cadera"
  end

  test "Scenario: Guardar chequeos funcionales", %{conn: conn} do
    # Given I rate one or more functional tests
    {:ok, view, _html} = live(conn, "/fuerza")
    view |> element("button[phx-value-tab='movilidad']") |> render_click()

    view
    |> element("button[phx-click='strength:test'][phx-value-id='sitrise'][phx-value-level='2']")
    |> render_click()

    # When I save today's check
    view |> element("button[phx-click='strength:save_tests']") |> render_click()

    # Then the snapshot persists and shows progress from the previous one
    assert [%{"results" => %{"sitrise" => 2}}] = Strength.profile()["tests"]
    assert render(view) =~ "Historial"
  end

  test "Scenario: Mantener una escalera de progresiones", %{conn: conn} do
    # Given I open a movement pattern
    {:ok, view, _html} = live(conn, "/fuerza")
    view |> element("button[phx-value-tab='escalera']") |> render_click()

    view
    |> element("button[phx-click='strength:pattern'][phx-value-id='squat']")
    |> render_click()

    # When I mark my current stage
    view
    |> element(
      "button[phx-click='strength:stage'][phx-value-pattern='squat'][phx-value-stage='0']"
    )
    |> render_click()

    # Then the stage persists and shows criteria, next step, and mobility gates
    assert Strength.profile()["levels"]["squat"] == 0
    assert render(view) =~ "ESTÁS AQUÍ"
  end

  test "Scenario: Inspeccionar anatomía y posturas del maniquí sin arrastrarlo", %{conn: conn} do
    # Given I open the Fuerza de Papá plan
    {:ok, view, _html} = live(conn, "/fuerza")

    # When I show the mannequin and choose a camera shortcut or the Posturas muñeco tab
    view |> element("button[phx-click='strength:show_body']") |> render_click()

    assert has_element?(view, "#strength-filter [data-camera-view='front']")
    assert has_element?(view, "#strength-filter [data-camera-view='back']")
    assert has_element?(view, "#strength-filter [data-camera-view='side']")

    view
    |> element("button[phx-click='strength:tab'][phx-value-tab='posturas']")
    |> render_click()

    # Then I can access front, back, side, and posture diagnostic views
    assert has_element?(view, "#strength-postures")
  end

  defp make_tmp_vaults do
    base = Path.join(System.tmp_dir!(), "pomo-strength-#{System.unique_integer([:positive])}")
    work = Path.join(base, "work")
    personal = Path.join(base, "personal")

    for root <- [work, personal],
        kind <- ["templates", "backlog", "days", "sessions", "settings"],
        do: File.mkdir_p!(Path.join([root, "pomodoro-tracker", kind]))

    {work, personal}
  end
end
