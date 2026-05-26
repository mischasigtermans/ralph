# Changelog

## [1.1.0] - 2026-05-25

**Added**

- `RALPH_BUILDER_EXECUTOR` / `RALPH_PLANNER_EXECUTOR` env vars: pick `claude` or `grok` per role. Both default to `claude`. Model defaults switch automatically with the executor (`grok-build` for grok, `claude-sonnet-4-6` / `claude-opus-4-7` for claude). Both binaries share an almost-identical flag surface (`--agents`, `--agent`, `--model`, `--output-format json`); the script branches on the few that differ (`--always-approve` vs `--dangerously-skip-permissions`, `-p` vs `--print`).
- `.ralph/state.json` now carries `builder_executor` and `planner_executor` fields alongside `builder_model` / `planner_model`, and the loop reads all four. Previously the model fields were descriptive only; now they're load-bearing. Precedence: env var beats state.json, state.json beats built-in default. Existing state.json files without the new fields fall through cleanly to defaults.
- `ralph --watch` flag: when the current batch completes, the loop sets `state.json.status = "waiting"` and polls `.ralph/stories.json` every 10s for new incomplete entries instead of exiting. On a new `passes:false` story it resumes the loop. Honours `STOP_REQUESTED` (Ctrl-C or `ralph stop`) inside the wait. Also intercepts the builder's `<promise>COMPLETE</promise>` sentinel under watch mode so a clean batch-complete routes to `waiting` rather than terminal `complete`.
- `RALPH_WATCH_POLL_SEC` env var to override the 10s watch poll interval. Validated as a positive integer.
- Captures per-iteration stderr separately at `.ralph/logs/iter-NN-{builder|planner}.log.stderr`. The old setup merged stderr into the JSON log via `2>&1`, which broke `jq` parsing for executors that emit non-JSON to stderr (Grok writes an auth-bootstrap line).
- Spinner label now shows `executor:model` so the active CLI shows at a glance.

**Changed**

- `version` field in `scripts/ralph.sh` and `skills/ralph/SKILL.md` realigned with `plugin.json`. They had drifted to an internal 2.x numbering during the 1.0.0 rewrite; plugin.json is the source of truth and all three now move in lockstep.
- SKILL `/ralph` setup writes `builder_executor` / `planner_executor` to the initial `state.json` (both default to `claude`). v1-to-v2 migration also writes them.

**Notes**

- Grok iterations don't surface per-call cost. `state.json` cost tracking accumulates only Claude iterations; Grok contributes 0.
- Projects with `RALPH_*_MODEL` env vars set in shell config gain influence from `state.json` on this release. Env vars still win; the change is that state.json values are no longer ignored when env is unset. If a project previously relied on the hard-coded default winning over its own state.json (an edge case), set the env var explicitly.

## [1.0.0] - 2026-05-09

Major rewrite. Two-agent loop, prose brief, state-aware bash runtime.

**Breaking**

- `--roadmap` mode and 'Loopception' removed.
- `--pause` flag removed.
- `roadmap.json` state file removed (auto-archived on migration).
- Multi-phase scope detection in the SKILL removed.
- `<ready>PHASE_READY</ready>` sentinel removed.
- Positional iteration argument removed (`ralph 50`; use `ralph --max-iter 50`).
- Interactive update prompt during loop startup removed (didn't work in detached mode).

**Added**

- `.ralph/brief.md`: prose brief written by `/ralph`, loaded as plan-time context every iteration.
- Planner agent (default Opus) running every Nth iteration as a PM/reviewer; may rewrite `stories.json` and append to `learnings.txt`.
- `.ralph/state.json`: atomic, machine-readable loop state; tracks iteration, cadence, cost, status, PID, last commit, last planner note, last log path.
- `.ralph/logs/iter-NN-{builder|planner}.log` and `.log.json`: per-iteration audit trail.
- `.ralph/ralph.pid`: written on startup, deleted on exit; backs `ralph stop`.
- Subcommands: `ralph status`, `ralph stop`, `ralph tail`.
- `--max-iter N` flag (replaces 0.x positional iteration count).
- `RALPH_BUILDER_MODEL` / `RALPH_PLANNER_MODEL` env vars for model overrides.
- `claude --print --output-format json` parsing: captures `cost_usd`, `stop_reason`, `session_id` per iteration.
- CLAUDE.md context discovery during `/ralph` PM interview (generic, no vendor coupling).
- Sentinels: `<promise>COMPLETE</promise>` (both roles), `<replan-needed>` (planner only), `<plan-note>` (planner only, captured into state).
- SIGTERM/SIGINT trap on the loop: graceful exit after current iteration.
- Auto-migration from 0.x `.ralph/` directories (archives `roadmap.json`, generates stub `brief.md`, initializes `state.json`).
- Fail-fast prompt-file existence check before any work.

**Changed**

- Two prompt files (`scripts/builder.md`, `scripts/planner.md`) replace the single `scripts/ralph-prompt.md`.
- Agents are defined inline at runtime via `claude --agents <json>`; they never register as plugin agents and stay hidden from the user's `Agent` tool list.
- `SKILL.md` rewritten: PM interview capped at 3 questions, exit criterion is 'can I write the brief in two paragraphs?'.
- `SKILL.md` frontmatter version corrected (was lagging at 0.2.0).
- Builder stop wording strengthened: 'STOP IMMEDIATELY' after one story, no second-iteration drift.
- Plugin manifest gains `keywords` field.

**Migration**

0.x `.ralph/` directories run a one-time migration on first `ralph` invocation. Existing `stories.json`, `progress.txt`, `learnings.txt` are preserved. `roadmap.json` is moved to `.ralph/archive/roadmap.v1.json` (filename preserved for backwards compatibility). A stub `brief.md` is generated; users are urged to re-run `/ralph` for a proper one.

## [0.2.2] - 2026-01-28

**Changed**

- Update prompt asks to run update now (defaults to yes).

**Fixed**

- Version check was comparing against the oldest cached version instead of the newest.

## [0.2.1] - 2026-01-28

**Added**

- Auto-detect `roadmap.json` and prompt to run in roadmap mode (defaults to yes).

## [0.2.0] - 2026-01-28

**Added**

- Loopception: `--roadmap` flag for multi-phase project orchestration (a loop within a loop).
- `--pause` flag to pause between phases for review.
- `/ralph` now detects scope and offers to create a roadmap for large tasks.
- `ralph update` to refresh symlink after plugin updates.
- `ralph --version` and `ralph --help`.

**Changed**

- Roadmap stored as `.ralph/roadmap.json` for reliable jq parsing.
- Default iterations changed to infinite (use `ralph 50` to limit).
- Bash script refactored with reusable functions.

## [0.1.1] - 2026-01-27

**Changed**

- Installer creates a symlink instead of copying files.
- Bash script reads prompt directly from plugin cache (with fallback to `~/.claude/`).
- Re-run the installer after plugin updates to fix symlinks.

**Removed**

- Broken-symlink detection (no longer needed).

## [0.1.0] - 2026-01-27

- Initial release with `/ralph` skill and autonomous loop bash script.
