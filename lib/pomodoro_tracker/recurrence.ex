defmodule PomodoroTracker.Recurrence do
  @moduledoc """
  Canonical recurrence model + scheduling logic for templates.

  Supported recurrence families:

    * `daily`
    * `weekly` with explicit weekday selection
    * `interval` for every X days / months / years

  Interval recurrences support two anchor modes:

    * `calendar`   - fixed calendar cadence from an anchor date
    * `completion` - next due date is based on the last completion date

  Rules can optionally "pop" earlier than their due date through `lead`.
  """

  @weekday_atoms %{
    "mon" => 1,
    "tue" => 2,
    "wed" => 3,
    "thu" => 4,
    "fri" => 5,
    "sat" => 6,
    "sun" => 7
  }

  @weekday_short %{
    1 => "L",
    2 => "Ma",
    3 => "Mi",
    4 => "J",
    5 => "V",
    6 => "S",
    7 => "D"
  }

  @weekday_defaults [1, 2, 3, 4, 5]

  @type unit :: :days | :months | :years
  @type lead :: %{value: pos_integer(), unit: unit()}

  @type t ::
          %{type: :daily}
          | %{type: :weekly, weekdays: [1..7]}
          | %{
              type: :interval,
              every: pos_integer(),
              unit: unit(),
              anchor_date: Date.t(),
              anchor_mode: :calendar | :completion,
              lead: lead() | nil
            }

  def weekday_defaults, do: @weekday_defaults

  def weekday_short(day), do: Map.get(@weekday_short, day, "?")

  @doc "Normalize raw recurrence data from YAML or legacy string rules."
  @spec normalize(nil | binary() | map()) :: t() | nil
  def normalize(nil), do: nil
  def normalize(""), do: nil

  def normalize(rule) when is_binary(rule) do
    case String.trim(rule) |> String.downcase() do
      "daily" ->
        %{type: :daily}

      "weekdays" ->
        %{type: :weekly, weekdays: @weekday_defaults}

      "weekly" ->
        %{type: :weekly, weekdays: @weekday_defaults}

      "weekly:" <> days ->
        weekdays =
          days
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.map(&Map.get(@weekday_atoms, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort()

        if weekdays == [], do: nil, else: %{type: :weekly, weekdays: weekdays}

      _ ->
        nil
    end
  end

  def normalize(%{} = rule) do
    type = fetch(rule, ["type", :type])

    case to_string(type || "") do
      "daily" ->
        %{type: :daily}

      "weekly" ->
        %{type: :weekly, weekdays: parse_weekdays(fetch(rule, ["weekdays", :weekdays]))}

      "interval" ->
        %{
          type: :interval,
          every: positive_int(fetch(rule, ["every", :every]), 1),
          unit: parse_unit(fetch(rule, ["unit", :unit]), :days),
          anchor_date: parse_date(fetch(rule, ["anchor_date", :anchor_date]), Date.utc_today()),
          anchor_mode: parse_anchor_mode(fetch(rule, ["anchor_mode", :anchor_mode]), :calendar),
          lead: parse_lead(fetch(rule, ["lead", :lead]))
        }

      _ ->
        nil
    end
  end

  @doc "Serialize canonical recurrence data into YAML-friendly maps."
  @spec serialize(t() | nil) :: map() | nil
  def serialize(nil), do: nil
  def serialize(%{type: :daily}), do: %{"type" => "daily"}

  def serialize(%{type: :weekly, weekdays: weekdays}) do
    %{"type" => "weekly", "weekdays" => Enum.sort(weekdays)}
  end

  def serialize(%{type: :interval} = recurrence) do
    base = %{
      "type" => "interval",
      "every" => recurrence.every,
      "unit" => Atom.to_string(recurrence.unit),
      "anchor_date" => Date.to_iso8601(recurrence.anchor_date),
      "anchor_mode" => Atom.to_string(recurrence.anchor_mode)
    }

    case recurrence.lead do
      %{value: value, unit: unit} ->
        Map.put(base, "lead", %{"value" => value, "unit" => Atom.to_string(unit)})

      _ ->
        base
    end
  end

  @doc "Whether a template should materialize on the given date."
  @spec should_run?(nil | binary() | map(), Date.t(), map()) :: boolean()
  def should_run?(rule, %Date{} = date, template \\ %{}) do
    case normalize(rule) do
      nil ->
        false

      %{type: :daily} ->
        true

      %{type: :weekly, weekdays: weekdays} ->
        Date.day_of_week(date) in weekdays

      %{type: :interval, anchor_mode: :calendar} = recurrence ->
        pops_on_calendar_date?(recurrence, date)

      %{type: :interval, anchor_mode: :completion} = recurrence ->
        pops_on_completion_date?(recurrence, date, template)
    end
  end

  @doc "Compact label for cards and small metadata rows."
  @spec compact_label(nil | binary() | map()) :: binary() | nil
  def compact_label(rule) do
    case normalize(rule) do
      nil ->
        nil

      %{type: :daily} ->
        "cada: diario"

      %{type: :weekly, weekdays: weekdays} ->
        "cada: " <> Enum.map_join(weekdays, "|", &weekday_short/1)

      %{type: :interval} = recurrence ->
        base = "cada: #{recurrence.every}#{unit_short(recurrence.unit)}"
        lead = recurrence.lead && " -#{lead_short(recurrence.lead)}"
        reset = if recurrence.anchor_mode == :completion, do: " ↺", else: ""
        base <> (lead || "") <> reset
    end
  end

  @doc "Longer human-readable label for tooltips and form summaries."
  @spec human_label(nil | binary() | map()) :: binary() | nil
  def human_label(rule) do
    case normalize(rule) do
      nil ->
        nil

      %{type: :daily} ->
        "Todos los dias"

      %{type: :weekly, weekdays: weekdays} ->
        "Semanal: " <> Enum.map_join(weekdays, ", ", &weekday_short/1)

      %{type: :interval} = recurrence ->
        cadence = "Cada #{recurrence.every} #{unit_label(recurrence.unit, recurrence.every)}"

        anchor =
          case recurrence.anchor_mode do
            :calendar ->
              "fijo desde #{Date.to_iso8601(recurrence.anchor_date)}"

            :completion ->
              "reinicia al completar desde #{Date.to_iso8601(recurrence.anchor_date)}"
          end

        lead =
          case recurrence.lead do
            nil -> nil
            %{value: value, unit: unit} -> "aparece #{value} #{unit_label(unit, value)} antes"
          end

        [cadence, anchor, lead]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" · ")
    end
  end

  @doc "Default recurrence editor state for LiveView forms."
  def default_form(today \\ Date.utc_today()) do
    %{
      recurrence_type: "none",
      recurrence_weekdays: @weekday_defaults,
      recurrence_every: "1",
      recurrence_unit: "months",
      recurrence_anchor_date: Date.to_iso8601(today),
      recurrence_anchor_mode: "calendar",
      recurrence_lead_value: "0",
      recurrence_lead_unit: "days"
    }
  end

  @doc "Populate recurrence form state from an existing recurrence rule."
  def form_fields(rule, today \\ Date.utc_today()) do
    base = default_form(today)

    case normalize(rule) do
      nil ->
        base

      %{type: :daily} ->
        %{base | recurrence_type: "daily"}

      %{type: :weekly, weekdays: weekdays} ->
        %{base | recurrence_type: "weekly", recurrence_weekdays: weekdays}

      %{type: :interval} = recurrence ->
        lead = recurrence.lead || %{value: 0, unit: :days}

        %{
          base
          | recurrence_type: "interval",
            recurrence_every: Integer.to_string(recurrence.every),
            recurrence_unit: Atom.to_string(recurrence.unit),
            recurrence_anchor_date: Date.to_iso8601(recurrence.anchor_date),
            recurrence_anchor_mode: Atom.to_string(recurrence.anchor_mode),
            recurrence_lead_value: Integer.to_string(lead.value),
            recurrence_lead_unit: Atom.to_string(lead.unit)
        }
    end
  end

  @doc "Apply `phx-change` params to recurrence form state."
  def apply_form_params(form, params) when is_map(form) and is_map(params) do
    recurrence_type =
      params
      |> Map.get("recurrence_type", form.recurrence_type || "none")
      |> parse_recurrence_type()

    %{
      form
      | recurrence_type: recurrence_type,
        recurrence_every:
          params
          |> Map.get("recurrence_every", form.recurrence_every || "1")
          |> positive_string("1"),
        recurrence_unit:
          params
          |> Map.get("recurrence_unit", form.recurrence_unit || "months")
          |> parse_unit_string("months"),
        recurrence_anchor_date:
          params
          |> Map.get(
            "recurrence_anchor_date",
            form.recurrence_anchor_date || Date.to_iso8601(Date.utc_today())
          )
          |> valid_date_string(form.recurrence_anchor_date || Date.to_iso8601(Date.utc_today())),
        recurrence_anchor_mode:
          params
          |> Map.get("recurrence_anchor_mode", form.recurrence_anchor_mode || "calendar")
          |> parse_anchor_mode_string("calendar"),
        recurrence_lead_value:
          params
          |> Map.get("recurrence_lead_value", form.recurrence_lead_value || "0")
          |> non_negative_string("0"),
        recurrence_lead_unit:
          params
          |> Map.get("recurrence_lead_unit", form.recurrence_lead_unit || "days")
          |> parse_unit_string("days")
    }
  end

  @doc "Toggle a weekday chip in recurrence editor state."
  def toggle_weekday(form, day) when is_map(form) do
    day = parse_weekday_value(day)
    weekdays = Enum.sort(List.wrap(form.recurrence_weekdays || @weekday_defaults))

    new_weekdays =
      cond do
        is_nil(day) ->
          weekdays

        day in weekdays and length(weekdays) == 1 ->
          weekdays

        day in weekdays ->
          List.delete(weekdays, day)

        true ->
          Enum.sort(weekdays ++ [day])
      end

    %{form | recurrence_weekdays: new_weekdays}
  end

  @doc "Build canonical recurrence data from LiveView form state."
  def from_form(form) when is_map(form) do
    case form.recurrence_type do
      "none" ->
        nil

      "daily" ->
        %{type: :daily}

      "weekly" ->
        %{type: :weekly, weekdays: parse_weekdays(form.recurrence_weekdays)}

      "interval" ->
        lead_value = positive_int(form.recurrence_lead_value, 0)

        %{
          type: :interval,
          every: positive_int(form.recurrence_every, 1),
          unit: parse_unit(form.recurrence_unit, :months),
          anchor_date: parse_date(form.recurrence_anchor_date, Date.utc_today()),
          anchor_mode: parse_anchor_mode(form.recurrence_anchor_mode, :calendar),
          lead:
            if(lead_value > 0,
              do: %{value: lead_value, unit: parse_unit(form.recurrence_lead_unit, :days)},
              else: nil
            )
        }

      _ ->
        nil
    end
  end

  defp pops_on_calendar_date?(recurrence, date) do
    do_calendar_pop?(recurrence.anchor_date, recurrence, date, 0)
  end

  defp do_calendar_pop?(_due_date, _recurrence, _date, steps) when steps > 2048, do: false

  defp do_calendar_pop?(due_date, recurrence, date, steps) do
    pop_date = apply_lead(due_date, recurrence.lead, -1)

    case Date.compare(pop_date, date) do
      :eq ->
        true

      :gt ->
        false

      :lt ->
        next_due = shift_date(due_date, recurrence.every, recurrence.unit)
        do_calendar_pop?(next_due, recurrence, date, steps + 1)
    end
  end

  defp pops_on_completion_date?(recurrence, date, template) do
    anchor = completion_anchor_date(template, recurrence.anchor_date)
    due_date = shift_date(anchor, recurrence.every, recurrence.unit)
    pop_date = apply_lead(due_date, recurrence.lead, -1)
    Date.compare(pop_date, date) == :eq
  end

  defp completion_anchor_date(template, fallback) do
    case Map.get(template, :last_completed_at) do
      nil -> fallback
      value -> parse_date(value, fallback)
    end
  end

  defp apply_lead(date, nil, _direction), do: date

  defp apply_lead(date, %{value: value, unit: unit}, direction) do
    shift_date(date, value * direction, unit)
  end

  defp shift_date(date, amount, :days), do: Date.add(date, amount)
  defp shift_date(date, amount, :months), do: add_months(date, amount)
  defp shift_date(date, amount, :years), do: add_years(date, amount)

  defp add_years(%Date{} = date, years), do: add_months(date, years * 12)

  defp add_months(%Date{} = date, months) do
    total = date.year * 12 + (date.month - 1) + months
    year = div(total, 12)
    month = rem(total, 12) + 1
    day = min(date.day, Date.days_in_month(Date.new!(year, month, 1)))
    Date.new!(year, month, day)
  end

  defp parse_weekdays(nil), do: @weekday_defaults

  defp parse_weekdays(days) when is_list(days) do
    days
    |> Enum.map(&parse_weekday_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> case do
      [] -> @weekday_defaults
      list -> list
    end
  end

  defp parse_weekdays(_other), do: @weekday_defaults

  defp parse_weekday_value(day) when is_integer(day) and day in 1..7, do: day

  defp parse_weekday_value(day) when is_binary(day),
    do: day |> String.trim() |> Integer.parse() |> elem_or_nil()

  defp parse_weekday_value(day) when is_atom(day), do: parse_weekday_value(Atom.to_string(day))
  defp parse_weekday_value(_), do: nil

  defp parse_unit(value, _fallback) when value in [:days, :months, :years], do: value
  defp parse_unit("days", _fallback), do: :days
  defp parse_unit("months", _fallback), do: :months
  defp parse_unit("years", _fallback), do: :years

  defp parse_unit(value, fallback) when is_atom(value),
    do: parse_unit(Atom.to_string(value), fallback)

  defp parse_unit(_value, fallback), do: fallback

  defp parse_anchor_mode(value, _fallback) when value in [:calendar, :completion], do: value
  defp parse_anchor_mode("calendar", _fallback), do: :calendar
  defp parse_anchor_mode("completion", _fallback), do: :completion

  defp parse_anchor_mode(value, fallback) when is_atom(value),
    do: parse_anchor_mode(Atom.to_string(value), fallback)

  defp parse_anchor_mode(_value, fallback), do: fallback

  defp parse_date(%Date{} = date, _fallback), do: date

  defp parse_date(value, fallback) when is_binary(value) do
    iso = String.slice(value, 0, 10)

    case Date.from_iso8601(iso) do
      {:ok, date} -> date
      _ -> fallback
    end
  end

  defp parse_date(_value, fallback), do: fallback

  defp parse_lead(nil), do: nil

  defp parse_lead(%{} = lead) do
    value = positive_int(fetch(lead, ["value", :value]), 0)

    if value > 0 do
      %{
        value: value,
        unit: parse_unit(fetch(lead, ["unit", :unit]), :days)
      }
    else
      nil
    end
  end

  defp parse_lead(_other), do: nil

  defp positive_int(value, fallback) when is_integer(value),
    do: if(value > 0, do: value, else: fallback)

  defp positive_int(value, fallback) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> fallback
    end
  end

  defp positive_int(_value, fallback), do: fallback

  defp positive_string(value, fallback) do
    value
    |> positive_int(String.to_integer(fallback))
    |> Integer.to_string()
  end

  defp non_negative_string(value, fallback) when is_integer(value),
    do: if(value >= 0, do: Integer.to_string(value), else: fallback)

  defp non_negative_string(value, fallback) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int >= 0 -> Integer.to_string(int)
      _ -> fallback
    end
  end

  defp non_negative_string(_value, fallback), do: fallback

  defp parse_recurrence_type("daily"), do: "daily"
  defp parse_recurrence_type("weekly"), do: "weekly"
  defp parse_recurrence_type("interval"), do: "interval"
  defp parse_recurrence_type(_), do: "none"

  defp parse_unit_string(value, fallback) do
    value
    |> parse_unit(String.to_atom(fallback))
    |> Atom.to_string()
  end

  defp parse_anchor_mode_string(value, fallback) do
    value
    |> parse_anchor_mode(String.to_atom(fallback))
    |> Atom.to_string()
  end

  defp valid_date_string(value, fallback) do
    value
    |> parse_date(Date.from_iso8601!(fallback))
    |> Date.to_iso8601()
  rescue
    _ -> fallback
  end

  defp unit_short(:days), do: "d"
  defp unit_short(:months), do: "m"
  defp unit_short(:years), do: "a"

  defp lead_short(%{value: value, unit: unit}), do: "#{value}#{unit_short(unit)}"

  defp unit_label(:days, 1), do: "dia"
  defp unit_label(:days, _), do: "dias"
  defp unit_label(:months, 1), do: "mes"
  defp unit_label(:months, _), do: "meses"
  defp unit_label(:years, 1), do: "ano"
  defp unit_label(:years, _), do: "anos"

  defp fetch(map, keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp elem_or_nil({int, ""}) when int in 1..7, do: int
  defp elem_or_nil(_), do: nil
end
