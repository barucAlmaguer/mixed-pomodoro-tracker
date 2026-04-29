---
name: daily-task-sync
description: Write ad-hoc tasks to the pomodoro-tracker vaults. Creates .md files with proper YAML frontmatter in backlog/ or adds task IDs to days/. Can create personal or work tasks, and schedule them for today or leave in backlog.
---

# daily-task-sync

Write tasks to the pomodoro-tracker app by creating markdown files in the Obsidian vaults.

## Vault Paths (TWO VAULTS)

| Zone | Path | Purpose |
|------|------|---------|
| **Personal** | `~/repos/personal/personal-knowledge/pomodoro-tracker/` | Tareas personales, daily tracker, templates personales |
| **Work** | `~/repos/valiot/valiot-knowledge/pomodoro-tracker/` | Tareas de trabajo, templates de trabajo |

**IMPORTANT**: The app aggregates both vaults. The daily tracker (`days/`) solo existe en el vault personal.

## Where to write

### Task files (backlog/)
Create one `.md` file per task with full metadata:

```yaml
---
id: <unique-slug>
title: <task title>
zone: personal | work
priority: high | med | low
tags: [<tag1>, <tag2>]
created_at: YYYY-MM-DD
---

<body text (optional)>
```

| Zone | Directory |
|------|-----------|
| personal | `~/repos/personal/personal-knowledge/pomodoro-tracker/backlog/` |
| work | `~/repos/valiot/valiot-knowledge/pomodoro-tracker/backlog/` |

### Day files (days/) — SOLO PERSONAL
The day file only contains task IDs in `order:`:

```yaml
---
date: YYYY-MM-DD
order:
  - task-id-1
  - task-id-2
active: []
done: []
pomodoros: {}
---
```

**NEVER write task bodies in days/.** Only IDs that reference backlog/ files.

## How to create a task

### For "today" (ad-hoc):
1. Determine zone: personal or work
2. Create task file in appropriate `backlog/` with full metadata
3. Read existing `days/YYYY-MM-DD.md` (personal vault only)
4. Add the new task ID to `order:` array (preserve existing IDs)
5. Write back the day file

### For backlog only (not today):
1. Determine zone: personal or work
2. Create task file in appropriate `backlog/`
3. Done — user will schedule via /planner

## Critical rules

- **ALWAYS preserve existing content** when editing days/ files
- **NEVER overwrite** — append to `order:`, don't replace
- **Task IDs must match filename** (without .md)
- **Zone determines vault**: personal → personal vault, work → work vault
- **days/ only exists in personal vault** — work tasks scheduled for today still get their ID added to the personal days/ file
- **Work tasks** use tags like `[github, review]` or `[linear]` for filtering

## Example: Personal task for today

User: "Crea una tarea personal para hoy: tapar luz del clima"

Steps:
1. Create `~/repos/personal/personal-knowledge/pomodoro-tracker/backlog/tapar-luz-clima.md`:
   ```yaml
   ---
   id: tapar-luz-clima
   title: Tapar luz del clima
   zone: personal
   priority: med
   tags: []
   created_at: 2026-04-28
   ---
   ```
2. Read `~/repos/personal/personal-knowledge/pomodoro-tracker/days/2026-04-28.md`
3. Append `tapar-luz-clima` to `order:` (preserve existing IDs)
4. Write back day file

## Example: Work task for today

User: "Crea una tarea de trabajo para hoy: priorizar PRs anapau"

Steps:
1. Create `~/repos/valiot/valiot-knowledge/pomodoro-tracker/backlog/priorizar-prs-anapau.md`:
   ```yaml
   ---
   id: priorizar-prs-anapau
   title: Priorizar PRs anapau
   zone: work
   priority: high
   tags: [github, review]
   created_at: 2026-04-28
   ---
   ```
2. Read `~/repos/personal/personal-knowledge/pomodoro-tracker/days/2026-04-28.md`
3. Append `priorizar-prs-anapau` to `order:` (preserve existing IDs)
4. Write back day file

## How to schedule an existing backlog task for a specific day

User: "Agenda la tarea revisar-integracion-github para el jueves"

Steps:
1. Determine the date (e.g., 2026-05-01 for next Thursday)
2. Read `days/2026-05-01.md` — create if it doesn't exist with this template:
   ```yaml
   ---
   date: 2026-05-01
   order: []
   active: []
   done: []
   pomodoros: {}
   ---
   ```
3. Append the task ID (e.g., `revisar-integracion-github`) to `order:`
4. Write back the day file
5. **Do NOT modify the backlog file** — it stays where it is

**Important:** The task file remains in `backlog/` forever. The day file only references it by ID. This allows the same backlog task to be scheduled multiple times across different days.

## Future: GitHub/Linear/Slack integration

When syncing from external sources:
- GitHub PRs → work vault, tags: `[github, review]`
- Linear issues → work vault, tags: `[linear]`
- Slack mentions → work vault, tags: `[slack, mensaje-slack]`

Use `source:` and `source_id:` fields in frontmatter for idempotency.
