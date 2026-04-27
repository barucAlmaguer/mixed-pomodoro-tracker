# pomodoro-tracker agent notes

This file is the project-specific context for future agents working in this
repository. Keep it short, factual, and current.

## Product snapshot

- This is a Phoenix LiveView app for daily planning and pomodoro execution.
- The supported primary surface is `/` (`DayLive`).
- `Hammerspoon`, menubar, and floating-panel integration are intentionally
  disabled for now.
- `/planner` exists in the router, but should be treated as experimental until
  its current data-model mismatch is fixed.
- `/api/state` is a small read-only JSON snapshot for debugging or lightweight
  clients. It is not the main product surface.

## Source of truth

- There is no database.
- Tasks, plans, and session logs live as Markdown files with YAML frontmatter in
  two vaults: `work` and `personal`.
- Each vault contains `pomodoro-tracker/templates`, `backlog`, `days`, and
  `sessions`.
- The day plan (`days/YYYY-MM-DD.md`) and session log live in the personal
  vault and are the source of truth for "today".

## Current behavior that matters

- The app models two zones: `work` and `personal`.
- The top timeline and background theme switch between those zones based on time
  of day, unless an active timer phase overrides the styling.
- The top-left `SL` and `GH` badges are tag filters, not direct Slack or GitHub
  integrations. They filter backlog items tagged `mensaje-slack` and `review`.
- `Today` is an ordered day plan with `pending`, `active`, `done`, and
  `pomodoros` counts.
- Users can keep up to 2 tasks active at once.
- Breaks come in two explicit modes:
  - `active_break`: offers personal tasks without the `break` tag
  - `passive_break`: offers personal tasks with the `break` tag
- Recurring templates are auto-instantiated into today via `Cadence`.

## Timer semantics

- The timer is server-side in `PomodoroTracker.Timer` and syncs through PubSub.
- A work pomodoro is one run of the `:work` phase.
- The timer already supports the concept of switching tracked tasks mid-run via
  `Timer.switch_tasks/1` and keeps `visited_tasks` so one pomodoro can credit
  multiple tasks.
- Today, the main LiveView does not fully wire active-task changes to
  `Timer.switch_tasks/1`, so attribution can drift from what the UI shows.
- Today, a work pomodoro stores a single `zone` on the timer/session log, even
  though the UI can represent mixed active tasks.

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

- `/planner` currently filters for `:template`, but the vault layer emits
  `:templates`, so the page does not reflect real template data correctly.
- The session log is append-only plain text and currently stores only one zone
  per work pomodoro.
- There is test coverage for timer and cadence behavior, but not enough coverage
  for the full `/` workflow or `/planner`.

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
