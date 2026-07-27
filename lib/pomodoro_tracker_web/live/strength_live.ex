defmodule PomodoroTrackerWeb.StrengthLive do
  @moduledoc "Interactive, vault-backed Fuerza de Papá plan."

  use PomodoroTrackerWeb, :live_view

  alias PomodoroTracker.{Clock, Strength, Vault}

  @tabs [
    {"hoy", "Hoy"},
    {"escalera", "Escalera"},
    {"metas", "Metas"},
    {"ejercicios", "Ejercicios"},
    {"rutinas", "Rutinas"},
    {"movilidad", "Movilidad"},
    {"posturas", "Posturas muñeco"}
  ]
  @postures [
    {"neutral", "Neutral", "Referencia erguida para comparar cada ajuste."},
    {"carry", "Carga", "Carga bilateral y caminar con peso."},
    {"squat", "Sentadilla", "Cadera atrás, rodillas flexionadas."},
    {"hinge", "Bisagra", "Patrón de peso muerto y puente."},
    {"press", "Press", "Brazos por encima de la cabeza."},
    {"pushup", "Suelo", "Base para lagartijas, plancha y trabajo horizontal."},
    {"mobility", "Movilidad", "Postura asimétrica para drills articulares."}
  ]
  @phases [
    {"warm", "Antes de entrenar · 5 min · dinámico"},
    {"cool", "Después · 3–4 min · estático"},
    {"snack", "Snacks de escritorio · 2 min"}
  ]

  defp tabs, do: @tabs
  defp phases, do: @phases
  defp postures, do: @postures

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Vault.Watcher.topic())

    {:ok,
     socket
     |> assign(:page_title, "Fuerza de Papá")
     |> assign(:tab, "hoy")
     |> assign(:open_id, nil)
     |> assign(:week, 1)
     |> assign(:days, [true, true, true])
     |> assign(:marks, %{})
     |> assign(:show_body, false)
     |> assign(:debug_pose, "neutral")
     |> assign(:show_blocked, false)
     |> assign(:log_day, 0)
     |> assign(:log_muscles, MapSet.new())
     |> assign(:log_exercises, MapSet.new())
     |> assign(:log_effort, %{})
     |> assign(:joint_filter, nil)
     |> assign(:test_selection, %{})
     |> assign(:open_pattern, nil)
     |> refresh()}
  end

  @impl true
  def handle_info(:vault_changed, socket), do: {:noreply, refresh(socket)}

  @impl true
  def handle_event("strength:tab", %{"tab" => tab}, socket)
      when tab in ~w(hoy escalera metas ejercicios rutinas movilidad posturas) do
    {:noreply, socket |> assign(:tab, tab) |> assign(:open_id, nil)}
  end

  def handle_event("strength:toggle", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :open_id, toggle(socket.assigns.open_id, id))}

  def handle_event("strength:week", %{"week" => week}, socket),
    do: {:noreply, assign(socket, :week, String.to_integer(week))}

  def handle_event("strength:day", %{"index" => raw}, socket) do
    index = String.to_integer(raw)
    days = List.update_at(socket.assigns.days, index, &(not &1))
    {:noreply, assign(socket, :days, days)}
  end

  def handle_event("strength:cycle_mark", %{"muscle" => muscle}, socket),
    do: {:noreply, update(socket, :marks, &cycle_mark(&1, muscle))}

  def handle_event("strength:show_body", _, socket),
    do: {:noreply, update(socket, :show_body, &(not &1))}

  def handle_event("strength:debug_pose", %{"pose" => pose}, socket)
      when pose in ~w(neutral carry squat hinge press pushup mobility) do
    {:noreply, assign(socket, :debug_pose, pose)}
  end

  def handle_event("strength:save_pose", %{"pose" => pose, "settings" => settings}, socket) do
    case Strength.save_pose(pose, settings) do
      :ok ->
        {:noreply,
         socket |> put_flash(:info, "Postura guardada en tu vault personal.") |> refresh()}

      _ ->
        {:noreply, put_flash(socket, :error, "No se pudo guardar la postura.")}
    end
  end

  def handle_event("strength:show_blocked", _, socket),
    do: {:noreply, update(socket, :show_blocked, &(not &1))}

  def handle_event("strength:log_date", %{"action" => "previous"}, socket),
    do: {:noreply, shift_log_date(socket, -1)}

  def handle_event("strength:log_date", %{"action" => "next"}, socket) do
    if socket.assigns.log_day < 0 do
      {:noreply, shift_log_date(socket, 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("strength:log_date", %{"action" => action}, socket)
      when action in ["today", "latest"],
      do: {:noreply, set_log_date(socket, 0)}

  def handle_event("strength:log_muscle", %{"muscle" => muscle}, socket) do
    muscles = socket.assigns.log_muscles

    {:noreply,
     socket
     |> assign(
       :log_muscles,
       if(MapSet.member?(muscles, muscle),
         do: MapSet.delete(muscles, muscle),
         else: MapSet.put(muscles, muscle)
       )
     )
     |> refresh_log_effort()}
  end

  def handle_event("strength:log_exercise", %{"id" => id}, socket) do
    exercise_ids = MapSet.new(Enum.map(Strength.exercises(), & &1.id))

    if MapSet.member?(exercise_ids, id) do
      exercises = socket.assigns.log_exercises

      {:noreply,
       socket
       |> assign(
         :log_exercises,
         if(MapSet.member?(exercises, id),
           do: MapSet.delete(exercises, id),
           else: MapSet.put(exercises, id)
         )
       )
       |> refresh_log_effort()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("strength:save_session", _, socket) do
    case Strength.save_session(
           log_date(socket.assigns.log_day),
           Map.keys(socket.assigns.log_effort),
           socket.assigns.log_exercises |> MapSet.to_list() |> Enum.sort()
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:log_muscles, MapSet.new())
         |> assign(:log_exercises, MapSet.new())
         |> assign(:log_effort, %{})
         |> put_flash(:info, "Sesión guardada como hábito de ejercicio.")
         |> refresh()}

      _ ->
        {:noreply, put_flash(socket, :error, "No se pudo guardar la sesión.")}
    end
  end

  def handle_event("strength:delete_session", %{"id" => id}, socket) do
    case Strength.delete_session(id) do
      :ok -> {:noreply, socket |> put_flash(:info, "Sesión borrada.") |> refresh()}
      _ -> {:noreply, put_flash(socket, :error, "No se pudo borrar la sesión.")}
    end
  end

  def handle_event("strength:joint", %{"joint" => joint}, socket),
    do:
      {:noreply,
       assign(
         socket,
         :joint_filter,
         if(socket.assigns.joint_filter == joint, do: nil, else: joint)
       )}

  def handle_event("strength:test", %{"id" => id, "level" => level}, socket),
    do: {:noreply, update(socket, :test_selection, &Map.put(&1, id, String.to_integer(level)))}

  def handle_event("strength:save_tests", _, socket) do
    :ok = Strength.save_tests(socket.assigns.test_selection)
    {:noreply, socket |> put_flash(:info, "Chequeo guardado en tu vault personal.") |> refresh()}
  end

  def handle_event("strength:pattern", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :open_pattern, toggle(socket.assigns.open_pattern, id))}

  def handle_event("strength:stage", %{"pattern" => pattern, "stage" => stage}, socket) do
    :ok = Strength.save_level(pattern, String.to_integer(stage))
    {:noreply, refresh(socket)}
  end

  defp refresh_log_effort(socket) do
    selected_exercises = socket.assigns.log_exercises

    totals =
      Strength.exercises()
      |> Enum.filter(&MapSet.member?(selected_exercises, &1.id))
      |> Enum.reduce(%{}, fn exercise, effort ->
        Enum.reduce(exercise.effort, effort, fn {muscle, level}, accumulator ->
          Map.update(accumulator, muscle, level, &(&1 + level))
        end)
      end)
      |> then(fn effort ->
        Enum.reduce(socket.assigns.log_muscles, effort, fn muscle, accumulator ->
          Map.update(accumulator, muscle, 1.0, &max(&1, 1.0))
        end)
      end)

    peak = totals |> Map.values() |> Enum.max(fn -> 0 end)

    normalized =
      if peak == 0 do
        %{}
      else
        Map.new(totals, fn {muscle, total} -> {muscle, Float.round(total / peak, 2)} end)
      end

    assign(socket, :log_effort, normalized)
  end

  defp shift_log_date(socket, delta), do: set_log_date(socket, socket.assigns.log_day + delta)

  defp set_log_date(socket, day) do
    socket
    |> assign(:log_day, min(day, 0))
    |> assign(:log_muscles, MapSet.new())
    |> assign(:log_exercises, MapSet.new())
    |> assign(:log_effort, %{})
  end

  defp log_date(day_offset), do: Date.add(Clock.today(), day_offset)

  defp log_date_label(0), do: "Viendo hoy"

  defp log_date_label(-1),
    do: "Viendo ayer (#{spanish_date(log_date(-1))})"

  defp log_date_label(day_offset), do: "Viendo #{spanish_date(log_date(day_offset))}"

  defp spanish_date(date) do
    weekday =
      %{
        1 => "lunes",
        2 => "martes",
        3 => "miércoles",
        4 => "jueves",
        5 => "viernes",
        6 => "sábado",
        7 => "domingo"
      }
      |> Map.fetch!(Date.day_of_week(date))

    month =
      %{
        1 => "ene",
        2 => "feb",
        3 => "mar",
        4 => "abr",
        5 => "may",
        6 => "jun",
        7 => "jul",
        8 => "ago",
        9 => "sep",
        10 => "oct",
        11 => "nov",
        12 => "dic"
      }
      |> Map.fetch!(date.month)

    "#{weekday} #{date.day}-#{month}-#{date.year}"
  end

  defp session_for_log_date?(sessions, day_offset) do
    date = log_date(day_offset) |> Date.to_iso8601()
    Enum.any?(sessions, &(&1.date == date))
  end

  defp session_heatmap_key(effort), do: :erlang.phash2(effort)

  defp refresh(socket) do
    profile = Strength.profile()
    snapshots = profile["tests"] || []

    selection =
      if List.first(snapshots),
        do: List.first(snapshots)["results"] || %{},
        else: socket.assigns[:test_selection] || %{}

    socket
    |> assign(:sessions, Strength.list_sessions())
    |> assign(:profile, profile)
    |> assign(:snapshots, snapshots)
    |> assign(:poses, profile["poses"] || %{})
    |> assign(:test_selection, selection)
  end

  defp toggle(current, id), do: if(current == id, do: nil, else: id)

  defp cycle_mark(marks, muscle) do
    case marks[muscle] do
      nil -> Map.put(marks, muscle, :avoid)
      :avoid -> Map.put(marks, muscle, :focus)
      :focus -> Map.delete(marks, muscle)
    end
  end

  defp date_label(date), do: Calendar.strftime(date, "%a %-d %b")

  defp youtube(name),
    do:
      "https://www.youtube.com/results?search_query=" <>
        URI.encode_www_form(name <> " ejercicio técnica")

  defp muscle_name(id), do: Strength.muscles()[id]
  defp exercise(id), do: Enum.find(Strength.exercises(), &(&1.id == id))
  defp exercise_name(id), do: (exercise(id) || %{})[:name]
  defp linked_functions(id), do: Enum.filter(Strength.functions(), &(id in &1.exercises))
  defp routine_exercises(routine), do: Enum.filter(Strength.exercises(), &(&1.routine == routine))

  defp available_exercises(marks) do
    Strength.exercises()
    |> Enum.map(fn ex ->
      %{
        exercise: ex,
        blocked: Enum.filter(ex.muscles, fn muscle -> marks[muscle] == :avoid end),
        hits: Enum.count(ex.muscles, fn muscle -> marks[muscle] == :focus end)
      }
    end)
    |> Enum.sort_by(fn item -> {-item.hits, item.exercise.name} end)
  end

  defp recent?(sessions, muscle),
    do:
      Enum.any?(sessions, fn s ->
        muscle in s.muscles and Date.diff(Clock.today(), parse_date(s.date)) <= 1
      end)

  defp parse_date(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> date
      _ -> ~D[2000-01-01]
    end
  end

  defp recent_levels(sessions),
    do:
      Enum.reduce(sessions, %{}, fn s, acc ->
        days = Date.diff(Clock.today(), parse_date(s.date))

        if days in 0..7,
          do:
            Enum.reduce(
              s.muscles,
              acc,
              &Map.update(&2, &1, max(0, 1 - days / 7) / 1.5, fn n ->
                min(1, n + max(0, 1 - days / 7) / 1.5)
              end)
            ),
          else: acc
      end)

  defp weekly_loads(week, days) do
    schedule = if week == 1, do: ["A", "B", "A"], else: ["B", "A", "B"]

    Enum.zip(schedule, days)
    |> Enum.reduce(%{}, fn {routine, enabled}, loads ->
      if enabled,
        do:
          Enum.reduce(routine_exercises(routine), loads, fn ex, acc ->
            Enum.reduce(ex.muscles, acc, &Map.update(&2, &1, 3, fn n -> n + 3 end))
          end),
        else: loads
    end)
  end

  defp test_score(results), do: results |> Map.values() |> Enum.map(&as_int/1) |> Enum.sum()
  defp as_int(value) when is_integer(value), do: value
  defp as_int(value) when is_binary(value), do: String.to_integer(value)
  defp gate_ok?(nil, _results), do: true

  defp gate_ok?({test, minimum, _label, _drills}, results),
    do: as_int(Map.get(results, test, -1)) >= minimum

  defp gate_label({_, _, label, drills}),
    do: "#{label} · drills: #{Enum.map_join(drills, ", ", &drill_name/1)}"

  defp drill_name(id), do: (Enum.find(Strength.drills(), &(&1.id == id)) || %{})[:name]
  defp routine_label("X"), do: "EXTRA"
  defp routine_label(routine), do: routine

  defp routine_badge("A"),
    do: "ml-1 rounded bg-sky-100 px-1.5 py-0.5 font-mono text-[10px] font-bold text-sky-900"

  defp routine_badge("B"),
    do:
      "ml-1 rounded bg-emerald-100 px-1.5 py-0.5 font-mono text-[10px] font-bold text-emerald-900"

  defp routine_badge("X"),
    do: "ml-1 rounded bg-amber-100 px-1.5 py-0.5 font-mono text-[10px] font-bold text-amber-900"

  defp mark_symbol(:avoid), do: "✕"
  defp mark_symbol(:focus), do: "✓"
  defp mark_symbol(_), do: ""
  defp mark_color(:avoid), do: "#e07b6b"
  defp mark_color(:focus), do: "#2e9e5b"
  defp mark_color(_), do: "#9ec6e0"

  defp effort_label(level) when level >= 0.8, do: "principal"
  defp effort_label(level) when level >= 0.5, do: "medio"
  defp effort_label(_level), do: "apoyo"

  defp effort_chip_class(level) when level >= 0.8,
    do: "rounded-full bg-red-400/15 px-3 py-1 text-xs text-red-200"

  defp effort_chip_class(level) when level >= 0.5,
    do: "rounded-full bg-amber-300/15 px-3 py-1 text-xs text-amber-100"

  defp effort_chip_class(_level),
    do: "rounded-full bg-emerald-300/15 px-3 py-1 text-xs text-emerald-100"

  defp muscle_chip_class(:avoid),
    do:
      "rounded-full border border-red-400 bg-red-950/50 px-3 py-1.5 text-xs font-semibold text-red-200"

  defp muscle_chip_class(:focus),
    do:
      "rounded-full border border-emerald-400 bg-emerald-950/50 px-3 py-1.5 text-xs font-semibold text-emerald-200"

  defp muscle_chip_class(:selected),
    do:
      "rounded-full border border-sky-400 bg-sky-950 px-3 py-1.5 text-xs font-semibold text-sky-100"

  defp muscle_chip_class(_),
    do:
      "rounded-full border border-slate-700 bg-slate-800 px-3 py-1.5 text-xs font-semibold text-slate-300"

  defp test_level_class(selected, level) when selected == level and level == 0,
    do: "border-red-400 bg-red-950/40 text-red-200"

  defp test_level_class(selected, level) when selected == level and level == 1,
    do: "border-amber-400 bg-amber-950/40 text-amber-100"

  defp test_level_class(selected, level) when selected == level and level == 2,
    do: "border-emerald-400 bg-emerald-950/40 text-emerald-100"

  defp test_level_class(_, _), do: "border-slate-700 bg-slate-800 text-slate-300"

  defp score_delta(snapshot, previous) do
    delta = test_score(snapshot["results"] || %{}) - test_score(previous["results"] || %{})
    if delta >= 0, do: "▲ +#{delta}", else: "▼ #{delta}"
  end

  defp stage_marker(nil, index), do: index + 1
  defp stage_marker(current, index) when index < current, do: "✓"
  defp stage_marker(current, index) when index == current, do: "●"
  defp stage_marker(_current, index), do: index + 1

  defp stage_marker_class(nil, _),
    do:
      "flex size-6 shrink-0 items-center justify-center rounded-full border border-slate-600 font-mono text-xs text-slate-400"

  defp stage_marker_class(current, index) when index < current,
    do:
      "flex size-6 shrink-0 items-center justify-center rounded-full bg-emerald-400 font-bold text-emerald-950"

  defp stage_marker_class(current, index) when index == current,
    do:
      "flex size-6 shrink-0 items-center justify-center rounded-full bg-sky-500 font-bold text-white"

  defp stage_marker_class(_current, _index),
    do:
      "flex size-6 shrink-0 items-center justify-center rounded-full border border-sky-400 font-mono text-xs text-sky-300"

  attr :exercise, :map, required: true
  attr :open, :boolean, required: true
  attr :poses, :map, default: %{}

  defp exercise_card(assigns) do
    ~H"""
    <% pose_source = exercise_pose_source(@exercise, @poses) %>
    <article class={[
      "overflow-hidden rounded-2xl border bg-slate-900",
      if(@open, do: "border-sky-400", else: "border-slate-700")
    ]}>
      <button
        class="flex w-full items-center gap-2 p-4 text-left"
        phx-click="strength:toggle"
        phx-value-id={@exercise.id}
        aria-expanded={@open}
      >
        <span class="min-w-0 flex-1 text-sm font-bold">
          {@exercise.name}
          <span class={routine_badge(@exercise.routine)}>{routine_label(@exercise.routine)}</span><span
            :if={@exercise[:new]}
            class="ml-1 rounded bg-amber-200 px-1.5 py-0.5 text-[10px] text-amber-900"
          >nuevo</span>
        </span>
        <span class="text-xl text-slate-400">{if @open, do: "−", else: "+"}</span>
      </button>
      <div :if={@open} class="border-t border-dashed border-slate-700 p-4">
        <p class="text-sm leading-6 text-slate-300">{@exercise.note}</p>
        <div class="mt-3 rounded-xl bg-slate-800 p-3">
          <p class="text-xs font-semibold uppercase tracking-widest text-slate-500">Cómo se hace</p>
          <ol class="mt-2 list-decimal space-y-1 pl-4 text-xs leading-5 text-slate-300">
            <li :for={step <- @exercise.how}>{step}</li>
          </ol>
          <a
            class="mt-2 inline-block text-xs font-bold text-sky-300"
            href={youtube(@exercise.name)}
            target="_blank"
            rel="noreferrer"
          >
            ▶ Ver video de técnica
          </a>
        </div>
        <.body_map
          id={"strength-exercise-#{@exercise.id}"}
          mode={:heat}
          active={Map.keys(@exercise.effort)}
          levels={@exercise.effort}
          pose={exercise_pose(@exercise.id)}
          pose_key={"exercise-#{@exercise.id}"}
          pose_settings={pose_source.settings}
          pose_label={pose_source.label}
          pose_origin={pose_source.origin}
        />
        <div class="flex flex-wrap items-center gap-2">
          <span
            :for={muscle <- @exercise.muscles}
            class={effort_chip_class(@exercise.effort[muscle])}
          >
            {muscle_name(muscle)} · {effort_label(@exercise.effort[muscle])}
          </span>
        </div>
        <p class="mt-2 text-xs text-slate-500">
          Color = contribución relativa estimada dentro de este ejercicio: verde menor, amarillo media, rojo principal.
        </p>
        <p :if={linked_functions(@exercise.id) != []} class="mt-3 text-xs text-slate-400">
          <span :for={goal <- linked_functions(@exercise.id)} class="mr-2">
            <b class="text-sky-300">{goal.tag}</b> {goal.title}
          </span>
        </p>
        <p :if={linked_functions(@exercise.id) == []} class="mt-3 text-xs text-slate-400">
          Comodín: sustituye a <b>{exercise_name(@exercise.substitute)}</b> cuando ese no cuadre.
        </p>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :mode, :atom, default: :binary
  attr :active, :list, default: []
  attr :levels, :map, default: %{}
  attr :colors, :map, default: %{}
  attr :joints, :list, default: []
  attr :event, :string, default: nil
  attr :pose, :string, default: "neutral"
  attr :pose_key, :string, default: nil
  attr :pose_settings, :map, default: %{}
  attr :pose_label, :string, default: nil
  attr :pose_origin, :string, default: nil
  attr :class, :string, default: nil

  defp body_map(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="StrengthBody"
      phx-update="ignore"
      data-mode={@mode}
      data-active={Jason.encode!(@active)}
      data-levels={Jason.encode!(@levels)}
      data-colors={Jason.encode!(@colors)}
      data-joints={Jason.encode!(@joints)}
      data-pose={@pose}
      data-pose-key={@pose_key || @pose}
      data-pose-settings={Jason.encode!(@pose_settings)}
      data-body-event={@event}
      data-visual-model="mannequin-overlay"
      data-rig="articulated-ik"
      class={[
        "strength-body my-4 overflow-hidden rounded-2xl border border-sky-400/20 bg-[#07111c]",
        @class
      ]}
      aria-label="Maniquí 3D interactivo"
    >
      <div data-role="canvas" class="h-96 min-h-[22rem] w-full touch-none"></div>
      <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 border-t border-sky-300/10 bg-slate-950/60 px-3 py-2">
        <div class="min-w-0">
          <p data-role="label" class="text-xs text-slate-400">
            Arrastra para rotar · gira para ver frente y espalda
          </p>
          <p :if={@pose_label} data-role="pose-source" class="mt-0.5 text-[11px] text-sky-200">
            Postura: {@pose_label} · {@pose_origin}
          </p>
        </div>
        <div class="flex items-center gap-1" aria-label="Atajos de cámara">
          <button
            data-camera-view="front"
            type="button"
            class="rounded bg-sky-300/10 px-2 py-1 font-mono text-[10px] font-bold uppercase tracking-wider text-sky-200 hover:bg-sky-300/20"
          >
            Frente
          </button>
          <button
            data-camera-view="back"
            type="button"
            class="rounded bg-sky-300/10 px-2 py-1 font-mono text-[10px] font-bold uppercase tracking-wider text-sky-200 hover:bg-sky-300/20"
          >
            Espalda
          </button>
          <button
            data-camera-view="side"
            type="button"
            class="rounded bg-sky-300/10 px-2 py-1 font-mono text-[10px] font-bold uppercase tracking-wider text-sky-200 hover:bg-sky-300/20"
          >
            Lateral
          </button>
          <button
            data-camera-view="left"
            type="button"
            class="rounded bg-sky-300/10 px-2 py-1 font-mono text-[10px] font-bold uppercase tracking-wider text-sky-200 hover:bg-sky-300/20"
          >
            Izq.
          </button>
          <button
            data-camera-view="right"
            type="button"
            class="rounded bg-sky-300/10 px-2 py-1 font-mono text-[10px] font-bold uppercase tracking-wider text-sky-200 hover:bg-sky-300/20"
          >
            Der.
          </button>
          <button
            data-role="edit-pose"
            type="button"
            class="ml-1 rounded bg-amber-300/15 px-2 py-1 font-mono text-[10px] font-bold text-amber-200 hover:bg-amber-300/25"
            title="Editar postura y cámara"
          >
            ✏️ Editar
          </button>
          <span class="ml-1 rounded-full bg-sky-300/10 px-2 py-1 font-mono text-[10px] font-bold uppercase tracking-wider text-sky-200">
            3D
          </span>
        </div>
      </div>
      <div data-role="editor-panel" hidden class="border-t border-amber-300/20 bg-slate-950 px-3 py-3">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="font-mono text-xs font-bold uppercase tracking-wider text-amber-200">
              Editor de postura
            </p>
            <p data-role="editor-status" class="mt-1 text-xs text-slate-400">
              Selecciona un joint y arrástralo en el plano de cámara, o fija un eje. Al soltar, el rig asienta su joint de soporte más bajo sobre el plano.
            </p>
          </div>
          <button
            data-editor-action="close"
            type="button"
            class="text-xs text-slate-400 hover:text-white"
          >
            Cerrar
          </button>
        </div>
        <div class="mt-3 flex flex-wrap gap-1" aria-label="Eje de manipulación">
          <button
            data-editor-axis="camera"
            type="button"
            class="rounded bg-sky-300/15 px-2 py-1 font-mono text-[10px] font-bold text-sky-200"
          >
            Auto plano
          </button>
          <button
            data-editor-axis="x"
            type="button"
            class="rounded bg-red-400/15 px-2 py-1 font-mono text-[10px] font-bold text-red-200"
          >
            X
          </button>
          <button
            data-editor-axis="y"
            type="button"
            class="rounded bg-emerald-400/15 px-2 py-1 font-mono text-[10px] font-bold text-emerald-200"
          >
            Y
          </button>
          <button
            data-editor-axis="z"
            type="button"
            class="rounded bg-sky-400/15 px-2 py-1 font-mono text-[10px] font-bold text-sky-200"
          >
            Z
          </button>
        </div>
        <div class="mt-3 grid gap-3 sm:grid-cols-3">
          <label class="text-xs text-slate-400">
            Desplazar X<input
              data-editor-transform="x"
              type="range"
              min="-2"
              max="2"
              step="0.05"
              class="mt-1 w-full"
            />
          </label>
          <label class="text-xs text-slate-400">
            Desplazar Y<input
              data-editor-transform="y"
              type="range"
              min="-2"
              max="2"
              step="0.05"
              class="mt-1 w-full"
            />
          </label>
          <label class="text-xs text-slate-400">
            Desplazar Z<input
              data-editor-transform="z"
              type="range"
              min="-2"
              max="2"
              step="0.05"
              class="mt-1 w-full"
            />
          </label>
          <label class="text-xs text-slate-400">
            Rotación X<input
              data-editor-transform="rotation-x"
              type="range"
              min="-3.14"
              max="3.14"
              step="0.05"
              class="mt-1 w-full"
            />
          </label>
          <label class="text-xs text-slate-400">
            Rotación Y<input
              data-editor-transform="rotation-y"
              type="range"
              min="-3.14"
              max="3.14"
              step="0.05"
              class="mt-1 w-full"
            />
          </label>
          <label class="text-xs text-slate-400">
            Rotación Z<input
              data-editor-transform="rotation-z"
              type="range"
              min="-3.14"
              max="3.14"
              step="0.05"
              class="mt-1 w-full"
            />
          </label>
        </div>
        <div class="mt-3 flex flex-wrap gap-1 text-[10px] font-mono uppercase tracking-wider text-slate-500">
          <span data-editor-rig="shoulder">hombro</span><span>→</span><span data-editor-rig="elbow">codo</span><span>→</span><span data-editor-rig="wrist">muñeca</span>
          <span class="mx-2">|</span>
          <span data-editor-rig="hip">cadera</span><span>→</span><span data-editor-rig="knee">rodilla</span><span>→</span><span data-editor-rig="ankle">tobillo</span>
        </div>
        <div class="mt-3 flex flex-wrap justify-end gap-2">
          <button
            data-editor-action="ground"
            type="button"
            class="rounded bg-emerald-300/15 px-3 py-1.5 text-xs font-bold text-emerald-200 hover:bg-emerald-300/25"
          >
            Asentar al plano
          </button>
          <button
            data-editor-action="reset"
            type="button"
            class="rounded px-3 py-1.5 text-xs font-bold text-slate-300 hover:bg-slate-800"
          >
            Restablecer
          </button>
          <button
            data-editor-action="save"
            type="button"
            class="rounded bg-amber-300 px-3 py-1.5 text-xs font-bold text-slate-950 hover:bg-amber-200"
          >
            Guardar postura
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp goal_pose("jug"), do: "carry"
  defp goal_pose("pour"), do: "press"
  defp goal_pose("floor"), do: "squat"
  defp goal_pose("desk"), do: "neutral"
  defp goal_pose("play"), do: "squat"
  defp goal_pose("baby"), do: "carry"
  defp goal_pose(_), do: "neutral"

  defp exercise_pose(id) when id in ["goblet", "bulgarian", "stepup"], do: "squat"
  defp exercise_pose(id) when id in ["rdl", "bridge", "birddog"], do: "hinge"
  defp exercise_pose(id) when id in ["ohp", "cleanpress", "waiter"], do: "press"
  defp exercise_pose(id) when id in ["pushup", "floorpress", "plank", "deadbug"], do: "pushup"
  defp exercise_pose(id) when id in ["farmer", "suitcase", "shrug", "hammercurl"], do: "carry"
  defp exercise_pose(_), do: "neutral"

  defp exercise_pose_source(exercise, poses) do
    specific_key = "exercise-#{exercise.id}"
    family = exercise_pose(exercise.id)

    cond do
      is_map(poses[specific_key]) ->
        %{label: exercise.name, origin: "ajuste específico", settings: poses[specific_key]}

      is_map(poses[family]) ->
        %{label: family, origin: "preset compartido", settings: poses[family]}

      true ->
        %{label: family, origin: "preset base compartido", settings: %{}}
    end
  end

  defp drill_pose(id) when id in ["wgs", "deepsquat", "anklerock"], do: "squat"
  defp drill_pose(id) when id in ["hipflexor", "hamstring", "standhinge"], do: "hinge"

  defp drill_pose(id) when id in ["doorpec", "childreach", "armwrist", "wristflow"],
    do: "mobility"

  defp drill_pose(_), do: "neutral"

  defp pattern_pose("squat"), do: "squat"
  defp pattern_pose("hinge"), do: "hinge"
  defp pattern_pose("carry"), do: "carry"
  defp pattern_pose("push"), do: "pushup"
  defp pattern_pose(_), do: "neutral"

  defp pattern_active("squat"), do: ["quads", "glutes", "core"]
  defp pattern_active("hinge"), do: ["hams", "glutes", "erectors", "grip"]
  defp pattern_active("pull"), do: ["upperback", "traps", "arms", "grip"]
  defp pattern_active("carry"), do: ["grip", "traps", "core", "obliques"]
  defp pattern_active("push"), do: ["chest", "arms", "shoulders", "core"]
  defp pattern_active("core"), do: ["core", "obliques", "shoulders"]
  defp pattern_active(_), do: []
end
