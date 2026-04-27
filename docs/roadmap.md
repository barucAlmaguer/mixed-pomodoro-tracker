# Roadmap

This file captures the intended product direction after simplifying the app back
to a stable Phoenix LiveView core.

## Principles

- Favor one reliable full app over multiple fragile surfaces.
- Keep product semantics explicit.
- Do not add integration complexity until the daily workflow is solid.
- Prefer simple, testable state transitions over clever coupling.
- Separate execution concerns from planning concerns when that reduces cognitive
  load.

## Current focus

### 1. Stabilize the core app

- Keep `/` as the primary supported surface.
- Keep Hammerspoon / menubar / floating-panel integration disabled until the
  core workflow is boringly reliable.
- Maintain parity between:
  - `mix phx.server`
  - `./bin/serve`

### 2. Make pomodoro attribution correct

Current baseline:

- A work pomodoro is still one uninterrupted run of the work timer.
- Changing the active task during that run no longer pauses or resets it.
- A work pomodoro can start with no active task and accumulate attribution
  later.
- `DayLive` now wires task changes into `Timer.switch_tasks/2`.
- Completed work intervals now persist:
  - all touched task ids
  - all touched zones
- Work intervals can classify as:
  - `work`
  - `personal`
  - `work|personal`

Remaining refinement:

- Decide long-term reporting semantics for mixed intervals:
  - inclusive counts by zone
  - a distinct mixed bucket
  - both
- Decide whether the displayed in-progress work theme should eventually gain a
  dedicated mixed visual instead of collapsing to work-first red.

### 3. Add a minimal day summary bar under the timer

Current baseline:

- A second horizontal bar now renders directly below the top time-context bar.
- It summarizes the selected day as chronological contiguous fragments.
- Width reflects real interval duration.
- It renders:
  - red for `work`
  - blue for `personal`
  - split red/blue for mixed `work|personal`
  - blue for `active_break` only when a personal task really happened
  - light gray for `passive_break`
  - dark gray for idle gaps
- It includes the currently running interval on `today`.

Remaining refinement:

- Decide whether the represented day span should remain fixed at `07:00-20:00`
  or move under settings control.
- Decide whether active breaks without selected tasks should keep rendering as a
  neutral/dark segment or use another treatment.
- Decide whether mixed fragments should stay hard 50/50 or eventually become
  proportional if richer data exists later.

### 4. Add a global operating mode switch

Desired behavior:

- Introduce a global mode switch for the whole app:
  - `auto`
  - `work`
  - `personal`
- This is distinct from the current backlog zone filter. It is a product-level
  mode, not a local list filter.
- The control should be highly visible and minimal, likely centered near the top
  of the screen around the timer area.

Meaning of each mode:

- `auto`: derive the current mode from configured work hours, as the app does
  today.
- `work`: force the app into explicit work mode even outside normal work hours.
- `personal`: force the app into explicit personal mode even during work hours.

Why this exists:

- The app needs to support intentional "trabajar a des-horas" without making the
  user fight the default work-hours heuristics.
- The product should distinguish between:
  - the clock saying it is off-hours
  - the user explicitly choosing to be in work mode anyway

UI/behavior implications:

- The global mode should become the main source of truth for context-sensitive
  behavior that is currently driven only by wall-clock heuristics.
- At minimum it should influence:
  - app theming/background when idle
  - default zone assumptions when starting work without a clear active-task zone
  - whether work tasks are hidden from `Today`
  - backlog `auto` behavior
- The app should still preserve the notion of actual work hours for reference,
  but user intent should be able to override it cleanly.

Open implementation questions:

- Should the top time-context bar continue to show clock-based work/personal
  slices even when the global mode is overridden?
- Should the UI show both:
  - current manual mode
  - whether the clock is inside or outside configured work hours
- Decide whether the global mode is:
  - ephemeral per browser session
  - persisted in the day file
  - persisted as a user-level/global setting

### 5. Track daily work vs personal time totals

Current baseline:

- The execution header now shows minimal `work` and `personal` totals.
- Totals are derived from the same interval ledger used by the summary bar.
- `work` totals include any interval whose classification includes `work`.
- `personal` totals include any interval whose classification includes
  `personal`.
- `active_break` contributes to `personal` only when a real personal task was
  selected.
- `passive_break` contributes to neither total.
- The current hard-coded warning threshold is `4h`, and `work` turns warning
  yellow after that.

Remaining refinement:

- Move the `4h` threshold into real global settings instead of keeping it
  hard-coded.
- Decide whether the UI needs copy that explicitly explains inclusive mixed
  intervals.
- Decide whether future reporting should expose a separate mixed bucket in
  addition to the current inclusive totals.

### 6. Move product settings into a first-class global settings model

Desired behavior:

- Introduce a coherent global settings section for product behavior that is
  currently split between hard-coded values and environment variables.
- The settings should be editable from the UI.
- The settings should also live in a human-editable file inside the
  `pomodoro-tracker` vault area, using YAML.

Candidate storage model:

- A single settings file as source of truth, likely in the personal vault, for
  example:
  - `pomodoro-tracker/settings.yaml`
- The UI should edit that file rather than maintaining a separate hidden store.
- Manual edits to the file should be respected and picked up by the app.

Settings that should move into this model:

- work start hour
- work stop hour
- visible time range for the top timer-context bar
- daily work-time threshold for alerts
- default pomodoro work duration
- default short break duration
- default long break duration

Why this matters:

- These settings are product behavior, not deployment secrets.
- They should be part of the user's working system and portable with the vault.
- They should be editable without touching shell env vars or restart scripts.

UI direction:

- A global settings section should expose the key controls in a simple form.
- The YAML file remains the canonical persisted representation.
- The UI should be a convenience editor, not a separate competing source of
  truth.

Open design questions:

- Should the settings file live only in the personal vault, or be mirrored
  elsewhere?
- Should changes apply live, or require a lightweight refresh?
- Which settings remain environment-level only:
  - vault paths
  - server port
  - host / deployment values
- Decide whether the top time-context bar range is:
  - fully user-configurable
  - derived from work hours with configurable padding
  - configurable with sensible defaults

Implementation direction:

- Keep infrastructure/deployment values in env vars.
- Move user-facing behavioral configuration into YAML.
- Ensure the vault watcher also reloads settings changes, not only task/day
  files.

### 7. Unify templates, recurring tasks, and habits under one model

Desired model:

- A `template` is the reusable task definition.
- `recurrence` is optional schedule configuration attached to a template.
- `habit` is optional tracking configuration attached to a template.
- A concrete day task is an instance materialized from that template.

This means:

- template without recurrence: reusable manual template
- template with recurrence: scheduled/recurrent template
- template with `habit: true`: participates in habit tracking
- one template may be both scheduled and habit-tracked

Why this is the right direction:

- It avoids inventing separate entities for concepts that are mostly facets of
  the same reusable task definition.
- It keeps the data model composable:
  - reusable
  - schedulable
  - habit-trackable
- It stays close to the current architecture, which already has templates plus
  recurrence-driven instantiation.

UI implications:

- `Plan` should present templates with clear labels such as:
  - manual
  - scheduled
  - habit
  - combinations of the above
- Users should not have to reason about three disconnected object types when
  they are really configuring one reusable task definition.

Open design questions:

- Define what `habit: true` means operationally:
  - simply include this template in habit views
  - also enforce some completion expectation
  - also enable richer streak logic
- Decide whether habit configuration needs extra fields beyond a boolean:
  - target cadence
  - success criteria
  - pause state

### 8. Add nested tags as a first-class taxonomy

Desired behavior:

- Treat tags as structured hierarchical labels, not only flat strings.
- Support nested forms such as:
  - `ejercicio>cuello`
  - `ejercicio>ojos`
  - `perritos>vet`
  - `comida>preparacion`
  - `piano>digitacion`

Why this matters:

- Tags should support both planning and reporting.
- Hierarchical tags allow the user to inspect work at different levels:
  - `ejercicio`
  - `ejercicio>cuello`
  - `ejercicio>ojos`
- The same system should support:
  - planning filters
  - break-task suggestions
  - habit grouping
  - later analytics/reporting

Semantic expectations:

- Filtering by a parent tag such as `ejercicio` should be able to include tasks
  tagged with `ejercicio>cuello` and `ejercicio>ojos`.
- Filtering by a leaf such as `cuello` should be possible when explicitly
  requested, but the canonical identity should remain the full hierarchical tag.
- A task may carry multiple hierarchical tags.

Implementation direction:

- Preserve a canonical tag string representation in storage.
- Add parsing/helpers so the UI and filtering logic understand parent/child
  relationships.
- Avoid overengineering a separate taxonomy database; the vault-backed model can
  still work if the tag semantics are explicit.

### 9. Add a real tag picker/editor UX

Desired behavior:

- Replace the current plain text tag input with a structured multi-select tag
  picker.
- The picker should:
  - show existing tags
  - allow selecting multiple tags
  - allow creating new tags
  - support hierarchical tags cleanly

Why this matters:

- If tags become important for planning, break suggestions, and habit tracking,
  then raw comma-separated text input becomes too fragile.
- Good tag UX is now product-critical, not a minor convenience.

Planner/break implications:

- `Plan` should support efficient filtering by tag families such as:
  - `perritos`
  - `ejercicio`
  - `comida>preparacion`
- Active and passive break suggestions should also benefit from the same tag
  semantics and picker model.

Open design questions:

- Should the picker expose the hierarchy as:
  - searchable chips
  - nested grouped menu
  - autocomplete with path-like entries
- Decide whether new tags are free-form or normalized on creation.
- Decide whether aliases or display labels are needed later.

### 10. Add a habit tracker view built from templates and tags

Desired behavior:

- Add a dedicated `Habit Tracker` view for templates marked as habits.
- The view should not hardcode specific habits like "hacer ejercicio".
- Instead, it should derive useful groupings from the templates' tags.

Examples of desired drill-down:

- `ejercicios de cuello`
- `ejercicios de vista/ojos`
- `ejercicios de tren superior`
- `ejercicio` in general
- `ejercicio>cuello | ejercicio>ojos` style combined views

Grouping model:

- Habit views should be aggregatable by tag scope.
- A user should be able to inspect:
  - one specific habit template
  - one tag branch such as `ejercicio`
  - a subset such as `ejercicio>cuello`
  - combinations of related tags

Implementation direction:

- Build the habit tracker on top of:
  - templates marked as `habit: true`
  - recurrence/schedule metadata when relevant
  - hierarchical tag grouping
  - actual completion/history data from day instances and interval/session logs

Open design questions:

- Define whether habit success is measured by:
  - task completed on scheduled day
  - any effort logged
  - pomodoro time
  - a custom completion rule
- Decide whether the habit tracker is:
  - its own route
  - a subsection of `Plan`
  - both summary and detailed views

### 11. Add day navigation with readonly historical review

Current baseline:

- `/` now supports previous/next day navigation.
- `today` stays fully interactive.
- Non-today dates render in readonly mode.
- Historical days hide the live timer controls.
- Historical pending tasks support:
  - bring task to today
  - cancel task in that historical day
- Bringing a task forward preserves the task's historical existence on the
  original day.

Remaining refinement:

- Decide whether future dates should remain reachable as empty readonly states
  or be bounded differently.
- Decide whether historical days should eventually show a static interval
  summary instead of simply hiding the timer surface.
- Decide whether carried tasks should be annotated in today's UI with their
  source date.
- Decide whether canceling a historical task should also clear related recovery
  hints such as `tareas inconclusas`.
- Add richer browser-level coverage for history navigation once the next
  product slices settle.

### 12. Deepen the Execute vs Plan split

Current baseline:

- `/` is now the execution surface.
- `/planner` now owns backlog, templates, and archive.
- A minimal `Execute/Plan` navigation already exists.

Remaining product work:

- keep `Execute` focused on:
  - timer
  - day summary
  - active work
  - today's ordered plan
  - limited recovery actions
- keep `Plan` focused on:
  - templates
  - backlog
  - archive
  - later: historical review, settings, habits
- avoid reintroducing full planning/inventory surfaces back into `Execute`

### 13. Extend navigation beyond Execute and Plan

Current baseline:

- The app already supports fast switching between `Execute` and `Plan`.

Remaining behavior:

- Extend navigation to future views such as:
  - `Settings`
  - `Habit Tracker`
  - possibly historical review if it becomes its own surface
- Decide final navigation treatment across desktop/mobile.
- Decide whether `Settings` is a route, modal, panel, or planner subsection.

### 14. Grow `/planner` into the long-term planning hub

Current baseline:

- `/planner` is now a supported planning surface.

Remaining work:

- add global settings editing
- add habit management/tracking entry points
- decide how planner should link into or summarize historical review
- improve planner-specific data modeling and tests as those surfaces expand

### 15. Strengthen tests around product behavior

Add coverage for:

- day-plan interactions from `DayLive`
- active-task switching during a running pomodoro
- mixed-zone work pomodoros
- off-hours hiding / showing of work tasks
- hierarchical tag filtering behavior
- habit-template grouping and aggregation rules
- richer historical-day behavior beyond the new readonly baseline
- navigation to future views beyond execute/plan
- richer `/planner` behavior as it grows beyond templates/backlog/archive

## Next improvements after the core is stable

- Richer reports from the session log:
  - per-day work vs personal time
  - mixed-zone pomodoros
  - task-level effort summaries
- Make due-date and lead-time behavior more explicit in the UI.
- Clarify and possibly simplify the recurrent-task model.

## Explicit non-goals for now

- Reintroducing Hammerspoon or floating panels
- Adding more client surfaces before the main app is stable
- Hiding product decisions inside implementation quirks
