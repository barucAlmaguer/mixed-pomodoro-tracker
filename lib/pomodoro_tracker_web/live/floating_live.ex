defmodule PomodoroTrackerWeb.FloatingLive do
  @moduledoc """
  Compact, dense view for the always-on-top floating panel (Hammerspoon
  webview / Tauri window). Reuses Timer + Vault state but renders ~320×460px.
  """

  use PomodoroTrackerWeb, :live_view

  alias PomodoroTracker.{Cadence, Priority, Timer, Vault}
  alias PomodoroTrackerWeb.DayLive

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Timer.topic())
      Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Vault.Watcher.topic())
      :timer.send_interval(1000, self(), :tick_clock)
    end

    {:ok,
     socket
     |> assign(:page_title, "Floating")
     |> assign(:now, NaiveDateTime.from_erl!(:calendar.local_time()))
     |> assign(:timer, Timer.state())
     |> load_vault(), layout: false}
  end

  @impl true
  def handle_info({:timer, state}, socket), do: {:noreply, assign(socket, :timer, state)}
  def handle_info(:vault_changed, socket), do: {:noreply, load_vault(socket)}

  def handle_info(:tick_clock, socket) do
    {:noreply, assign(socket, :now, NaiveDateTime.from_erl!(:calendar.local_time()))}
  end

  @impl true
  def handle_event("timer:start_work", _, socket) do
    day = socket.assigns.day
    tasks = socket.assigns.tasks

    task_ids =
      case day.active do
        [] -> Enum.take(day.order, 1)
        active -> active
      end

    zone =
      case task_ids do
        [first | _] -> tasks[first].zone
        _ -> :personal
      end

    if task_ids != [], do: Timer.start_work(zone, task_ids)
    {:noreply, socket}
  end

  def handle_event("timer:pause", _, socket),
    do:
      (
        Timer.pause()
        {:noreply, socket}
      )

  def handle_event("timer:resume", _, socket),
    do:
      (
        Timer.resume()
        {:noreply, socket}
      )

  def handle_event("timer:skip", _, socket),
    do:
      (
        Timer.skip()
        {:noreply, socket}
      )

  def handle_event("day:finish", %{"id" => id}, socket) do
    day = socket.assigns.day

    new_day = %{
      day
      | active: List.delete(day.active, id),
        order: List.delete(day.order, id),
        done: day.done ++ [id]
    }

    Vault.save_day(new_day)
    {:noreply, socket |> assign(:day, new_day) |> load_vault()}
  end

  def handle_event("day:switch", %{"id" => id}, socket) do
    day = socket.assigns.day
    tasks = socket.assigns.tasks

    new_day = %{day | active: [id], order: ensure_in_order(day.order, id)}
    Vault.save_day(new_day)

    case tasks[id] do
      %{zone: zone} -> Timer.start_work(zone, [id])
      _ -> :ok
    end

    {:noreply, socket |> assign(:day, new_day) |> load_vault()}
  end

  defp ensure_in_order(order, id), do: if(id in order, do: order, else: order ++ [id])

  defp load_vault(socket) do
    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    {:ok, day} = Vault.load_day()
    day = Cadence.ensure_run!(day, tasks)
    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})

    socket
    |> assign(:tasks, tasks)
    |> assign(:day, day)
  end

  # ----- view helpers ----------------------------------------------------

  defp pending_today(day, tasks) do
    done_set = MapSet.new(day.done || [])

    day.order
    |> Enum.reject(&MapSet.member?(done_set, &1))
    |> Enum.flat_map(fn id ->
      case tasks[id] do
        nil -> []
        t -> [t]
      end
    end)
  end

  defp due_soon(day, tasks, now) do
    day.order
    |> Enum.flat_map(fn id ->
      case tasks[id] do
        nil -> []
        t -> [t]
      end
    end)
    |> Priority.due_soon(now)
  end

  defp progress_pct(%{remaining_ms: r, duration_ms: d}) when d > 0,
    do: max(0, min(100, round((d - r) / d * 100)))

  defp progress_pct(_), do: 0

  defp current_task(day, tasks) do
    case day.active do
      [id | _] ->
        tasks[id]

      _ ->
        case day.order do
          [id | _] -> tasks[id]
          _ -> nil
        end
    end
  end

  # Reuse formatting/labels already defined in DayLive so we don't fork.
  defdelegate fmt_time(ms), to: DayLive
  defdelegate phase_label(phase), to: DayLive
  defdelegate situation_bg(timer, now), to: DayLive
  defdelegate zone_card_class(zone), to: DayLive
end
