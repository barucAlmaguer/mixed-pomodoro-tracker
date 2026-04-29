defmodule PomodoroTrackerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PomodoroTrackerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc """
  Minimal product navigation between the major app surfaces.
  """
  attr :current, :atom, required: true
  attr :id, :string, default: "product-nav"

  def product_nav(assigns) do
    ~H"""
    <nav
      id={@id}
      class="inline-flex items-center gap-1 rounded-full border border-white/10 bg-black/20 p-1"
    >
      <.link
        id={"#{@id}-execute"}
        navigate={~p"/"}
        class={[
          "px-3 py-1.5 rounded-full text-xs uppercase tracking-[0.2em] transition",
          if(@current == :execute,
            do: "bg-white text-slate-950",
            else: "text-white/70 hover:text-white hover:bg-white/10"
          )
        ]}
      >
        Execute
      </.link>
      <.link
        id={"#{@id}-plan"}
        navigate={~p"/planner"}
        class={[
          "px-3 py-1.5 rounded-full text-xs uppercase tracking-[0.2em] transition",
          if(@current == :plan,
            do: "bg-white text-slate-950",
            else: "text-white/70 hover:text-white hover:bg-white/10"
          )
        ]}
      >
        Plan
      </.link>
    </nav>
    """
  end

  @doc """
  Small LiveView-native tag picker with multi-select and quick-create support.
  """
  attr :selected, :list, default: []
  attr :suggestions, :list, default: []
  attr :query, :string, default: ""
  attr :input_name, :string, required: true
  attr :toggle_event, :string, required: true
  attr :add_event, :string, required: true
  attr :placeholder, :string, default: "add tag or parent>child"

  def tag_picker(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex gap-2">
        <input
          name={@input_name}
          value={@query}
          placeholder={@placeholder}
          autocomplete="off"
          class="flex-1 bg-white/10 rounded px-3 py-2 text-sm"
        />
        <button
          type="button"
          phx-click={@add_event}
          class="shrink-0 rounded bg-white/10 px-3 py-2 text-xs uppercase tracking-[0.18em] hover:bg-white/20"
        >
          Add
        </button>
      </div>

      <div :if={@selected != []} class="flex flex-wrap gap-1.5">
        <button
          :for={tag <- @selected}
          type="button"
          phx-click={@toggle_event}
          phx-value-tag={tag}
          class="rounded-full bg-white/15 px-2 py-1 text-xs text-white/90 hover:bg-white/25"
          title="Remove tag"
        >
          {tag} ×
        </button>
      </div>

      <div :if={@suggestions != []} class="flex flex-wrap gap-1.5">
        <button
          :for={tag <- @suggestions}
          type="button"
          phx-click={@toggle_event}
          phx-value-tag={tag}
          class={[
            "rounded-full px-2 py-1 text-xs transition",
            if(tag in @selected,
              do: "bg-white text-slate-950",
              else: "bg-white/5 text-white/70 hover:bg-white/10 hover:text-white"
            )
          ]}
        >
          {tag}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Recurrence editor for template forms. Shows only the controls that apply to
  the selected recurrence type.
  """
  attr :form, :map, required: true
  attr :toggle_event, :string, required: true

  def recurrence_editor(assigns) do
    ~H"""
    <div
      :if={@form.kind == :templates}
      class="space-y-2 rounded-lg border border-white/10 bg-white/5 p-3"
    >
      <div class="text-[11px] uppercase tracking-[0.18em] text-white/55">Recurrence</div>

      <select
        name="task[recurrence_type]"
        class="w-full rounded bg-white/10 px-2 py-2 text-sm"
      >
        <option value="none" selected={@form.recurrence_type == "none"}>Manual template</option>
        <option value="daily" selected={@form.recurrence_type == "daily"}>Daily</option>
        <option value="weekly" selected={@form.recurrence_type == "weekly"}>Weekly</option>
        <option value="interval" selected={@form.recurrence_type == "interval"}>Every X...</option>
      </select>

      <div :if={@form.recurrence_type == "daily"} class="text-xs text-white/60">
        Will appear every day.
      </div>

      <div :if={@form.recurrence_type == "weekly"} class="space-y-2">
        <div class="text-xs text-white/60">Weekdays</div>
        <div class="flex flex-wrap gap-1.5">
          <button
            :for={day <- 1..7}
            type="button"
            phx-click={@toggle_event}
            phx-value-day={day}
            class={[
              "rounded-full px-2 py-1 text-xs transition",
              if(day in (@form.recurrence_weekdays || []),
                do: "bg-white text-slate-950",
                else: "bg-white/5 text-white/70 hover:bg-white/10 hover:text-white"
              )
            ]}
          >
            {PomodoroTracker.Recurrence.weekday_short(day)}
          </button>
        </div>
      </div>

      <div :if={@form.recurrence_type == "interval"} class="space-y-2">
        <div class="grid grid-cols-[80px_1fr] gap-2">
          <input
            name="task[recurrence_every]"
            value={@form.recurrence_every}
            inputmode="numeric"
            class="rounded bg-white/10 px-2 py-2 text-sm"
          />
          <select
            name="task[recurrence_unit]"
            class="rounded bg-white/10 px-2 py-2 text-sm"
          >
            <option value="days" selected={@form.recurrence_unit == "days"}>days</option>
            <option value="months" selected={@form.recurrence_unit == "months"}>months</option>
            <option value="years" selected={@form.recurrence_unit == "years"}>years</option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-white/60">Anchor date</label>
          <input
            type="date"
            name="task[recurrence_anchor_date]"
            value={@form.recurrence_anchor_date}
            class="w-full rounded bg-white/10 px-2 py-2 text-sm"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs text-white/60">Anchor policy</label>
          <select
            name="task[recurrence_anchor_mode]"
            class="w-full rounded bg-white/10 px-2 py-2 text-sm"
          >
            <option value="calendar" selected={@form.recurrence_anchor_mode == "calendar"}>
              Fixed calendar
            </option>
            <option value="completion" selected={@form.recurrence_anchor_mode == "completion"}>
              Reset when done
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-white/60">Start popping early</label>
          <div class="grid grid-cols-[80px_1fr] gap-2">
            <input
              name="task[recurrence_lead_value]"
              value={@form.recurrence_lead_value}
              inputmode="numeric"
              class="rounded bg-white/10 px-2 py-2 text-sm"
            />
            <select
              name="task[recurrence_lead_unit]"
              class="rounded bg-white/10 px-2 py-2 text-sm"
            >
              <option value="days" selected={@form.recurrence_lead_unit == "days"}>
                days before
              </option>
              <option value="months" selected={@form.recurrence_lead_unit == "months"}>
                months before
              </option>
              <option value="years" selected={@form.recurrence_lead_unit == "years"}>
                years before
              </option>
            </select>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
