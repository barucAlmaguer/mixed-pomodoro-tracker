defmodule PomodoroTracker.Timer do
  @moduledoc """
  Single pomodoro timer, server-side. Survives page reloads and syncs across
  browser tabs / devices via PubSub.

  Phases:
    :idle          - not running
    :work          - focus interval (ticks)
    :active_break  - short break with a quick personal task
    :passive_break - short break with no task
    :long_break    - after N work intervals

  The timer keeps track of every task and zone touched during the current
  interval so finished sessions can later be classified as `work`,
  `personal`, or mixed.
  """

  use GenServer
  require Logger

  @topic "timer"
  def topic, do: @topic

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def state, do: GenServer.call(__MODULE__, :state)

  def start_work(zone, task_ids) when zone in [:work, :personal] and is_list(task_ids),
    do: start_work(zone, task_ids, [zone])

  def start_work(zone, task_ids, zones)
      when zone in [:work, :personal] and is_list(task_ids) and is_list(zones),
      do:
        GenServer.call(
          __MODULE__,
          {:start, :work, zone, task_ids, normalize_zones([zone | zones])}
        )

  def start_break(kind, override_minutes \\ nil)
      when kind in [:active_break, :passive_break],
      do: GenServer.call(__MODULE__, {:start_break, kind, override_minutes})

  @doc """
  Updates the active task_ids without touching the timer countdown. Use this
  when the user picks a different task mid-pomodoro or mid-break — the timer
  continues, and every task touched during the work pomodoro gets credited at
  the end.
  """
  def switch_tasks(task_ids) when is_list(task_ids), do: switch_tasks(task_ids, [])

  def switch_tasks(task_ids, zones) when is_list(task_ids) and is_list(zones),
    do: GenServer.call(__MODULE__, {:switch_tasks, task_ids, normalize_zones(zones)})

  def pause, do: GenServer.call(__MODULE__, :pause)
  def resume, do: GenServer.call(__MODULE__, :resume)
  def reset, do: GenServer.call(__MODULE__, :reset)
  def skip, do: GenServer.call(__MODULE__, :skip)

  def adjust(delta_ms) when is_integer(delta_ms),
    do: GenServer.call(__MODULE__, {:adjust, delta_ms})

  @doc "Minutes the next break would use, given rounds completed so far."
  def default_break_minutes(rounds_completed) do
    if rounds_completed > 0 and rem(rounds_completed, 4) == 0,
      do: cfg(:long_break_minutes),
      else: cfg(:break_minutes)
  end

  def work_minutes, do: cfg(:work_minutes)

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    {:ok,
     %{
       phase: :idle,
       zone: nil,
       task_ids: [],
       visited_tasks: MapSet.new(),
       visited_zones: MapSet.new(),
       remaining_ms: 0,
       duration_ms: 0,
       running: false,
       rounds_completed: 0,
       tref: nil,
       started_at: nil
     }}
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, public(state), state}

  # Switch active task(s) without touching the timer. While in :work, every
  # task switched into is added to visited_tasks so finish() credits them all.
  def handle_call({:switch_tasks, task_ids, zones}, _from, state) do
    visited_tasks =
      case state.phase do
        phase when phase in [:work, :active_break] ->
          MapSet.union(state.visited_tasks, MapSet.new(task_ids))

        _ ->
          state.visited_tasks
      end

    visited_zones =
      case state.phase do
        :work ->
          MapSet.union(state.visited_zones, MapSet.new(zones))

        :active_break ->
          personal_only = Enum.filter(zones, &(&1 == :personal))
          MapSet.union(state.visited_zones, MapSet.new(personal_only))

        _ ->
          state.visited_zones
      end

    new = %{
      state
      | task_ids: task_ids,
        visited_tasks: visited_tasks,
        visited_zones: visited_zones,
        zone: display_zone(zones, state.zone)
    }

    {:reply, :ok, broadcast(new)}
  end

  def handle_call({:start, :work, zone, task_ids, zones}, _from, state) do
    cancel(state.tref)
    ms = cfg(:work_minutes) * 60_000

    new = %{
      state
      | phase: :work,
        zone: display_zone(zones, zone),
        task_ids: task_ids,
        visited_tasks: MapSet.new(task_ids),
        visited_zones: MapSet.new(zones),
        remaining_ms: ms,
        duration_ms: ms,
        running: true,
        started_at: now()
    }

    {:reply, :ok, schedule(new) |> broadcast()}
  end

  def handle_call({:start_break, kind, override_minutes}, _from, state) do
    cancel(state.tref)

    minutes = override_minutes || default_break_minutes(state.rounds_completed)
    ms = minutes * 60_000

    new = %{
      state
      | phase: kind,
        zone: nil,
        task_ids: [],
        visited_tasks: MapSet.new(),
        visited_zones: MapSet.new(),
        remaining_ms: ms,
        duration_ms: ms,
        running: true,
        started_at: now()
    }

    {:reply, :ok, schedule(new) |> broadcast()}
  end

  def handle_call({:adjust, _delta}, _from, %{phase: :idle} = state),
    do: {:reply, :noop, state}

  def handle_call({:adjust, delta_ms}, _from, state) do
    new_remaining = max(5_000, state.remaining_ms + delta_ms)

    new_duration =
      if delta_ms > 0 do
        state.duration_ms + delta_ms
      else
        max(new_remaining, state.duration_ms + delta_ms)
      end

    cancel(state.tref)
    new = %{state | remaining_ms: new_remaining, duration_ms: new_duration}
    new = if state.running, do: schedule(new), else: new
    {:reply, :ok, broadcast(new)}
  end

  def handle_call(:pause, _from, state) do
    cancel(state.tref)
    {:reply, :ok, broadcast(%{state | running: false, tref: nil})}
  end

  def handle_call(:resume, _from, %{phase: :idle} = state), do: {:reply, :noop, state}

  def handle_call(:resume, _from, state) do
    {:reply, :ok, schedule(%{state | running: true}) |> broadcast()}
  end

  def handle_call(:reset, _from, state) do
    cancel(state.tref)

    {:reply, :ok,
     broadcast(%{
       state
       | phase: :idle,
         zone: nil,
         task_ids: [],
         visited_tasks: MapSet.new(),
         visited_zones: MapSet.new(),
         remaining_ms: 0,
         duration_ms: 0,
         running: false,
         tref: nil,
         started_at: nil
     })}
  end

  def handle_call(:skip, _from, state) do
    cancel(state.tref)
    {:reply, :ok, advance(state) |> broadcast()}
  end

  @impl true
  def handle_info(:tick, state) do
    remaining = state.remaining_ms - 1000

    if remaining <= 0 do
      {:noreply, finish(state) |> broadcast()}
    else
      new = %{state | remaining_ms: remaining}
      {:noreply, schedule(new) |> broadcast()}
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp schedule(%{running: true} = state) do
    ref = Process.send_after(self(), :tick, 1000)
    %{state | tref: ref}
  end

  defp schedule(state), do: %{state | tref: nil}

  defp cancel(nil), do: :ok
  defp cancel(ref), do: Process.cancel_timer(ref)

  defp finish(%{phase: :work} = state) do
    credited = MapSet.to_list(state.visited_tasks)
    ended_at = now()

    PomodoroTracker.Vault.log_session(%{
      phase: :work,
      minutes: div(state.duration_ms, 60_000),
      started_at: state.started_at,
      ended_at: ended_at,
      zones: MapSet.to_list(state.visited_zones),
      tasks: credited
    })

    increment_day_pomodoros(credited)

    rounds = state.rounds_completed + 1

    %{
      state
      | rounds_completed: rounds,
        phase: :idle,
        zone: nil,
        task_ids: [],
        running: false,
        tref: nil,
        visited_tasks: MapSet.new(),
        visited_zones: MapSet.new(),
        remaining_ms: 0,
        duration_ms: 0,
        started_at: nil
    }
  end

  defp finish(state) do
    ended_at = now()

    {tasks, zones} =
      case state.phase do
        :active_break ->
          {MapSet.to_list(state.visited_tasks), MapSet.to_list(state.visited_zones)}

        _ ->
          {[], []}
      end

    PomodoroTracker.Vault.log_session(%{
      phase: state.phase,
      minutes: div(state.duration_ms, 60_000),
      started_at: state.started_at,
      ended_at: ended_at,
      zones: zones,
      tasks: tasks
    })

    %{
      state
      | phase: :idle,
        zone: nil,
        task_ids: [],
        running: false,
        tref: nil,
        visited_tasks: MapSet.new(),
        visited_zones: MapSet.new(),
        remaining_ms: 0,
        duration_ms: 0,
        started_at: nil
    }
  end

  defp advance(%{phase: :work} = state), do: finish(state)
  defp advance(state), do: finish(state)

  defp increment_day_pomodoros(task_ids) do
    {:ok, day} = PomodoroTracker.Vault.load_day()

    pomos =
      Enum.reduce(task_ids, day.pomodoros, fn id, acc ->
        Map.update(acc, id, 1, &(&1 + 1))
      end)

    PomodoroTracker.Vault.save_day(%{day | pomodoros: pomos})
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(PomodoroTracker.PubSub, @topic, {:timer, public(state)})
    state
  end

  defp public(state) do
    Map.take(state, [
      :phase,
      :zone,
      :started_at,
      :task_ids,
      :remaining_ms,
      :duration_ms,
      :running,
      :rounds_completed
    ])
    |> Map.put(:zones, MapSet.to_list(state.visited_zones))
  end

  defp display_zone(zones, fallback) do
    cond do
      :work in zones -> :work
      :personal in zones -> :personal
      true -> fallback
    end
  end

  defp normalize_zones(zones) do
    zones
    |> Enum.flat_map(fn
      :work -> [:work]
      :personal -> [:personal]
      "work" -> [:work]
      "personal" -> [:personal]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp now, do: NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second)

  defp cfg(key), do: Keyword.fetch!(Application.fetch_env!(:pomodoro_tracker, :pomodoro), key)
end
