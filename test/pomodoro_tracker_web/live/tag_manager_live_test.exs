defmodule PomodoroTrackerWeb.TagManagerLiveTest do
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

  test "tags view renders counts for direct and descendant usage", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "buy-soap",
        title: "Buy soap",
        tags: ["hogar"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "wash-clothes",
        title: "Wash clothes",
        tags: ["hogar>lavanderia"]
      })

    {:ok, view, _html} = live(conn, "/tags?zone=personal")

    assert has_element?(view, "#tags-nav")
    assert render(view) =~ "hogar"
    assert render(view) =~ "lavanderia"
    assert render(view) =~ "2"
  end

  test "tags view can create and rename a tag", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/tags?zone=personal")

    view
    |> form("form[phx-submit='tags:create']", %{"new_tag_query" => "casa"})
    |> render_change()

    view
    |> form("form[phx-submit='tags:create']", %{"new_tag_query" => "casa"})
    |> render_submit()

    assert "casa" in Vault.list_registered_tags(:personal)

    view
    |> element(~s([phx-click="tags:rename_open"][phx-value-tag="casa"]))
    |> render_click()

    view
    |> form("form[phx-submit='tags:rename_submit'][phx-value-tag='casa']", %{"rename_value" => "hogar"})
    |> render_change()

    view
    |> form("form[phx-submit='tags:rename_submit'][phx-value-tag='casa']", %{"rename_value" => "hogar"})
    |> render_submit()

    assert "hogar" in Vault.list_registered_tags(:personal)
    refute "casa" in Vault.list_registered_tags(:personal)
  end

  test "tags view can merge tags into a new target and handle existing target paths", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "fix-house",
        title: "Fix house",
        tags: ["casa"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "clean-home",
        title: "Clean home",
        tags: ["hogar"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "wash-home",
        title: "Wash home",
        tags: ["home>laundry"]
      })

    _ = Vault.register_tags(:personal, ["casa", "hogar", "home>laundry", "lavanderia"])

    {:ok, view, _html} = live(conn, "/tags?zone=personal")

    view
    |> element(~s([phx-click="tags:toggle_select"][phx-value-tag="casa"]))
    |> render_click()

    view
    |> element(~s([phx-click="tags:toggle_select"][phx-value-tag="hogar"]))
    |> render_click()

    view
    |> element(~s([phx-click="tags:merge_open"]))
    |> render_click()

    view
    |> form("form[phx-submit='tags:merge_confirm']", %{"target_tag" => "home"})
    |> render_change()

    view
    |> form("form[phx-submit='tags:merge_confirm']", %{"target_tag" => "home"})
    |> render_submit()

    tasks = Vault.list_tasks(:personal, :backlog)
    assert Enum.any?(tasks, &(&1.id == "fix-house" and &1.tags == ["home"]))
    assert Enum.any?(tasks, &(&1.id == "clean-home" and &1.tags == ["home"]))

    {:ok, view, _html} = live(conn, "/tags?zone=personal")

    view
    |> element(~s([phx-click="tags:toggle_select"][phx-value-tag="lavanderia"]))
    |> render_click()

    view
    |> element(~s([phx-click="tags:toggle_select"][phx-value-tag="home"]))
    |> render_click()

    view
    |> element(~s([phx-click="tags:merge_open"]))
    |> render_click()

    view
    |> form("form[phx-submit='tags:merge_confirm']", %{"target_tag" => "home>laundry"})
    |> render_change()

    assert render(view) =~ "ya existe con"

    view
    |> form("form[phx-submit='tags:merge_confirm']", %{"target_tag" => "home>laundry"})
    |> render_submit()

    refute "lavanderia" in Vault.list_registered_tags(:personal)
    assert "home>laundry" in Vault.list_registered_tags(:personal)
  end

  test "merge confirm survives if the dialog disappeared before submit", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "clean-house",
        title: "Clean house",
        tags: ["casa"]
      })

    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "fix-home",
        title: "Fix home",
        tags: ["hogar"]
      })

    _ = Vault.register_tags(:personal, ["casa", "hogar"])

    {:ok, view, _html} = live(conn, "/tags?zone=personal")

    view
    |> element(~s([phx-click="tags:toggle_select"][phx-value-tag="casa"]))
    |> render_click()

    view
    |> element(~s([phx-click="tags:toggle_select"][phx-value-tag="hogar"]))
    |> render_click()

    view
    |> element(~s([phx-click="tags:merge_open"]))
    |> render_click()

    view
    |> element(~s(div.fixed[phx-click="tags:merge_cancel"]))
    |> render_click()

    assert render_submit(view, "tags:merge_confirm", %{"target_tag" => "casa"}) =~
             "Merged into casa"

    tasks = Vault.list_tasks(:personal, :backlog)
    assert Enum.any?(tasks, &(&1.id == "clean-house" and &1.tags == ["casa"]))
    assert Enum.any?(tasks, &(&1.id == "fix-home" and &1.tags == ["casa"]))
  end

  test "tags view can delete a tag subtree and strip it from tasks", %{conn: conn} do
    {:ok, _} =
      Vault.create_task(:personal, :backlog, %{
        id: "dog-groom",
        title: "Dog groom",
        tags: ["perras>acicalar"]
      })

    {:ok, view, _html} = live(conn, "/tags?zone=personal")

    view
    |> element(~s([phx-click="tags:delete_open"][phx-value-tag="perras"]))
    |> render_click()

    assert render(view) =~ "1 tareas perderían este tag"

    view
    |> element(~s([phx-click="tags:delete_confirm"][phx-value-tag="perras"]))
    |> render_click()

    [task] = Enum.filter(Vault.list_tasks(:personal, :backlog), &(&1.id == "dog-groom"))
    assert task.tags == []
  end

  defp make_tmp_vaults do
    base = Path.join(System.tmp_dir!(), "pomo-tags-#{System.unique_integer([:positive])}")
    work = Path.join(base, "work")
    personal = Path.join(base, "personal")

    for root <- [work, personal],
        kind <- ["templates", "backlog", "days", "sessions", "settings"] do
      File.mkdir_p!(Path.join([root, "pomodoro-tracker", kind]))
    end

    {work, personal}
  end
end
