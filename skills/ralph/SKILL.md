---
name: ralph
description: This skill should be used when the user invokes "/ralph" to initialize a project for autonomous development. Creates .ralph/ directory with stories.json, progress.txt, and learnings.txt for the Ralph loop.
version: 1.1.0
---

# Ralph Skill

Initialize a project for the Ralph autonomous development loop.

**CRITICAL: NEVER start implementing within this session. After setup is complete, instruct the user to run `ralph` from their terminal to begin implementation.**

## Instructions

When the user invokes `/ralph`:

### Scope Detection

First, analyze the user's request to determine scope:

**Single phase indicators (create stories directly):**
- One clear feature or component
- Can be broken into 3-5 stories
- No distinct "layers" or "stages"

**Multi-phase indicators (offer roadmap):**
- Multiple distinct areas (auth, API, frontend, etc.)
- Would need 10+ stories
- Natural phases or stages mentioned
- Words like "full", "complete", "end-to-end"

If multi-phase detected, ask:
```
This looks like it could be split into phases:
1. [Phase name]
2. [Phase name]
...

Should I create a roadmap with phases, or keep it as one set of stories?
```

### If user chooses roadmap:

1. Create `.ralph/` directory if needed
2. Create `.ralph/roadmap.json` with phase structure (see format below)
3. Create `.ralph/learnings.txt` if it doesn't exist
4. Do NOT create `stories.json` or `progress.txt` yet
5. Update `.gitignore`
6. Tell user to run `ralph --roadmap`

### If `.ralph/` already exists:

Ask the user what they want to do:

1. **Add stories** - Keep existing stories in `stories.json` and add new ones. Progress and learnings are preserved.
2. **Replace stories** - Start fresh with new stories. Then ask:
   - Keep learnings? (yes → preserve `learnings.txt`, no → reset it)
   - Progress is always reset when replacing stories.

### Setup flow (single phase):

1. **Understand the project** - Read CLAUDE.md and explore the codebase structure
2. **Ask clarifying questions** - Understand goals, constraints, and priorities
3. **Create .ralph/ directory** - If it doesn't exist
4. **Generate .ralph/stories.json** - Create or update the task list with user stories
5. **Create .ralph/progress.txt** - Initialize (or reset if replacing)
6. **Handle .ralph/learnings.txt** - Preserve existing, create if missing, or reset if user chose to
7. **Update .gitignore** - Add `.ralph` to .gitignore (create if needed)

## .ralph/roadmap.json Format

```json
{
  "project": "Project Name",
  "phases": [
    {
      "id": 1,
      "title": "Phase Title",
      "description": [
        "Description bullet 1",
        "Description bullet 2"
      ],
      "complete": false
    },
    {
      "id": 2,
      "title": "Another Phase",
      "description": [
        "Description bullet 1"
      ],
      "complete": false
    }
  ]
}
```

## .ralph/stories.json Format

```json
{
  "project": "Project Name",
  "description": "One-line description",
  "stories": [
    {
      "id": "PROJ-001",
      "title": "Short title",
      "description": "Detailed description of what needs to be built",
      "acceptance_criteria": [
        "Criterion 1",
        "Criterion 2",
        "Tests pass"
      ],
      "priority": 1,
      "passes": false
    }
  ]
}
```

## .ralph/progress.txt Format

```markdown
# {Project Name} Progress Log

---
```

## .ralph/learnings.txt Format

Only create this file if it doesn't already exist. Preserve existing learnings across ralph runs.

```markdown
# {Project Name} Learnings

## Codebase Patterns
(Patterns discovered during implementation will be added here)

## Gotchas
(Project-specific warnings will be added here)

---
```

## Guidelines

### Story Sizing

Each story must be completable in ONE iteration (one Claude context window).

**Right-sized stories:**
- Add a database migration and model
- Create a single component
- Add an API endpoint with validation
- Implement a service class

**Too big (split these):**
- "Build the dashboard" → split into: model, list view, detail view, actions
- "Refactor the API" → split into one story per endpoint

**Rule of thumb:** If you can't describe the change in 2-3 sentences, split it.

### Story Ordering

Stories execute in priority order. Earlier stories must not depend on later ones.

**Correct order:**
1. Database migrations and models
2. Service classes and business logic
3. Controllers and routes
4. UI components that use the above

### Acceptance Criteria

Each criterion must be **verifiable**, not vague.

**Good:**
- "User model has email and password fields"
- "API returns 401 for unauthenticated requests"
- "Feature test covers the happy path"

**Bad:**
- "Works correctly"
- "Good user experience"
- "Handles edge cases"

### Always Include

For every story, include at least one of:
- "Tests pass" (for backend logic)
- "Feature test covers the happy path" (for new features)

### Project Detection

Detect project type to set appropriate defaults:

**Laravel projects** (has `artisan` file):
- Test command: `php artisan test --compact`
- Story IDs: `PROJ-001` format (use project name prefix)

**Node.js projects** (has `package.json`):
- Test command: check scripts.test in package.json
- Story IDs: `PROJ-001` format

**Python projects** (has `pyproject.toml` or `setup.py`):
- Test command: `pytest`
- Story IDs: `PROJ-001` format

## Phase Mode (called from `ralph --roadmap`)

When invoked with phase context, you'll receive a prompt like:
```
Run /ralph for this phase:

Phase: Phase 1: Data Models
  - User and Project models with migrations
  - Basic validation and relationships

Create stories only for this phase. Preserve learnings.txt if it exists.
```

In this mode:
- Create stories ONLY for this phase's scope
- Always reset `.ralph/progress.txt` (new phase = fresh progress)
- Preserve `.ralph/learnings.txt` if it exists
- Do NOT ask clarifying questions - use the phase description as-is
- After setup, output: `<ready>PHASE_READY</ready>`

## After Running

Tell the user what happened:

**If roadmap created:**
- `.ralph/roadmap.json` - created with N phases
- `.ralph/learnings.txt` - created (if new)
- `.ralph` added to .gitignore
- **Run `ralph --roadmap` from terminal to start**

**If stories created:**
- `.ralph/stories.json` - created/updated with N stories (N new if adding)
- `.ralph/progress.txt` - initialized or reset
- `.ralph/learnings.txt` - preserved, created, or reset (based on user choice)
- `.ralph` added to .gitignore (if not already)
- **Run `ralph` from terminal to start the autonomous loop**
- Run `ralph 1` for a single iteration

**Do NOT start implementing. The user must run `ralph` from their terminal.**
