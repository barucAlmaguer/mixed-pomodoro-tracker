defmodule PomodoroTrackerWeb.DayLiveBreakPickerTest do
  use ExUnit.Case, async: true

  alias PomodoroTrackerWeb.DayLive

  test "passive break prefers today's instance over its recurrent base" do
    tasks = %{
      "leer" => task("leer", :templates, ["break"]),
      "leer-20260430" => task("leer-20260430", :backlog, ["break"], from_template: "leer")
    }

    picker = DayLive.break_picker_tasks(tasks, :passive_break, [], ["leer-20260430"], nil)

    assert Enum.map(picker, & &1.id) == ["leer-20260430"]
  end

  test "passive break prefers recurrent base over stale instances from older days" do
    tasks = %{
      "leer" => task("leer", :templates, ["break"]),
      "leer-20260424" => task("leer-20260424", :backlog, ["break"], from_template: "leer")
    }

    picker = DayLive.break_picker_tasks(tasks, :passive_break, [], [], nil)

    assert Enum.map(picker, & &1.id) == ["leer"]
  end

  test "active break keeps one-offs and recurrent families deduped independently" do
    tasks = %{
      "lavar-trastes" => task("lavar-trastes", :backlog, ["hogar"]),
      "estirar" => task("estirar", :templates, ["ejercicio>cuello"]),
      "estirar-20260430" =>
        task("estirar-20260430", :backlog, ["ejercicio>cuello"], from_template: "estirar")
    }

    picker =
      DayLive.break_picker_tasks(
        tasks,
        :active_break,
        [],
        ["estirar-20260430"],
        nil
      )

    assert Enum.map(picker, & &1.id) == ["estirar-20260430", "lavar-trastes"]
  end

  defp task(id, kind, tags, attrs \\ []) do
    defaults = %{
      id: id,
      kind: kind,
      title: id,
      priority: "med",
      tags: tags,
      zone: :personal,
      from_template: nil
    }

    Enum.into(attrs, defaults)
  end
end
