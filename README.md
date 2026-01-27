# Ralph

Autonomous AI development loop for Claude Code. Define user stories, run the loop, check back when it's done.

The concept comes from [Geoffrey Huntley](https://ghuntley.com/ralph/), who named it after Ralph Wiggum from The Simpsons. Each iteration spawns a fresh Claude instance with no memory of previous runs. The AI's work persists through files: git commits, a progress log, and a learnings file.

Available through the [Ryde Ventures plugin marketplace](https://github.com/rydeventures/claude-plugins).

## Installation

### Step 1: Install the plugin

```bash
# Add the Ryde Ventures marketplace (one-time)
/plugin marketplace add rydeventures/claude-plugins

# Install the plugin
/plugin install ralph@rydeventures-claude-plugins
```

### Step 2: Install the bash script

The plugin includes a bash script that runs the autonomous loop. The installer copies two files to your home directory:
- `ralph` command to `~/.local/bin/`
- `ralph-prompt.md` to `~/.claude/`

Run the installer:

```bash
~/.claude/plugins/cache/rydeventures-claude-plugins/ralph/*/scripts/install.sh
```

If `~/.local/bin` isn't in your PATH, add it:

```bash
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.zshrc
source ~/.zshrc
```

### Manual Installation

Alternatively, copy the files manually from this repository:

**Bash script and prompt (required):**

```bash
# Create directories
mkdir -p ~/.local/bin ~/.claude

# Copy files
cp scripts/ralph.sh ~/.local/bin/ralph
cp scripts/ralph-prompt.md ~/.claude/ralph-prompt.md

# Make executable
chmod +x ~/.local/bin/ralph
```

**Skill (for `/ralph` command):**

User-level (available in all projects):
```bash
mkdir -p ~/.claude/skills/ralph
cp skills/ralph/SKILL.md ~/.claude/skills/ralph/skill.md
```

Project-level (available only in this project):
```bash
mkdir -p .claude/skills/ralph
cp skills/ralph/SKILL.md .claude/skills/ralph/skill.md
```

## Usage

### 1. Initialize a project

Open Claude Code in your project directory and run:

```
/ralph
```

Claude will ask about your feature, then generate a `.ralph/` directory:

```
.ralph/
├── stories.json    # Your user stories
├── progress.txt    # Implementation log per iteration
└── learnings.txt   # Patterns and gotchas (persists across runs)
```

### 2. Run the loop

Exit Claude Code and run from terminal:

```bash
ralph        # Default: 20 iterations
ralph 50     # Custom: 50 iterations
ralph 1      # Single iteration (useful for testing)
```

### 3. Review results

When Ralph finishes (or hits max iterations), check:
- Git log for commits
- `.ralph/progress.txt` for what was implemented
- `.ralph/learnings.txt` for patterns discovered
- `.ralph/stories.json` for completion status

## How it works

```
┌─────────────────────────────────────────────────────────┐
│  /ralph                                                 │
│  Creates .ralph/ with stories, progress, learnings      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  ralph (bash script)                                    │
│  Loops until all stories complete or max iterations     │
│                                                         │
│  Each iteration:                                        │
│  1. Spawns fresh Claude instance                        │
│  2. Claude reads .ralph/ files                          │
│  3. Implements highest priority incomplete story        │
│  4. Runs tests, commits, updates files                  │
│  5. Outputs <promise>COMPLETE</promise> when done       │
└─────────────────────────────────────────────────────────┘
```

## The learnings file

Knowledge compounds across iterations. After several runs, `.ralph/learnings.txt` might look like:

```markdown
# Project Learnings

## Codebase Patterns
- This project uses Repository pattern for data access
- All API responses use JsonResource classes
- Feature tests extend TestCase with RefreshDatabase trait

## Gotchas
- The User model uses SoftDeletes - check for trashed records
- Queue jobs need QUEUE_CONNECTION=sync in tests
```

Every new iteration reads this first, avoiding repeated mistakes.

## Story sizing

The sweet spot is one story per context window:

**Right-sized:**
- Add a database migration and model
- Create a single component
- Add an API endpoint with validation

**Too big (split these):**
- "Build the dashboard" → model, list view, detail view, actions
- "Refactor the API" → one story per endpoint

## When to intervene

Ralph works best on greenfield features with clear acceptance criteria. Intervene when:
- The same story fails twice (needs splitting)
- A story needs context it can't discover from files
- Tests require manual setup or external services

## File locations

| File | Location | Purpose |
|------|----------|---------|
| `ralph` | `~/.local/bin/ralph` | Bash script (the loop) |
| `ralph-prompt.md` | `~/.claude/ralph-prompt.md` | Instructions for each iteration |
| `/ralph` skill | Plugin | Initializes projects |

## See also

- [Blog post](https://mischa.sigtermans.me/my-simplified-ralph-loop-setup-for-claude-code) explaining the setup
- [snarktank/ralph](https://github.com/snarktank/ralph) - Ryan Carson's full implementation with flowcharts

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `jq` for JSON parsing (`brew install jq` on macOS)

## Credits

- [Mischa Sigtermans](https://github.com/mischasigtermans)
- Concept: [Geoffrey Huntley](https://ghuntley.com/ralph/)

## License

MIT
