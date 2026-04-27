# Current Features

This file documents the product behavior confirmed from the codebase on
2026-04-27. It is intentionally about what the app does today, not what it was
supposed to do.

## Supported surfaces

- `/` is the main supported app surface.
- `/planner` is the supported planning surface.
- `/api/state` exposes a read-only JSON snapshot of timer + today + next due
  task.
- Hammerspoon / menubar / floating panel are intentionally disabled.
- `/` supports historical day navigation through `?date=YYYY-MM-DD`.
- There is now explicit product-level navigation between `Execute` and `Plan`.
- There is still no first-class navigation model yet for historical review,
  settings, habit tracking, or other future views.

## Core model

- The app has two zones: `work` and `personal`.
- Data lives in Markdown files inside two vaults, one per zone.
- Tasks are either:
  - `templates`: reusable definitions
  - `backlog`: concrete tasks that can be scheduled into today
- The current day plan lives in the personal vault and tracks:
  - `order`
  - `active`
  - `done`
  - `pomodoros`
  - `auto_injected`

## Current configuration model

- Operational settings currently come from environment variables, not from a
  vault file or in-app settings UI.
- This includes at least:
  - work start / stop hours
  - pomodoro work duration
  - short break duration
  - long break duration
- The top time-context bar is currently hard-coded to represent `07:00-20:00`.

## Main screen (`/`)

### Day navigation and readonly history

- The top header includes previous / next day navigation.
- `today` remains the fully interactive execution surface.
- Any non-today date renders in readonly historical mode.
- Historical mode:
  - hides the live timer controls
  - preserves the real task order / done state / pomodoro counts from that day
  - disables off-hours hiding heuristics so work tasks remain visible as they
    were
  - shows a visible readonly banner
- Historical pending tasks expose only:
  - `+ today` to carry the task into the current day without removing it from
    history
  - `cancel` to remove it from that historical day without deleting the task
    globally
- Empty historical days render `No hubo tareas en este día.`

### Time context and theming

- A top timeline shows the day from `07:00` to `20:00`.
- A second minimal bar below it summarizes timer intervals for the selected
  day.
- On weekdays it is split as:
  - personal `07:00-09:00`
  - work `09:00-18:00`
  - personal `18:00-20:00`
- On weekends the whole strip is personal.
- The summary bar uses:
  - red for `work`
  - blue for `personal`
  - split red/blue for mixed `work|personal`
  - blue for `active_break` only when a personal task was really selected
  - light gray for `passive_break`
  - dark gray for idle gaps
- Segment widths reflect real interval duration, not fixed pomodoro blocks.
- The page background follows the current situation:
  - work pomodoro in work zone: red
  - work pomodoro in personal zone: blue
  - any break: blue
  - idle: based on current work hours

### Top-bar badges

- `SL` and `GH` are backlog tag filters, not live integrations.
- `SL` filters `mensaje-slack`.
- `GH` filters `review`.
- Their badges show how many backlog tasks currently have those tags.

### Pomodoro timer

- Timer phases:
  - `idle`
  - `work`
  - `active_break`
  - `passive_break`
- Timer controls:
  - `Start work`
  - `Passive`
  - `Active break`
  - `Pause`
  - `Resume`
  - `Skip`
  - `Reset`
  - `-5` / `+5` minutes while running
- The timer is server-side, so it survives page reloads and syncs across
  clients while the app process keeps running.
- The four dots under the timer represent the current pomodoro cycle.
- `Start work` no longer requires an active task. A work interval can begin
  empty and gain task/zone attribution later.
- Near the timer, the UI shows live day totals for:
  - `work`
  - `personal`
- The `work` total turns warning-yellow once it crosses the current hard-coded
  threshold of `4h`.

### Task attribution during work pomodoros

- A work pomodoro can start:
  - with active tasks
  - with planned but inactive tasks
  - with no task selected at all
- Active-task changes during a running interval do not pause or reset the timer.
- The timer accumulates every task touched during the run.
- The timer also accumulates every zone touched during the run, so completed
  work intervals can classify as:
  - `work`
  - `personal`
  - mixed `work|personal`
- Active breaks also track whether a real personal task was selected during the
  interval.
- Session logs now persist:
  - started/ended timestamps
  - phase
  - tasks touched
  - zones touched

### "Trabajo actual" / current focus

- When there are active tasks and the app is not on break, the UI shows them in
  an `In progress` section.
- During breaks, the UI only shows personal tasks selected for that break in a
  `Doing this break` section.
- Each card can show:
  - zone
  - title
  - pomodoro count for today
  - related links
  - notes/body
- Actions on the card:
  - edit
  - pause/remove from active
  - finish

### Break task picker

- If the app is in a break phase and there is no personal break task selected,
  the UI shows a picker.
- `active_break` offers personal tasks without the `break` tag.
- `passive_break` offers personal tasks with the `break` tag.
- Break candidates can also be filtered by tag chips.
- Work-zone active tasks remain visible as `Up next` during a break.

### Empty states

- Idle with no active tasks and empty `Today`:
  - `No hay tareas hoy. Usa Plan para traer o crear tareas.`
- Idle with no active tasks but tasks already in `Today`:
  - `Elige algo para trabajar ↓`
- Active break with no break task selected:
  - `Elige una tarea para este break`
- Passive break with no break task selected:
  - `Elige algo para descansar`

### `Today`

- `Today` is collapsible.
- It shows separate progress counters for `work` and `personal`.
- Pending tasks can be:
  - reordered
  - activated
  - edited
  - removed from today
- Done tasks are shown separately with `undo`.
- Recurrent auto-injected items show a `🔁` marker.

### Off-hours behavior

- Outside work hours, pending work tasks are auto-hidden from `Today`.
- A banner lets the user temporarily show them again.

### Due-soon banner

- If any task in `Today` has `due_at` within the next 2 hours, a banner appears.
- The banner shows humanized urgency and lets the user move that task to the
  top of `Today`.

### `Tareas inconclusas`

- The app scans the last 7 days, excluding today.
- It shows tasks that were planned but not marked done.
- The list is deduped by task id, keeping the most recent unfinished date.
- Actions:
  - edit
  - add back to today
  - dismiss from the unfinished section without deleting the task itself

This is currently the closest thing to "recover work from previous days", but it
is now only a secondary helper because direct per-day historical review exists.

### Planning handoff

- The execution screen no longer renders the full backlog or archive sections.
- Instead it shows a planner handoff card linking to `/planner`.
- This keeps the main screen focused on execution rather than inventory
  management.
- When `Today` is empty on the live execution day, the empty state now points
  the user to `Plan`.

## Planning screen (`/planner`)

### Product navigation

- A minimal persistent nav now exists between:
  - `Execute`
  - `Plan`
- The current surface is visually highlighted.

### Templates

- Templates render correctly from real `:templates` data.
- Templates are grouped by pilar.
- A `Sin pilar` group exists so templates without a pilar do not disappear.
- Actions:
  - pause/reactivate template
  - edit
  - add to today

### `Backlog`

- Backlog now lives in `/planner`.
- Zone filter modes:
  - `auto`
  - `work`
  - `personal`
- `auto` follows work hours.
- Backlog candidates include both `backlog` items and `templates`.
- If a template has already been instantiated into a backlog task, the template
  is hidden to avoid duplicates.
- Dynamic tag chips are generated from the visible backlog candidates.
- Actions:
  - add to today
  - edit
  - create ad-hoc task
  - create template

### Archive

- Archive now lives in `/planner`.
- It remains lazy-loaded until the user opens it.
- It supports filtering by:
  - `unfinished` vs `finished`
  - `all`, `work`, `personal`
- Old unfinished items can be re-added to today from the archive.

This is still a task archive, not the primary date-by-date day review
experience.

## Recurrent tasks

- Recurrent behavior is driven by template frontmatter.
- Supported recurrence rules:
  - `daily`
  - `weekdays`
  - `weekly`
  - `weekly:mon,wed,fri`
- On first load each day, matching templates are auto-instantiated into backlog
  tasks for that date and injected into `Today`.
- The day file stores `cadence_ran_for` so the same day is not re-injected.
- There is no separate first-class habit model or habit-tracker view yet.

## Editing and task metadata

- New tasks can be created as `backlog` or `templates`.
- Personal templates can be flagged as break tasks, which adds the `break` tag.
- Existing tasks can store:
  - priority
  - tags
  - related links
  - body/notes
  - due date/time
  - recurrence
  - pilar / paused / streak fields
- Backlog tasks can be promoted into templates.
- Tags are currently flat strings.
- Tag editing is currently plain text, comma-separated input, not a structured
  picker.
- There is no first-class nested-tag semantics such as `ejercicio>cuello`.
- There is no tag registry, no tag suggestion UI, and no multi-select tag editor.

## Known caveats

- The timer supports switching tracked tasks mid-run, but the main LiveView does
  not fully use that capability yet.
- Work pomodoros currently store only one zone classification.
- `SL` / `GH` are labels and filters only; there is no live Slack or GitHub API
  integration in the app itself.
