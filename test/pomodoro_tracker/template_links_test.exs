defmodule PomodoroTracker.TemplateLinksTest do
  use ExUnit.Case, async: true

  alias PomodoroTracker.TemplateLinks

  test "rewrite updates outgoing and reverse incoming links from both sides" do
    tasks = %{
      "patinar" => %{id: "patinar", kind: :templates, on_done: []},
      "banarse" => %{id: "banarse", kind: :templates, on_done: []},
      "orear" => %{id: "orear", kind: :templates, on_done: []}
    }

    assert {:ok, updates} =
             TemplateLinks.rewrite(tasks, "banarse", ["orear"], ["patinar"])

    assert updates == %{
             "banarse" => ["orear"],
             "patinar" => ["banarse"]
           }
  end

  test "rewrite rejects cycles" do
    tasks = %{
      "lavar" => %{id: "lavar", kind: :templates, on_done: ["secar"]},
      "secar" => %{id: "secar", kind: :templates, on_done: []}
    }

    assert {:error, :cycle} =
             TemplateLinks.rewrite(tasks, "lavar", ["secar"], ["secar"])
  end
end
