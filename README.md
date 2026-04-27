# pomodoro-tracker

Focus on **today**. Plan → execute with Phoenix LiveView, pomodoro timer, and Obsidian-backed task files.

Hammerspoon / menubar / floating-panel integration is currently disabled. The supported surface is the full Phoenix LiveView app only.

- Work zone (red) and personal zone (blue) auto-switch by time of day
- Mobile-first narrow UI — put it in a sidebar or open from your phone on LAN
- Tasks live as `.md` files with YAML frontmatter inside your existing Obsidian vaults
- Slack/GitHub filter badges in the top bar (tag filters, not live integrations)
- 1 or 2 active tasks at a time
- Pomodoro usage auto-logged per task for traceability

## Product docs

- Current behavior: [`docs/current-features.md`](docs/current-features.md)
- Planned changes: [`docs/roadmap.md`](docs/roadmap.md)
- Repo-specific agent context: [`AGENTS.md`](AGENTS.md)

## Layout inside each vault

```
{VAULT}/pomodoro-tracker/
├── templates/    # reusable task definitions
├── backlog/      # discovered tasks not yet scheduled
├── days/         # YYYY-MM-DD.md — today's ordered plan + pomodoro counts
└── sessions/     # append-only pomodoro log
```

Day plans and session logs live in the **personal vault** (single source of truth for "today"). Templates and backlog split across both vaults by zone.

## Setup

```bash
mix setup                    # deps + assets
mix phx.server               # dev mode — http://localhost:4000
```

## Production mode (leave it running)

For a background tab on your machine:

```bash
./bin/serve                  # http://<your-ip>:4123, MIX_ENV=prod
```

The script:
- generates + persists `SECRET_KEY_BASE` in `.env` on first run (gitignored)
- loads any other env vars from `.env` (e.g. `PORT=4123`, `PHX_HOST=...`, vault paths)
- digests assets, then boots Phoenix with `MIX_ENV=prod`
- binds to `0.0.0.0` so any device on your LAN can open `http://<your-ip>:4123`

To change the port, add `PORT=4555` (or whatever) to `.env`. To run on boot, wrap it in launchd / a tmux session / a terminal tab — whatever fits your habit.

## Environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `WORK_VAULT_PATH` | `./vaults/work` | Work Obsidian vault (point at your actual vault) |
| `PERSONAL_VAULT_PATH` | `./vaults/personal` | Personal Obsidian vault |
| `WORK_START_HOUR` | `9` | Work zone begins (local time) |
| `WORK_STOP_HOUR` | `18` | Work zone ends |
| `POMO_WORK_MIN` | `25` | Focus interval |
| `POMO_BREAK_MIN` | `5` | Short break |
| `POMO_LONG_BREAK_MIN` | `15` | Long break after 4 rounds |

The app creates `pomodoro-tracker/` subfolders inside each vault on first run if missing.

## Daily flow

1. **Morning (plan)** — open the app, pick tasks from the backlog (+ button) into Today. Reorder with ↑/↓.
2. **Execute** — click a Today task to activate (up to 2). Hit **Start work** on the timer.
3. **Break** — when the work interval ends, choose **Active** (quick personal task during the break) or **Passive** (pure rest).
4. **Off hours** — zone switches to personal automatically; work tasks hide unless you toggle the zone filter.

Pomodoro counts accumulate on the task per day (`3🍅`, `5🍅`, …). A task doesn't have to finish in one pomodoro.

## Slack / GitHub filters

Top-left badges (SL, GH) count backlog tasks tagged `mensaje-slack` / `review`. Click to filter the backlog to just those. Tasks get these tags from the `daily-task-sync` skill.

## Task sync skill

`.claude/skills/daily-task-sync/SKILL.md` — instructions for Claude Code / opencode / any agent to scrape Linear, Slack, and GitHub and drop new `.md` files into `backlog/`. Idempotent via `source_id`. See the skill for details.

Wire it to a cron / schedule (e.g. via `/schedule` in Claude Code) to sync in the background.

## Architecture

- `PomodoroTracker.Vault` — read/write MD + YAML frontmatter
- `PomodoroTracker.Vault.Watcher` — `file_system` watcher → PubSub on vault changes
- `PomodoroTracker.Timer` — GenServer state machine (`:idle | :work | :active_break | :passive_break | :long_break`), broadcasts via PubSub
- `PomodoroTrackerWeb.DayLive` — single LiveView, reacts to both `timer` and `vault` topics
- `PomodoroTrackerWeb.RecurrentPlannerLive` — present, but currently not a stable supported surface

No database. Zero server-side state beyond the Timer GenServer — all source-of-truth is in your vault, and any external editor (Obsidian, vim, another agent) triggers a live UI refresh.
