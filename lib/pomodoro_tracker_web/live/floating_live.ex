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

    socket =
      socket
      |> assign(:page_title, "Floating")
      |> assign(:now, NaiveDateTime.from_erl!(:calendar.local_time()))
      |> assign(:timer, Timer.state())
      |> assign(:break_tag_filter, nil)
      |> assign(:expanded, MapSet.new())
      |> load_vault()

    # Minimal HTML wrapper without manifest/service-worker for hs.webview compatibility
    {:ok, socket, layout: {__MODULE__, :floating_root}}
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

  def handle_event("timer:adjust", %{"delta" => delta}, socket) do
    Timer.adjust(String.to_integer(delta) * 1000)
    {:noreply, socket}
  end

  def handle_event("timer:break", %{"kind" => kind}, socket) do
    Timer.start_break(String.to_existing_atom(kind))
    {:noreply, socket}
  end

  def handle_event("filter:break_tag", %{"tag" => tag}, socket) do
    current = socket.assigns.break_tag_filter
    {:noreply, assign(socket, :break_tag_filter, if(current == tag, do: nil, else: tag))}
  end

  def handle_event("toggle:expand", %{"id" => id}, socket) do
    set = socket.assigns.expanded

    new =
      if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)

    {:noreply, assign(socket, :expanded, new)}
  end

  # Pick a break task: instantiate the template if needed, then add to active.
  def handle_event("break:pick", %{"id" => id}, socket) do
    tasks = socket.assigns.tasks

    resolved =
      case tasks[id] do
        %{kind: :templates} = tpl ->
          {:ok, new_id} = Vault.instantiate_template(tpl)
          new_id

        _ ->
          id
      end

    day = socket.assigns.day

    new_day =
      if resolved in day.active do
        day
      else
        order = if resolved in day.order, do: day.order, else: day.order ++ [resolved]
        %{day | active: day.active ++ [resolved], order: order}
      end

    Vault.save_day(new_day)
    Timer.switch_tasks(new_day.active)
    {:noreply, socket |> assign(:day, new_day) |> load_vault()}
  end

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

  # Switch the active task(s). Supports up to 2 simultaneous tasks.
  # If a pomodoro is running, the timer keeps going and all touched tasks get
  # credited at the end. If idle, just sets active without starting.
  # Toggle behavior: clicking an active task removes it; clicking inactive adds
  # it (up to 2 max).
  def handle_event("day:switch", %{"id" => id}, socket) do
    day = socket.assigns.day

    new_active =
      if id in day.active do
        List.delete(day.active, id)
      else
        # Keep max 2 active tasks (FIFO if exceeding)
        Enum.take(day.active ++ [id], 2)
      end

    new_day = %{day | active: new_active, order: ensure_in_order(day.order, id)}
    Vault.save_day(new_day)
    Timer.switch_tasks(new_active)
    {:noreply, socket |> assign(:day, new_day) |> load_vault()}
  end

  # Remove a task from active (used in In Progress section)
  def handle_event("day:deactivate", %{"id" => id}, socket) do
    day = socket.assigns.day
    new_active = List.delete(day.active, id)
    new_day = %{day | active: new_active}
    Vault.save_day(new_day)
    Timer.switch_tasks(new_active)
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

  defp active_tasks(day, tasks) do
    day.active
    |> Enum.flat_map(fn id ->
      case tasks[id] do
        nil -> []
        t -> [t]
      end
    end)
  end

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
  defdelegate break_phase?(phase), to: DayLive
  defdelegate now_ids(active, tasks, phase), to: DayLive
  defdelegate break_picker_tags(tasks, phase, exclude), to: DayLive
  defdelegate break_picker_tasks(tasks, phase, exclude, order, tag), to: DayLive
  defdelegate next_break_minutes(timer), to: DayLive

  defp link_target(s) when is_binary(s) do
    cond do
      String.starts_with?(s, "http://") or String.starts_with?(s, "https://") -> s
      true -> nil
    end
  end

  defp link_target(_), do: nil

  # Minimal root layout for floating panel - no manifest, no service worker
  # This prevents 404s and connection issues with hs.webview
  def floating_root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#0f172a" />
        <title>PomodoroTracker</title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
