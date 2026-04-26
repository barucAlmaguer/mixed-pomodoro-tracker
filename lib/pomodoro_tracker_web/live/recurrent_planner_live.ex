defmodule PomodoroTrackerWeb.RecurrentPlannerLive do
  @moduledoc """
  Big-picture view of all recurring commitments organized by "Pilares de Vida".
  Shows habit stats and allows managing recurring task templates.
  """

  use PomodoroTrackerWeb, :live_view

  alias PomodoroTracker.{Vault}

  @pilares [
    %{id: :salud, label: "Salud", icon: "💪", color: "rose"},
    %{id: :sustento, label: "Sustento", icon: "💼", color: "blue"},
    %{id: :limites, label: "Límites de Trabajo", icon: "🛡️", color: "amber"},
    %{id: :hogar, label: "Tareas del Hogar", icon: "🏠", color: "emerald"},
    %{id: :pasatiempos, label: "Pasatiempos", icon: "🎸", color: "purple"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Recurrent Planner")
     |> assign(:pilares, @pilares)
     |> assign(:selected_pilar, nil)
     |> assign(:now, NaiveDateTime.from_erl!(:calendar.local_time()))
     |> load_templates(), layout: {PomodoroTrackerWeb.Layouts, :app}}
  end

  @impl true
  def handle_info(:vault_changed, socket), do: {:noreply, load_templates(socket)}

  def handle_info(:tick_clock, socket) do
    {:noreply, assign(socket, :now, NaiveDateTime.from_erl!(:calendar.local_time()))}
  end

  @impl true
  def handle_event("select:pilar", %{"id" => id}, socket) do
    current = socket.assigns.selected_pilar
    new_id = if current == id, do: nil, else: String.to_existing_atom(id)
    {:noreply, assign(socket, :selected_pilar, new_id)}
  end

  def handle_event("toggle:template", %{"id" => id}, socket) do
    tasks = socket.assigns.templates
    task = tasks[id]

    new_task =
      if task do
        updated = %{task | paused: !task.paused}
        Vault.save_task(updated)
        updated
      else
        task
      end

    new_tasks = Map.put(tasks, id, new_task)
    {:noreply, assign(socket, :templates, new_tasks)}
  end

  defp load_templates(socket) do
    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})

    templates =
      tasks
      |> Enum.filter(fn {_id, t} -> t.kind == :template end)
      |> Enum.map(fn {_id, t} -> t end)

    socket
    |> assign(:tasks, tasks)
    |> assign(:templates, tasks)
    |> assign(:templates_by_pilar, group_by_pilar(templates))
  end

  defp group_by_pilar(templates) do
    templates
    |> Enum.group_by(fn t -> t.pilar || :sin_pilar end)
    |> Map.put_new(:salud, [])
    |> Map.put_new(:sustento, [])
    |> Map.put_new(:limites, [])
    |> Map.put_new(:hogar, [])
    |> Map.put_new(:pasatiempos, [])
    |> Map.put_new(:sin_pilar, [])
  end

  # View helpers
  def recurrence_label(nil), do: nil
  def recurrence_label("daily"), do: "Cada día"
  def recurrence_label("weekdays"), do: "Lunes a viernes"
  def recurrence_label("weekly:" <> days), do: "Semanal (#{days})"
  def recurrence_label(r), do: r

  def pilar_class(color) do
    case color do
      "rose" -> "bg-rose-500/10 border-rose-500/30 text-rose-200"
      "blue" -> "bg-blue-500/10 border-blue-500/30 text-blue-200"
      "amber" -> "bg-amber-500/10 border-amber-500/30 text-amber-200"
      "emerald" -> "bg-emerald-500/10 border-emerald-500/30 text-emerald-200"
      "purple" -> "bg-purple-500/10 border-purple-500/30 text-purple-200"
      _ -> "bg-white/5 border-white/10 text-white/70"
    end
  end

  def pilar_bg(color) do
    case color do
      "rose" -> "from-rose-500/20 to-rose-600/5"
      "blue" -> "from-blue-500/20 to-blue-600/5"
      "amber" -> "from-amber-500/20 to-amber-600/5"
      "emerald" -> "from-emerald-500/20 to-emerald-600/5"
      "purple" -> "from-purple-500/20 to-purple-600/5"
      _ -> "from-white/10 to-white/5"
    end
  end

  def last_done_ago(task, _tasks) do
    case task.last_completed_at do
      nil ->
        "Nunca"

      dt ->
        days = Date.diff(Date.utc_today(), Date.from_iso8601!(String.slice(dt, 0, 10)))

        cond do
          days == 0 -> "Hoy"
          days == 1 -> "Ayer"
          days < 7 -> "#{days} días"
          true -> "#{div(days, 7)} sem"
        end
    end
  end

  def weekly_status(_task, _tasks) do
    # Returns emoji dots for last 7 days: ✅ done, ⏸️ paused/skip, ○ pending
    # Simplified - would need actual history data
    "○○○○○○○"
  end

  def streak_count(task) do
    # Simplified streak calculation
    task.streak || 0
  end
end
