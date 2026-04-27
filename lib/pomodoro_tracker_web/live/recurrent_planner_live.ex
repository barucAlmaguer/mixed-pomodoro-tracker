defmodule PomodoroTrackerWeb.RecurrentPlannerLive do
  @moduledoc """
  Planning surface for templates, backlog, and archived tasks.
  """

  use PomodoroTrackerWeb, :live_view

  alias PomodoroTracker.{Cadence, Vault}
  alias PomodoroTrackerWeb.DayLive, as: ExecuteLive

  @pilares [
    %{id: :salud, label: "Salud", icon: "💪", color: "rose"},
    %{id: :sustento, label: "Sustento", icon: "💼", color: "blue"},
    %{id: :limites, label: "Límites de Trabajo", icon: "🛡️", color: "amber"},
    %{id: :hogar, label: "Tareas del Hogar", icon: "🏠", color: "emerald"},
    %{id: :pasatiempos, label: "Pasatiempos", icon: "🎸", color: "purple"},
    %{id: :sin_pilar, label: "Sin pilar", icon: "•", color: "slate"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PomodoroTracker.PubSub, Vault.Watcher.topic())
      :timer.send_interval(1000, self(), :tick_clock)
    end

    {:ok,
     socket
     |> assign(:page_title, "Plan")
     |> assign(:pilares, @pilares)
     |> assign(:selected_pilar, nil)
     |> assign(:zone_filter, :auto)
     |> assign(:tag_filter, MapSet.new())
     |> assign(:archive_visible, false)
     |> assign(:archive, nil)
     |> assign(:archive_state_filter, :unfinished)
     |> assign(:archive_zone_filter, :all)
     |> assign(:new_task_form, nil)
     |> assign(:edit_form, nil)
     |> assign(:now, NaiveDateTime.from_erl!(:calendar.local_time()))
     |> load_data()}
  end

  @impl true
  def handle_info(:vault_changed, socket), do: {:noreply, load_data(socket)}

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

    {:noreply,
     socket
     |> assign(:templates, new_tasks)
     |> assign(:templates_by_pilar, group_by_pilar(Map.values(new_tasks)))}
  end

  def handle_event("filter:zone", %{"zone" => zone}, socket) do
    {:noreply, assign(socket, :zone_filter, String.to_existing_atom(zone))}
  end

  def handle_event("filter:tag", %{"tag" => tag}, socket) do
    current = socket.assigns.tag_filter

    new =
      if MapSet.member?(current, tag),
        do: MapSet.delete(current, tag),
        else: MapSet.put(current, tag)

    {:noreply, assign(socket, :tag_filter, new)}
  end

  def handle_event("filter:clear_tags", _, socket) do
    {:noreply, assign(socket, :tag_filter, MapSet.new())}
  end

  def handle_event("archive:show", _, socket) do
    {:noreply,
     socket
     |> assign(:archive_visible, true)
     |> assign(:archive, load_archive())}
  end

  def handle_event("archive:hide", _, socket) do
    {:noreply, socket |> assign(:archive_visible, false) |> assign(:archive, nil)}
  end

  def handle_event("archive:state_filter", %{"state" => s}, socket) do
    {:noreply, assign(socket, :archive_state_filter, String.to_existing_atom(s))}
  end

  def handle_event("archive:zone_filter", %{"zone" => z}, socket) do
    {:noreply, assign(socket, :archive_zone_filter, String.to_existing_atom(z))}
  end

  def handle_event("day:add", %{"id" => id}, socket) do
    case socket.assigns.tasks[id] do
      %{kind: :templates} = tpl ->
        {:ok, new_id} = Vault.instantiate_template(tpl)
        day = socket.assigns.day

        new_day =
          if new_id in day.order or new_id in day.done,
            do: day,
            else: %{day | order: day.order ++ [new_id]}

        Vault.save_day(new_day)
        {:noreply, socket |> assign(:day, new_day) |> load_data()}

      _ ->
        update_day(socket, fn day ->
          if id in day.order or id in day.done,
            do: day,
            else: %{day | order: day.order ++ [id]}
        end)
    end
  end

  def handle_event("new:open", %{"kind" => kind, "zone" => zone}, socket) do
    {:noreply,
     assign(socket, :new_task_form, %{
       kind: String.to_existing_atom(kind),
       zone: String.to_existing_atom(zone),
       title: "",
       priority: "med",
       tags: "",
       is_break: false,
       add_to_today: false
     })}
  end

  def handle_event("new:close", _, socket), do: {:noreply, assign(socket, :new_task_form, nil)}

  def handle_event("new:change", %{"task" => p}, socket) do
    form = socket.assigns.new_task_form

    form = %{
      form
      | title: p["title"] || "",
        priority: p["priority"] || "med",
        tags: p["tags"] || "",
        is_break: p["is_break"] == "true",
        add_to_today: p["add_to_today"] == "true"
    }

    {:noreply, assign(socket, :new_task_form, form)}
  end

  def handle_event("new:submit", _params, socket) do
    form = socket.assigns.new_task_form
    title = String.trim(form.title)

    if title == "" do
      {:noreply, put_flash(socket, :error, "Title required")}
    else
      id = slugify(title)
      tags = parse_tags(form.tags, form.is_break)

      attrs = %{
        id: id,
        title: title,
        zone: form.zone,
        priority: form.priority,
        tags: tags,
        created_at: Date.utc_today() |> Date.to_iso8601()
      }

      case Vault.create_task(form.zone, form.kind, attrs) do
        {:ok, _path} ->
          socket =
            if form.add_to_today do
              day = socket.assigns.day
              Vault.save_day(%{day | order: day.order ++ [id]})
              socket
            else
              socket
            end

          {:noreply, socket |> assign(:new_task_form, nil) |> load_data()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not create: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("edit:open", %{"id" => id}, socket) do
    t = socket.assigns.tasks[id]

    if t do
      form = %{
        id: id,
        path: t.path,
        kind: t.kind,
        from_template: t.from_template,
        title: t.title,
        priority: t.priority || "med",
        tags: Enum.join(t.tags || [], ", "),
        related: Enum.join(t.related || [], "\n"),
        body: t.body || "",
        is_break: "break" in (t.tags || [])
      }

      {:noreply, assign(socket, :edit_form, form)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit:close", _, socket), do: {:noreply, assign(socket, :edit_form, nil)}

  def handle_event("edit:change", %{"task" => p}, socket) do
    f = socket.assigns.edit_form

    f = %{
      f
      | title: p["title"] || "",
        priority: p["priority"] || "med",
        tags: p["tags"] || "",
        related: p["related"] || "",
        body: p["body"] || "",
        is_break: p["is_break"] == "true"
    }

    {:noreply, assign(socket, :edit_form, f)}
  end

  def handle_event("edit:submit", _params, socket) do
    f = socket.assigns.edit_form

    attrs = %{
      title: f.title,
      priority: f.priority,
      tags: parse_tags(f.tags, f.is_break),
      related: parse_lines(f.related),
      body: f.body
    }

    case Vault.update_task(f.path, attrs) do
      :ok ->
        {:noreply, socket |> assign(:edit_form, nil) |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Update failed: #{inspect(reason)}")}
    end
  end

  def handle_event("edit:delete", _, socket) do
    f = socket.assigns.edit_form

    if f do
      Vault.delete_task(f.path)

      day = socket.assigns.day

      new_day = %{
        day
        | order: List.delete(day.order, f.id),
          active: List.delete(day.active, f.id),
          done: List.delete(day.done, f.id)
      }

      if new_day != day, do: Vault.save_day(new_day)

      {:noreply,
       socket
       |> assign(:edit_form, nil)
       |> assign(:day, new_day)
       |> load_data()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit:promote", _, socket) do
    f = socket.assigns.edit_form
    task = socket.assigns.tasks[f.id]

    case task && Vault.promote_to_template(task) do
      {:ok, _path} ->
        {:noreply,
         socket
         |> put_flash(:info, "Promoted #{task.title} to template")
         |> load_data()}

      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "Template with this id already exists")}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_data(socket) do
    tasks = Vault.list_all_tasks() |> Map.new(&{&1.id, &1})
    {:ok, day} = Vault.load_day()
    day = Cadence.ensure_run!(day, tasks)

    templates =
      tasks
      |> Enum.filter(fn {_id, t} -> t.kind == :templates end)
      |> Enum.map(fn {_id, t} -> t end)

    template_map = Map.new(templates, &{&1.id, &1})

    socket
    |> assign(:day, day)
    |> assign(:tasks, tasks)
    |> assign(:templates, template_map)
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

  defp update_day(socket, fun) do
    new_day = fun.(socket.assigns.day)
    Vault.save_day(new_day)
    {:noreply, assign(socket, :day, new_day)}
  end

  defp parse_tags(str, is_break?) do
    base = parse_lines(str, ",")

    cond do
      is_break? and "break" not in base -> base ++ ["break"]
      not is_break? -> Enum.reject(base, &(&1 == "break"))
      true -> base
    end
  end

  defp parse_lines(str, sep \\ "\n")
  defp parse_lines(nil, _sep), do: []
  defp parse_lines("", _sep), do: []

  defp parse_lines(str, sep) when is_binary(str) do
    str |> String.split(sep) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 60)
  end

  defdelegate zone_card_class(zone), to: ExecuteLive
  defdelegate backlog_zone(now, zone_filter), to: ExecuteLive
  defdelegate backlog_tags(tasks, zone, exclude_ids), to: ExecuteLive
  defdelegate filtered_backlog(tasks, zone, tag_filter, exclude_ids), to: ExecuteLive
  defdelegate load_archive(), to: ExecuteLive
  defdelegate archive_entries(archive, state_filter, zone_filter), to: ExecuteLive

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
