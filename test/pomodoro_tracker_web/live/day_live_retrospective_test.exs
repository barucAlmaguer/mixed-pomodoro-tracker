defmodule PomodoroTrackerWeb.DayLiveRetrospectiveTest do
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

  test "can log a retrospective session for a historical day", %{conn: conn} do
    yesterday = Date.add(Clock.today(), -1)

    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "llamar-taller",
        title: "Llamar taller",
        priority: "med",
        tags: ["carro"]
      })

    {:ok, view, _html} = live(conn, "/?date=#{Date.to_iso8601(yesterday)}")

    render_hook(view, "timeline:range_selected", %{"start_minute" => 420, "end_minute" => 540})

    view
    |> form("form[phx-submit='retrospective:submit']", %{
      "retro" => %{"phase" => "work", "zone_mode" => "personal", "task_query" => "", "ad_hoc_title" => "", "ad_hoc_zone" => "personal"}
    })
    |> render_change()

    view
    |> element(~s(button[phx-click="retrospective:toggle_task"][phx-value-id="llamar-taller"]))
    |> render_click()

    view
    |> form("form[phx-submit='retrospective:submit']")
    |> render_submit()

    [session] = Vault.list_sessions(yesterday)
    assert session.phase == :work
    assert session.tasks == ["llamar-taller"]
    assert session.zones == [:personal]
    assert session.started_at == NaiveDateTime.new!(yesterday, ~T[07:00:00])
    assert session.ended_at == NaiveDateTime.new!(yesterday, ~T[09:00:00])
  end

  test "can create an ad-hoc task from the retrospective modal and auto-select it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_hook(view, "timeline:range_selected", %{"start_minute" => 600, "end_minute" => 660})

    view
    |> form("form[phx-submit='retrospective:submit']", %{
      "retro" => %{
        "phase" => "work",
        "zone_mode" => "personal",
        "task_query" => "",
        "ad_hoc_title" => "Recoger paquete",
        "ad_hoc_zone" => "personal"
      }
    })
    |> render_change()

    view
    |> element(~s(button[phx-click="retrospective:create_ad_hoc"]))
    |> render_click()

    [task] = Enum.filter(Vault.list_tasks(:personal, :backlog), &(&1.id == "recoger-paquete"))
    assert task.title == "Recoger paquete"
    assert render(view) =~ "Recoger paquete"
  end

  defp make_tmp_vaults do
    base = Path.join(System.tmp_dir!(), "pomo-retro-#{System.unique_integer([:positive])}")
    work = Path.join(base, "work")
    personal = Path.join(base, "personal")

    for root <- [work, personal],
        kind <- ["templates", "backlog", "days", "sessions", "settings"] do
      File.mkdir_p!(Path.join([root, "pomodoro-tracker", kind]))
    end

    {work, personal}
  end
end
