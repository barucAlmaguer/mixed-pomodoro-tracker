defmodule PomodoroTracker.Tags do
  @moduledoc """
  Shared helpers for hierarchical tags like `ejercicio>cuello`.

  Tags are stored as normalized strings. Parent filters match descendants, so a
  filter of `ejercicio` matches tasks tagged with `ejercicio>cuello`.
  """

  @type tag :: String.t()

  @spec normalize(tag | nil) :: tag | nil
  def normalize(nil), do: nil

  def normalize(tag) when is_binary(tag) do
    tag
    |> String.trim()
    |> String.replace(~r/\s*>\s*/, ">")
    |> String.replace(~r/\s+/, " ")
    |> String.trim(">")
    |> blank_to_nil()
  end

  @spec normalize_many([tag | nil]) :: [tag]
  def normalize_many(tags) when is_list(tags) do
    tags
    |> Enum.map(&normalize/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort_by(&sort_key/1)
  end

  @spec parse_input(String.t() | nil) :: [tag]
  def parse_input(nil), do: []
  def parse_input(""), do: []

  def parse_input(input) when is_binary(input) do
    input
    |> String.split(~r/[\n,]/, trim: true)
    |> normalize_many()
  end

  @spec with_break([tag], boolean()) :: [tag]
  def with_break(tags, is_break?) do
    tags = normalize_many(tags)

    cond do
      is_break? -> normalize_many(tags ++ ["break"])
      true -> Enum.reject(tags, &(&1 == "break"))
    end
  end

  @spec ancestors(tag) :: [tag]
  def ancestors(tag) when is_binary(tag) do
    parts = String.split(tag, ">", trim: true)

    case length(parts) do
      len when len <= 1 ->
        []

      len ->
        1..(len - 1)
        |> Enum.map(fn depth -> Enum.take(parts, depth) |> Enum.join(">") end)
    end
  end

  @spec family(tag) :: [tag]
  def family(tag) when is_binary(tag) do
    normalize_many([tag | ancestors(tag)])
  end

  @spec expand_catalog([tag]) :: [tag]
  def expand_catalog(tags) when is_list(tags) do
    tags
    |> Enum.flat_map(&family/1)
    |> normalize_many()
  end

  @spec matches?(tag | nil, [tag] | nil) :: boolean()
  def matches?(nil, _task_tags), do: true
  def matches?(_filter_tag, nil), do: false

  def matches?(filter_tag, task_tags) when is_binary(filter_tag) and is_list(task_tags) do
    filter_tag = normalize(filter_tag)

    Enum.any?(task_tags, fn task_tag ->
      task_tag = normalize(task_tag)
      task_tag == filter_tag or String.starts_with?(task_tag, filter_tag <> ">")
    end)
  end

  @spec matches_all?(Enumerable.t(), [tag] | nil) :: boolean()
  def matches_all?(filter_tags, task_tags) do
    filter_tags
    |> Enum.to_list()
    |> normalize_many()
    |> Enum.all?(&matches?(&1, task_tags || []))
  end

  @spec registry_seed([tag], [tag]) :: [tag]
  def registry_seed(explicit_tags, discovered_tags) do
    normalize_many(explicit_tags ++ discovered_tags)
  end

  defp sort_key(tag) do
    segments = String.split(tag, ">", trim: true)
    {length(segments), Enum.map(segments, &String.downcase/1), String.downcase(tag)}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
