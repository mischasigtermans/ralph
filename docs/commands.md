# Commands and configuration

## Subcommands

| Command | Purpose |
|---|---|
| `ralph` | Run the loop until complete, halted, or stopped |
| `ralph --max-iter N` | Cap at N iterations |
| `ralph status` | Pretty-print `.ralph/state.json` |
| `ralph stop` | Graceful stop (SIGTERM, exits after current iteration) |
| `ralph tail` | `tail -f .ralph/progress.txt` |
| `ralph update` | Re-run installer (refresh symlink after plugin update) |
| `ralph -v` | Print version |
| `ralph -h` | Show help |

If the loop is unresponsive after 30 seconds, `ralph stop` offers to send SIGKILL.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `RALPH_BUILDER_EXECUTOR` | `claude` | Builder CLI: `claude` or `grok` |
| `RALPH_PLANNER_EXECUTOR` | `claude` | Planner CLI: `claude` or `grok` |
| `RALPH_BUILDER_MODEL` | `claude-sonnet-4-6` (claude) / `grok-build` (grok) | Override the builder model |
| `RALPH_PLANNER_MODEL` | `claude-opus-4-7` (claude) / `grok-build` (grok) | Override the planner model |

## Picking an executor

Both roles default to `claude`. Set the relevant `RALPH_*_EXECUTOR` env var to `grok` to swap. The two CLIs share an almost-identical flag surface; Ralph branches internally on the few that differ.

```bash
# Run the planner on Grok, keep the builder on Claude (recommended first experiment).
RALPH_PLANNER_EXECUTOR=grok ralph

# Run both on Grok.
RALPH_BUILDER_EXECUTOR=grok RALPH_PLANNER_EXECUTOR=grok ralph
```

Model defaults switch automatically with the executor, so swapping `RALPH_PLANNER_EXECUTOR` alone is enough. No need to also set `RALPH_PLANNER_MODEL` unless you want a non-default Grok model.

## Configuration precedence

Both executor and model resolve in this order, highest to lowest:

1. Environment variable (`RALPH_BUILDER_EXECUTOR`, `RALPH_PLANNER_EXECUTOR`, `RALPH_BUILDER_MODEL`, `RALPH_PLANNER_MODEL`)
2. `.ralph/state.json` fields (`builder_executor`, `planner_executor`, `builder_model`, `planner_model`)
3. Built-in default (`claude` for both executors; model default tracks the executor)

This lets you commit a project-specific choice to `.ralph/state.json` and override it ad-hoc with an env var when you need to. `/ralph` setup writes the four fields on initial state.json creation; the v1-to-v2 migration writes them too. Edit them directly in `state.json` to change the project-level default.

Caveats:

- Grok iterations don't surface per-call cost. `state.json` cost tracking accumulates only Claude iterations.
- The Ralph sentinel protocol (`<promise>COMPLETE</promise>`, `<replan-needed>`, `<plan-note>`) lives in model output text. Both Claude and Grok follow the prompt instructions, but nobody has run Grok as a planner in this loop yet, so start small.
