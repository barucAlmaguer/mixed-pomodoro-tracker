# pomodoro-tracker agent notes

This file is the project-specific context for future agents working in this
repository. Keep it short, factual, and current.

## Product snapshot

- This is a Phoenix LiveView app for daily planning and pomodoro execution.
- The supported primary surfaces are:
  - `/` (`DayLive`) for execution
  - `/planner` (`RecurrentPlannerLive`) for planning
- `Hammerspoon`, menubar, and floating-panel integration are intentionally
  disabled for now.
- `/api/state` is a small read-only JSON snapshot for debugging or lightweight
  clients. It is not the main product surface.

## Source of truth

- There is no database.
- Tasks, plans, and session logs live as Markdown files with YAML frontmatter in
  two vaults: `work` and `personal`.
- Each vault contains `pomodoro-tracker/templates`, `backlog`, `days`,
  `sessions`, and `settings`.
- The day plan (`days/YYYY-MM-DD.md`) and session log live in the personal
  vault and are the source of truth for "today".
- Tag registries live at `pomodoro-tracker/settings/tags.yaml` per vault.

## Current behavior that matters

- The app models two zones: `work` and `personal`.
- The product now has explicit top-level navigation between `Execute` and `Plan`.
- `/` also supports readonly historical review via `?date=YYYY-MM-DD`.
- The top timeline and background theme switch between those zones based on time
  of day, unless an active timer phase overrides the styling.
- A second minimal timeline bar summarizes today's logged/running intervals.
- The top-left `SL` and `GH` badges are tag filters, not direct Slack or GitHub
  integrations. They filter backlog items tagged `mensaje-slack` and `review`.
- `Today` is an ordered day plan with `pending`, `active`, `done`, and
  `pomodoros` counts.
- `/planner` now owns the full backlog / templates / archive surfaces.
- `/planner` is intentionally tag-driven, not pilar-driven.
- Templates and one-off tasks are shown together in one planning inventory, with
  explicit labels such as `template`, `instance`, and `one-off`.
- Tags now support parent-aware nested taxonomy such as `ejercicio>cuello`.
- Task edit/create flows use a structured tag picker, not raw comma text.
- Users can keep up to 2 tasks active at once.
- Breaks come in two explicit modes:
  - `active_break`: offers personal tasks without the `break` tag
  - `passive_break`: offers personal tasks with the `break` tag
- Recurring templates are auto-instantiated into today via `Cadence`.
- Supported recurrence families are now:
  - `daily`
  - `weekly` with explicit weekday selection
  - `interval` (`every X days|months|years`) with `calendar` or `completion`
    anchoring plus optional early-pop lead time
- Template instances must not carry recurrence metadata; recurrence belongs only
  to the template definition.

## Timer semantics

- The timer is server-side in `PomodoroTracker.Timer` and syncs through PubSub.
- A work pomodoro is one run of the `:work` phase.
- A work pomodoro can start without any active task and accumulate task/zone
  attribution later.
- The timer tracks `visited_tasks` and `visited_zones`, and `DayLive` now wires
  active-task changes into `Timer.switch_tasks/2`.
- Work intervals can now classify as `work`, `personal`, or mixed
  `work|personal`.
- `active_break` intervals only classify as personal when a real personal task
  was selected during that break.

## Product direction

- Prefer the simple, stable full app over clever integrations.
- Do not reintroduce Hammerspoon, floating views, PWA behavior, or other side
  surfaces unless the user explicitly asks for it.
- Treat "what does a pomodoro mean?" as a product decision, not just an
  implementation detail.
- The desired direction is to make pomodoro attribution explicit for:
  - the task ids touched during the run
  - whether the run counts as `work`, `personal`, or mixed `work|personal`

## Known gaps as of 2026-04-27

- The session log is still append-only plain text, but it now stores interval
  level timestamps, touched tasks, and touched zones.
- There is test coverage for timer/cadence, planner entry points, and basic
  historical day review plus pomodoro-attribution flows, but not enough
  coverage for the full `/` workflow or the deeper product semantics still
  planned on the roadmap.

## Working rules

- Before changing product semantics, update:
  - `README.md`
  - `docs/current-features.md`
  - `docs/roadmap.md`
- If you touch timer, day-planning, or recurrence behavior, run at least:
  - `mix test`
- If you touch the served app behavior, verify both:
  - `mix phx.server`
  - `./bin/serve`
- Prefer additive, explicit state over hidden coupling between LiveView state,
  timer state, and vault files.
