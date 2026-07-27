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
    {"movilidad", "Movilidad"}
  ]
  @phases [
    {"warm", "Antes de entrenar · 5 min · dinámico"},
    {"cool", "Después · 3–4 min · estático"},
    {"snack", "Snacks de escritorio · 2 min"}
  ]

  defp tabs, do: @tabs
  defp phases, do: @phases

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
     |> assign(:show_blocked, false)
     |> assign(:log_day, 0)
     |> assign(:log_muscles, MapSet.new())
     |> assign(:joint_filter, nil)
     |> assign(:test_selection, %{})
     |> assign(:open_pattern, nil)
     |> refresh()}
  end

  @impl true
  def handle_info(:vault_changed, socket), do: {:noreply, refresh(socket)}

  @impl true
  def handle_event("strength:tab", %{"tab" => tab}, socket)
      when tab in ~w(hoy escalera metas ejercicios rutinas movilidad) do
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

  def handle_event("strength:show_blocked", _, socket),
    do: {:noreply, update(socket, :show_blocked, &(not &1))}

  def handle_event("strength:log_day", %{"offset" => offset}, socket),
    do: {:noreply, assign(socket, :log_day, String.to_integer(offset))}

  def handle_event("strength:log_muscle", %{"muscle" => muscle}, socket) do
    muscles = socket.assigns.log_muscles

    {:noreply,
     assign(
       socket,
       :log_muscles,
       if(MapSet.member?(muscles, muscle),
         do: MapSet.delete(muscles, muscle),
         else: MapSet.put(muscles, muscle)
       )
     )}
  end

  def handle_event("strength:save_session", _, socket) do
    case Strength.save_session(
           Date.add(Clock.today(), -socket.assigns.log_day),
           MapSet.to_list(socket.assigns.log_muscles)
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:log_muscles, MapSet.new())
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

  defp exercise_card(assigns) do
    ~H"""
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
          active={@exercise.muscles}
          pose={exercise_pose(@exercise.id)}
        />
        <div class="flex flex-wrap gap-2">
          <span
            :for={muscle <- @exercise.muscles}
            class="rounded-full bg-slate-800 px-3 py-1 text-xs text-slate-300"
          >
            {muscle_name(muscle)}
          </span>
        </div>
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
      data-body-event={@event}
      data-visual-model="mannequin-overlay"
      class={[
        "strength-body my-4 overflow-hidden rounded-2xl border border-sky-400/20 bg-[#07111c]",
        @class
      ]}
      aria-label="Maniquí 3D interactivo"
    >
      <div data-role="canvas" class="h-96 min-h-[22rem] w-full touch-none"></div>
      <div class="flex items-center justify-between gap-3 border-t border-sky-300/10 bg-slate-950/60 px-3 py-2">
        <p data-role="label" class="text-xs text-slate-400">
          Arrastra para rotar · gira para ver frente y espalda
        </p>
        <span class="rounded-full bg-sky-300/10 px-2 py-1 font-mono text-[10px] font-bold uppercase tracking-wider text-sky-200">
          3D
        </span>
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
