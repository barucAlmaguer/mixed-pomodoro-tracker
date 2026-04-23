---
name: daily-task-sync
description: Scan Linear (issues assigned to me), Slack (unanswered threads/mentions), and GitHub (PRs assigned or requesting my review) and write new markdown tasks into the pomodoro-tracker backlog inside my Obsidian vaults. Idempotent — never duplicates existing tasks. Use when the user asks to "sync tasks", "check my backlog", "pull today's work", or on a schedule.
---

# daily-task-sync

Keep the pomodoro-tracker backlog in sync with Linear, Slack, and GitHub. The backlog lives inside my Obsidian vaults (one file per task, YAML frontmatter + markdown body) so Obsidian treats them as normal notes.

## Vault paths

- **Work** — `~/repos/valiot/valiot-knowledge/pomodoro-tracker/`
- **Personal** — `~/repos/personal/personal-knowledge/pomodoro-tracker/`

Each has these subdirs:

```
templates/   # reusable task DEFINITIONS (edited by the user, never by this skill)
backlog/     # discovered TASKS awaiting scheduling (this skill writes here)
days/        # YYYY-MM-DD.md — owned by the app, do not touch
sessions/    # append-only pomodoro log — do not touch
```

**Only write into `backlog/` of the WORK vault.**

- `templates/` is off-limits. Templates are user-curated definitions (e.g. "Review PRs asignados") that the user promotes manually from the UI. Never create or modify templates from this skill.
- `backlog/` is where real, actionable tasks live. Each item from Linear/Slack/GitHub becomes one `.md` file here.
- This skill does not scrape personal sources — only work (Linear/Slack/GitHub).

## What to sync

1. **Linear** — issues assigned to the current user (status != Done/Canceled), and issues where the user is subscribed and unread.
2. **Slack** — threads where the user is @mentioned and hasn't replied; unread DMs older than 30 min.
3. **GitHub** — PRs where the user is a reviewer (reviewDecision = REVIEW_REQUIRED), PRs assigned to the user, issues assigned to the user.

## Idempotency (critical)

Before creating a task file, check whether one already exists with the same `source_id`. Scan every `.md` in `backlog/` and `templates/` across BOTH vaults — a task may have been promoted to a template or moved by the user.

If it exists: skip silently. Never overwrite. Never "update". If the user moved the file, that's intentional.

Match key:
- Linear → `source: linear, source_id: <identifier>` (e.g. `VAL-1234`)
- GitHub → `source: github, source_id: <owner>/<repo>#<number>`
- Slack → `source: slack, source_id: <channel_id>/<thread_ts>`

## File naming

```
backlog/<source_id-slug>.md
```

Examples: `backlog/VAL-1234.md`, `backlog/valiot_repo_456.md`, `backlog/slack_C123_1714.md`

Keep the filename filesystem-safe: replace `/` `#` `:` with `_`.

## Frontmatter schema

```yaml
---
id: <same slug as filename, without .md>
title: <short, actionable>
zone: work
priority: high | med | low      # high for "review requested", else med
tags: [<source>, <optional: review|mensaje-slack>]
source: linear | github | slack
source_id: <see match key above>
related:
  - <primary URL — link back to the item>
created_at: <YYYY-MM-DD>
---

<body: any extra context, author, reviewers, thread preview, etc.>
```

**Do NOT set `from_template:`.** That field is reserved for tasks the user instantiates from a template in the UI — your scraped tasks are primary sources, not instances of a template.

**Special tags the UI depends on**:
- `mensaje-slack` — unanswered Slack messages (floats up in SL filter)
- `review` — GitHub PR reviews (floats up in GH filter)

## Priority heuristic

- GitHub PR review requested → `high`, tag `review`
- Linear issue in Urgent or High → `high`
- Slack mention → `med`, tag `mensaje-slack`
- Everything else → `med`

## Available MCP tools to use

Prefer MCP tools if present in the current Claude Code session:

- Linear: `list_issues` (filter by assignee=me, state != done/canceled)
- Slack: `slack_search_users` for my user id, then `slack_read_channel` / `slack_read_thread` for mentions
- GitHub: run `gh` CLI — `gh pr list --search "review-requested:@me"`, `gh issue list --assignee @me`

If a tool isn't available, fall back to the CLI (`gh`, `linear` API via curl) or skip that source and note it in the output.

## Execution flow

1. **Scan existing** — list every `.md` in `backlog/` + `templates/` across both vaults. Build a set of `source:source_id` pairs already tracked.
2. **Fetch sources** — query Linear, Slack, GitHub in parallel when possible.
3. **Filter out duplicates** — drop any item whose `source:source_id` is already tracked.
4. **Write new files** — one `.md` per new item into `~/repos/valiot/valiot-knowledge/pomodoro-tracker/backlog/`. Use the schema above.
5. **Report** — print a one-line summary per source: `linear: +3 / github: +1 / slack: +2` and list the filenames created.

Do not delete, rename, or modify existing files. Do not touch `days/` or `sessions/`.

## Example new file

```yaml
---
id: VAL-1234
title: Fix auth middleware session tokens
zone: work
priority: high
tags: [linear, compliance]
source: linear
source_id: VAL-1234
related:
  - https://linear.app/valiot/issue/VAL-1234
created_at: 2026-04-23
---

Assigned by: Juan
State: In Progress
Labels: backend, compliance
```

## When nothing is new

Print `nothing new — already in sync` and exit. Do not write empty files.

## When a source is unavailable

Print e.g. `slack: unavailable (no MCP, no cli)` and continue with the others. Do not fail the whole run.
