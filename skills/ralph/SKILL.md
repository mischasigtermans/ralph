---
name: ralph
description: Use this skill when the user invokes "/ralph" to set up a project for the autonomous Ralph loop. Conducts a short PM interview, writes a prose brief plus a story list, and configures the loop's planner cadence. Migrates v1 .ralph/ directories on the fly. Never starts implementing. The user runs `ralph` from a terminal afterward.
version: 1.1.0
---

# Ralph Skill (v2)

Your job in this skill is to **scope** Ralph's autonomous coding loop. Write a **prose brief** that survives across every loop iteration, draft the story list, and decide how often the loop's planner agent should review progress. Then exit. The user runs `ralph` separately.

**CRITICAL: NEVER start implementing within this session. After setup is complete, tell the user to run `ralph` from a terminal.**

## The brief is the contract

The single most important thing you produce is `.ralph/brief.md`. It is **prose**, not bullets. Each loop iteration loads it as the plan-time context. The builder agent reads it before picking a story; the planner agent treats it as read-only ground truth.

Steve Jobs's exit criterion: **if you cannot describe the work in two paragraphs, the planning isn't done yet.** If you find yourself writing a four-page brief, you don't understand the scope well enough. Go back and ask one more question, or push back to narrow the work.

## Step 1: Discover context (silent, no questions yet)

Before asking the user anything, do this on your own:

1. **Read `CLAUDE.md`** if it exists in the project root. Note any conventions, patterns, or external context sources mentioned (issue trackers, spec dirs, dashboards, design docs).
2. **Read any context files referenced by CLAUDE.md** that look directly relevant to the user's request.
3. **If a referenced source is reachable via an MCP server loaded in this session** (Linear, GitHub, Notion, Sentry, etc.), and the user's job description references something matching it (e.g. "PROJ-123" when CLAUDE.md mentions Linear team PROJ), fetch the relevant items quietly. If no MCP for the source is loaded, skip. Don't ask the user to set one up.
4. **Briefly explore the codebase** structure (top-level dirs, package manager, framework signals) so you can write a brief that uses the project's own vocabulary.

If `.ralph/` already exists, check what's there before proceeding (see "Existing .ralph/" below).

## Step 2: One round of clarifying questions (max three)

Now ask the user **at most three questions, in one round**. Don't go back and forth. The exit criterion is 'I can write the brief in two paragraphs'. If you have that already from the user's prompt + discovery, skip questions entirely.

Good questions are about scope edges, invariants, and what to *not* do:

- "Should this include {edge case X}, or is that out of scope?"
- "Are we touching {existing system Y}, or staying isolated?"
- "Is there an existing pattern for {Z} I should follow, or is this new ground?"

Bad questions ask for things you should infer or research:
- "What framework is this?" (you read CLAUDE.md)
- "Where do tests live?" (you grepped)
- "What's your style preference?" (defer to the codebase)

## Step 3: Decide the planner cadence

The loop runs a planner agent every Nth iteration. Lower = more PM oversight, higher cost. Pick one:

| Scope size | Cadence | When |
|---|---|---|
| Small (≤4 stories, isolated change) | **3** | Greenfield small features, single-file refactors |
| Medium (5-10 stories) | **5** | Multi-file features, typical CRUD work |
| Large (>10 stories or cross-cutting) | **10** | Big migrations, feature suites |

Defend the cadence in one line within the brief (e.g. 'Cadence 5. Moderate scope, dependencies between stories warrant a mid-run sanity check'). The user can override later by editing `.ralph/state.json`.

## Step 4: Write `.ralph/brief.md`

This is the artifact that carries plan-time context across every loop iteration. Write it as prose. **Two paragraphs minimum, four maximum.**

Required sections:

```markdown
# {Project / Feature Name}

## What we're building

{One paragraph. The shape of the thing. End state described in plain language.
Reference frameworks/files by name where relevant. This is what the builder
reads before every story to remember why it's working.}

## What's out of scope

{One short paragraph or 3-5 bullets. The walls. What we ruled out and why.
This is the most-skipped section and the most valuable one. It stops the
builder from drifting into adjacent work.}

## Invariants

{Bullets. Things that must remain true throughout. Examples:
- "All endpoints stay backwards-compatible, no contract changes"
- "Existing tests must keep passing"
- "No new top-level dependencies without flagging"
- "User-facing copy is owned by {someone}, don't author new strings"}

## Context

{Optional. Links/refs to external sources used during planning: Linear issues,
spec docs, design files. One-liners: pointers, not summaries.}

## Cadence

Planner runs every {N} iterations. {One sentence rationale.}
```

If you can't fill all four sections meaningfully, you don't have enough context. Go back to Step 2 and ask one more question, or tell the user the scope is too vague to plan.

## Step 5: Write `.ralph/stories.json`

The to-do list. Story shape stays compatible with v1 so existing tooling works:

```json
{
  "project": "Project Name",
  "description": "One-line summary",
  "stories": [
    {
      "id": "PROJ-001",
      "title": "Short imperative title",
      "description": "What this story implements (2-3 sentences). Don't repeat the brief; describe the local change.",
      "acceptance_criteria": [
        "Verifiable criterion 1",
        "Verifiable criterion 2",
        "Tests pass"
      ],
      "priority": 1,
      "passes": false
    }
  ]
}
```

### Story sizing

Each story must fit in one Claude context window. Right-sized examples:
- Add a database migration and model
- Create a single component
- Add one API endpoint with validation
- Implement a service class

If you can't describe a story in 2-3 sentences, split it.

### Story ordering

`priority: 1` runs first. Earlier stories must not depend on later ones. Typical order: data models → services → controllers/routes → UI.

### Acceptance criteria

Each criterion must be verifiable, not vague.

Good: "API returns 401 for unauthenticated requests" / "User model has email + password fields" / "Feature test covers the happy path"

Bad: "Works correctly" / "Good UX" / "Handles edge cases"

Always include at least one of: "Tests pass" or "Feature test covers the happy path".

### Project detection

Detect the project type and set sensible defaults:

- **Laravel** (`artisan` file present): test command `php artisan test --compact` or `vendor/bin/pest --compact`
- **Node.js** (`package.json`): check `scripts.test`
- **Python** (`pyproject.toml` / `setup.py`): `pytest`
- **Other**: use the project's existing test command from its README/Makefile

Story IDs: use a 3-5 letter project prefix + zero-padded number (e.g. `TODO-001`, `INV-014`).

## Step 6: Write `.ralph/state.json`

Initial state, picked up by the loop on first run:

```json
{
  "version": 2,
  "status": "initialized",
  "project_dir": "<absolute path>",
  "started_at": "<ISO 8601 UTC>",
  "updated_at": "<ISO 8601 UTC>",
  "iteration": 0,
  "last_builder_iteration": 0,
  "last_planner_iteration": 0,
  "planner_cadence": <number from Step 3>,
  "next_role": "builder",
  "stories_total": <int>,
  "stories_complete": 0,
  "stories_incomplete": <int>,
  "last_commit": null,
  "last_commit_sha": null,
  "last_planner_note": null,
  "builder_executor": "claude",
  "planner_executor": "claude",
  "builder_model": "claude-sonnet-4-6",
  "planner_model": "claude-opus-4-7",
  "total_cost_usd": 0,
  "pid": null,
  "last_log_path": null,
  "migration": null
}
```

## Step 7: Initialize the auxiliary files

- `.ralph/progress.txt`:
  ```markdown
  # {Project Name} Progress Log

  ---
  ```

- `.ralph/learnings.txt` (only if it doesn't already exist; preserve across runs):
  ```markdown
  # {Project Name} Learnings

  ## Codebase Patterns
  (Patterns discovered during implementation will be added here)

  ## Gotchas
  (Project-specific warnings will be added here)

  ---
  ```

- `.ralph/logs/` directory (empty; the loop populates it).

- Update `.gitignore` to include `.ralph` if it's not already listed. Create the file if missing.

## Existing `.ralph/` handling

If `.ralph/` already exists when the user runs `/ralph`:

- **`brief.md` exists.** Ask: do they want to (a) keep the brief and add new stories, (b) keep the brief and replace the story list, or (c) start over with a new brief? Preserve `learnings.txt` by default unless they explicitly say to reset.

- **`brief.md` missing but `stories.json` or `roadmap.json` present.** This is a v1 directory. The loop will auto-migrate on first run, but doing it here gives the user a real brief instead of a stub. Offer: (a) walk through the PM interview now to write a proper brief, then carry the existing stories forward, or (b) skip, let the loop auto-migrate with a stub brief. Recommend (a).

## Migrating from v1

When a v1 `.ralph/` is present:

1. Move `.ralph/roadmap.json` (if any) to `.ralph/archive/roadmap.v1.json` for reference.
2. Run the PM interview as if from scratch, but use the existing `stories.json` content as input. Many of those stories are likely still valid; reuse them where they fit, drop the rest, add new ones from the conversation.
3. Write a fresh `brief.md` that incorporates what's already been built (read `progress.txt` and recent git log) plus what's still ahead.
4. Preserve `learnings.txt` and `progress.txt`.

## Phase mode is gone

If you encounter an old `--roadmap` invocation (a phase prompt mentioning `<ready>PHASE_READY</ready>`), **do not honor it**. Tell the user that v2 dropped phase mode and that they should describe the whole feature in a single `/ralph` call. The brief replaces what the roadmap used to do. High-level structure now lives in prose, not in a JSON tree.

## After Running

Report what was created:

```
✓ Brief written to .ralph/brief.md ({2 sentences from the brief})
✓ {N} stories in .ralph/stories.json
✓ Planner cadence: every {N} iterations
✓ State initialized in .ralph/state.json
✓ .ralph added to .gitignore

To start the loop, run from a terminal in this directory:

  ralph                  # foreground, watch progress
  nohup ralph &          # detached, log to nohup.out
  tmux new -s ralph 'ralph'   # in a tmux session

Useful subcommands:
  ralph status   current iteration, cost, last commit
  ralph tail     follow .ralph/progress.txt
  ralph stop     graceful stop (finishes current iteration)
```

**Do NOT start implementing. The user must run `ralph` from a terminal.**
