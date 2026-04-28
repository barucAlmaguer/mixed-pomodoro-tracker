defmodule PomodoroTracker.TagsTest do
  use ExUnit.Case, async: true

  alias PomodoroTracker.Tags

  test "normalizes and expands nested tags" do
    assert Tags.normalize(" ejercicio > cuello ") == "ejercicio>cuello"
    assert Tags.ancestors("ejercicio>cuello") == ["ejercicio"]

    assert Tags.expand_catalog(["ejercicio>cuello", "perritos>vet"]) == [
             "ejercicio",
             "perritos",
             "ejercicio>cuello",
             "perritos>vet"
           ]
  end

  test "parent filters match descendants" do
    assert Tags.matches?("ejercicio", ["ejercicio>cuello"])
    assert Tags.matches_all?(MapSet.new(["ejercicio"]), ["ejercicio>cuello"])
    refute Tags.matches?("cuello", ["ejercicio>cuello"])
    refute Tags.matches_all?(MapSet.new(["perritos"]), ["ejercicio>cuello"])
  end

  test "break helper keeps break separate from visible tags" do
    assert Tags.with_break(["ejercicio>cuello"], true) == ["break", "ejercicio>cuello"]
    assert Tags.with_break(["break", "ejercicio>cuello"], false) == ["ejercicio>cuello"]
  end
end
