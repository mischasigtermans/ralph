#!/bin/bash
# Ralph 2.0 - Autonomous AI development loop for Claude Code
#
# Loop alternates a builder agent (builds the next story) and a planner
# agent (reviews progress against the prose brief at .ralph/brief.md). Both
# agents are defined inline via `claude --agents <json> --agent <name>` so they
# never register as plugin agents. State lives in .ralph/.

set -e

VERSION="1.1.0"

BUILDER_EXECUTOR="${RALPH_BUILDER_EXECUTOR:-claude}"
PLANNER_EXECUTOR="${RALPH_PLANNER_EXECUTOR:-claude}"

case "$BUILDER_EXECUTOR" in claude|grok) ;; *) echo "Error: RALPH_BUILDER_EXECUTOR must be 'claude' or 'grok' (got '$BUILDER_EXECUTOR')" >&2; exit 1;; esac
case "$PLANNER_EXECUTOR" in claude|grok) ;; *) echo "Error: RALPH_PLANNER_EXECUTOR must be 'claude' or 'grok' (got '$PLANNER_EXECUTOR')" >&2; exit 1;; esac

if [ "$BUILDER_EXECUTOR" = "grok" ]; then
    BUILDER_MODEL="${RALPH_BUILDER_MODEL:-grok-build}"
else
    BUILDER_MODEL="${RALPH_BUILDER_MODEL:-claude-sonnet-4-6}"
fi

if [ "$PLANNER_EXECUTOR" = "grok" ]; then
    PLANNER_MODEL="${RALPH_PLANNER_MODEL:-grok-build}"
else
    PLANNER_MODEL="${RALPH_PLANNER_MODEL:-claude-opus-4-7}"
fi

resolve_script_dir() {
    local src="${BASH_SOURCE[0]}"
    while [ -L "$src" ]; do
        local dir
        dir="$(cd -P "$(dirname "$src")" && pwd)"
        src="$(readlink "$src")"
        [[ "$src" != /* ]] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")" && pwd
}

SCRIPT_DIR="$(resolve_script_dir)"
BUILDER_PROMPT="$SCRIPT_DIR/builder.md"
PLANNER_PROMPT="$SCRIPT_DIR/planner.md"
INSTALLER="$SCRIPT_DIR/install.sh"

SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
if ! echo -e "⠋" | grep -q "⠋" 2>/dev/null; then
    SPINNER=("|" "/" "-" "\\")
fi

show_help() {
    cat <<EOF
ralph $VERSION - Autonomous AI development loop for Claude Code

Usage:
  ralph                  Run the loop until complete or stopped
  ralph --max-iter N     Cap at N iterations
  ralph status           Print .ralph/state.json (pretty)
  ralph stop             Signal the running loop to stop after the current iteration
  ralph tail             Follow .ralph/progress.txt
  ralph update           Re-run installer (refresh symlink)
  ralph -v, --version    Print version
  ralph -h, --help       Show this help

Environment:
  RALPH_BUILDER_EXECUTOR  Builder CLI: claude or grok (default: $BUILDER_EXECUTOR)
  RALPH_PLANNER_EXECUTOR  Planner CLI: claude or grok (default: $PLANNER_EXECUTOR)
  RALPH_BUILDER_MODEL     Override builder model (default: $BUILDER_MODEL)
  RALPH_PLANNER_MODEL     Override planner model (default: $PLANNER_MODEL)

State files (in .ralph/ of the project):
  brief.md       prose brief written by /ralph (read-only after that)
  stories.json   story list (builder flips passes:true; planner may rewrite)
  state.json     loop state (atomic writes by ralph)
  progress.txt   append-only human log
  learnings.txt  cross-iteration patterns
  logs/          per-iteration raw agent output (audit trail)
  ralph.pid      PID of the running loop (deleted on exit)
EOF
}

# ----- Subcommand: status ----------------------------------------------------

cmd_status() {
    if [ ! -f ".ralph/state.json" ]; then
        echo "No .ralph/state.json. Run /ralph in Claude Code first."
        exit 1
    fi

    local s
    s=$(cat .ralph/state.json)

    local status iter cadence next_role total complete incomplete cost
    status=$(echo "$s" | jq -r '.status // "unknown"')
    iter=$(echo "$s" | jq -r '.iteration // 0')
    cadence=$(echo "$s" | jq -r '.planner_cadence // 5')
    next_role=$(echo "$s" | jq -r '.next_role // "builder"')
    total=$(echo "$s" | jq -r '.stories_total // 0')
    complete=$(echo "$s" | jq -r '.stories_complete // 0')
    incomplete=$(echo "$s" | jq -r '.stories_incomplete // 0')
    cost=$(echo "$s" | jq -r '.total_cost_usd // 0')

    local color_status
    case "$status" in
        running)             color_status="\033[1;36m$status\033[0m" ;;
        complete)            color_status="\033[1;32m$status\033[0m" ;;
        error|halted_replan) color_status="\033[1;31m$status\033[0m" ;;
        *)                   color_status="\033[1;33m$status\033[0m" ;;
    esac

    printf "Status:        %b\n" "$color_status"
    printf "Iteration:     %s (next: %s, planner every %s)\n" "$iter" "$next_role" "$cadence"
    printf "Stories:       %s/%s complete (%s remaining)\n" "$complete" "$total" "$incomplete"
    printf "Cost:          \$%.4f\n" "$cost"

    local last_commit last_eval last_log pid
    last_commit=$(echo "$s" | jq -r '.last_commit // empty')
    last_eval=$(echo "$s" | jq -r '.last_planner_note // empty')
    last_log=$(echo "$s" | jq -r '.last_log_path // empty')
    pid=$(echo "$s" | jq -r '.pid // empty')

    [ -n "$last_commit" ] && printf "Last commit:   %s\n" "$last_commit"
    [ -n "$last_eval" ] && printf "Plan note:     %s\n" "$last_eval"
    [ -n "$last_log" ] && printf "Last log:      %s\n" "$last_log"
    [ -n "$pid" ] && [ -f ".ralph/ralph.pid" ] && printf "Running PID:   %s\n" "$pid"
}

# ----- Subcommand: stop ------------------------------------------------------

cmd_stop() {
    if [ ! -f ".ralph/ralph.pid" ]; then
        echo "No .ralph/ralph.pid. Nothing running."
        exit 1
    fi

    local pid
    pid=$(cat .ralph/ralph.pid)

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "PID $pid not running. Cleaning up stale .ralph/ralph.pid."
        rm -f .ralph/ralph.pid
        exit 0
    fi

    echo "Sending SIGTERM to PID $pid (will exit after current iteration)..."
    kill -TERM "$pid"

    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge 30 ]; then
            echo "PID $pid did not exit after 30s. Send SIGKILL? [y/N] "
            read -r reply
            if [[ "$reply" =~ ^[Yy]$ ]]; then
                kill -KILL "$pid" 2>/dev/null || true
                rm -f .ralph/ralph.pid
                echo "Killed."
                exit 0
            fi
            echo "Still waiting..."
            waited=0
        fi
    done

    echo "Stopped."
}

# ----- Subcommand: tail ------------------------------------------------------

cmd_tail() {
    if [ ! -f ".ralph/progress.txt" ]; then
        echo "No .ralph/progress.txt yet."
        exit 1
    fi
    exec tail -f .ralph/progress.txt
}

# ----- Migration from v1 -----------------------------------------------------

migrate_if_needed() {
    [ ! -f ".ralph/stories.json" ] && return 0
    [ -f ".ralph/brief.md" ] && [ ! -f ".ralph/roadmap.json" ] && return 0

    echo "Detected v1 .ralph/ directory. Migrating..."
    mkdir -p .ralph/archive

    if [ -f ".ralph/roadmap.json" ]; then
        mv .ralph/roadmap.json .ralph/archive/roadmap.v1.json
        echo "  Archived roadmap.json → .ralph/archive/roadmap.v1.json"
    fi

    if [ ! -f ".ralph/brief.md" ]; then
        local project_name
        project_name=$(jq -r '.project // "Project"' .ralph/stories.json 2>/dev/null || echo "Project")
        local story_titles
        story_titles=$(jq -r '.stories[]? | "- " + (.title // "")' .ralph/stories.json 2>/dev/null || echo "")

        cat > .ralph/brief.md <<EOF
# $project_name

> **Auto-generated from v1 stories on $(date -u +%Y-%m-%dT%H:%M:%SZ).**
> This is a weak brief. Run \`/ralph\` to replace it with a proper one
> before continuing significant work. Each iteration loads this file as the
> plan-time context, so it's worth doing well.

## What's being built

This brief was synthesized from a v1 \`stories.json\`. The original planning
conversation that produced those stories is not preserved.

## Stories carried over

$story_titles

## Invariants

(none captured during migration; re-run \`/ralph\` to surface these)
EOF
        echo "  Wrote stub .ralph/brief.md"
    fi

    if [ ! -f ".ralph/state.json" ]; then
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local total complete
        total=$(jq '[.stories[]?] | length' .ralph/stories.json 2>/dev/null || echo "0")
        complete=$(jq '[.stories[]? | select(.passes == true)] | length' .ralph/stories.json 2>/dev/null || echo "0")
        local incomplete=$((total - complete))

        jq -n \
            --arg now "$now" \
            --arg pwd "$PWD" \
            --argjson total "$total" \
            --argjson complete "$complete" \
            --argjson incomplete "$incomplete" \
            --arg exec_executor "$BUILDER_EXECUTOR" \
            --arg eval_executor "$PLANNER_EXECUTOR" \
            --arg exec_model "$BUILDER_MODEL" \
            --arg eval_model "$PLANNER_MODEL" \
            '{
                version: 2,
                status: "initialized",
                project_dir: $pwd,
                started_at: $now,
                updated_at: $now,
                iteration: 0,
                last_builder_iteration: 0,
                last_planner_iteration: 0,
                planner_cadence: 5,
                next_role: "builder",
                stories_total: $total,
                stories_complete: $complete,
                stories_incomplete: $incomplete,
                last_commit: null,
                last_commit_sha: null,
                last_planner_note: null,
                builder_executor: $exec_executor,
                planner_executor: $eval_executor,
                builder_model: $exec_model,
                planner_model: $eval_model,
                total_cost_usd: 0,
                pid: null,
                last_log_path: null,
                migration: { from: "1.x", at: $now }
            }' > .ralph/state.json
        echo "  Wrote .ralph/state.json (cadence defaulted to 5; re-run /ralph to set properly)"
    fi

    if [ ! -f ".ralph/progress.txt" ]; then
        printf "# Project Progress Log\n\n---\n\n" > .ralph/progress.txt
    fi
    printf "## Migration %s: auto-migrated from v1\n\n---\n\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .ralph/progress.txt
}

# ----- State helpers ---------------------------------------------------------

state_read() {
    cat .ralph/state.json
}

state_write_atomic() {
    local new_json="$1"
    local tmp=".ralph/state.json.tmp"
    echo "$new_json" > "$tmp"
    mv "$tmp" .ralph/state.json
}

# Precedence for executor + model: env var > state.json > built-in default.
# This runs after state.json passes validation. Script-top assignments already
# applied env > default; here we replace the default with state.json when env
# was unset.
load_loop_config_from_state() {
    local s
    s=$(state_read)

    if [ -z "${RALPH_BUILDER_EXECUTOR:-}" ]; then
        local from_state
        from_state=$(echo "$s" | jq -r '.builder_executor // empty')
        [ -n "$from_state" ] && BUILDER_EXECUTOR="$from_state"
    fi
    if [ -z "${RALPH_PLANNER_EXECUTOR:-}" ]; then
        local from_state
        from_state=$(echo "$s" | jq -r '.planner_executor // empty')
        [ -n "$from_state" ] && PLANNER_EXECUTOR="$from_state"
    fi

    case "$BUILDER_EXECUTOR" in claude|grok) ;; *) echo "Error: builder_executor must be 'claude' or 'grok' (got '$BUILDER_EXECUTOR' from .ralph/state.json)" >&2; exit 1;; esac
    case "$PLANNER_EXECUTOR" in claude|grok) ;; *) echo "Error: planner_executor must be 'claude' or 'grok' (got '$PLANNER_EXECUTOR' from .ralph/state.json)" >&2; exit 1;; esac

    if [ -z "${RALPH_BUILDER_MODEL:-}" ]; then
        local from_state
        from_state=$(echo "$s" | jq -r '.builder_model // empty')
        if [ -n "$from_state" ]; then
            BUILDER_MODEL="$from_state"
        elif [ "$BUILDER_EXECUTOR" = "grok" ]; then
            BUILDER_MODEL="grok-build"
        else
            BUILDER_MODEL="claude-sonnet-4-6"
        fi
    fi
    if [ -z "${RALPH_PLANNER_MODEL:-}" ]; then
        local from_state
        from_state=$(echo "$s" | jq -r '.planner_model // empty')
        if [ -n "$from_state" ]; then
            PLANNER_MODEL="$from_state"
        elif [ "$PLANNER_EXECUTOR" = "grok" ]; then
            PLANNER_MODEL="grok-build"
        else
            PLANNER_MODEL="claude-opus-4-7"
        fi
    fi
}

# ----- Loop ------------------------------------------------------------------

STOP_REQUESTED=false
on_stop_signal() {
    STOP_REQUESTED=true
    echo ""
    echo "Stop requested. Finishing current iteration then exiting..."
}

cleanup_on_exit() {
    rm -f .ralph/ralph.pid 2>/dev/null || true
}

SENTINEL_COMPLETE='<promise>COMPLETE</promise>'
SENTINEL_REPLAN='<replan-needed>'
SENTINEL_PLAN_NOTE='<plan-note>'

extract_plan_note() {
    local result="$1"
    echo "$result" | sed -n 's/.*<plan-note>\(.*\)<\/plan-note>.*/\1/p' | head -1
}

run_iteration() {
    local iter="$1"
    local role="$2"
    local message="$3"

    local prompt_file model agent_desc executor
    if [ "$role" = "builder" ]; then
        prompt_file="$BUILDER_PROMPT"
        model="$BUILDER_MODEL"
        executor="$BUILDER_EXECUTOR"
        agent_desc="Implements one story per invocation. Reads .ralph/brief.md for plan-time context, picks the highest-priority incomplete story, implements it, runs quality checks, commits, marks passes:true."
    else
        prompt_file="$PLANNER_PROMPT"
        model="$PLANNER_MODEL"
        executor="$PLANNER_EXECUTOR"
        agent_desc="Reviews progress against the brief. May rewrite stories.json and append to learnings.txt. Halts the loop if the brief itself needs rework."
    fi

    if [ ! -f "$prompt_file" ]; then
        echo "Error: prompt file not found: $prompt_file" >&2
        return 1
    fi

    local agents_json
    agents_json=$(jq -n \
        --rawfile prompt "$prompt_file" \
        --arg desc "$agent_desc" \
        --arg name "ralph-$role" \
        '{ ($name): { description: $desc, prompt: $prompt } }')

    local log_base
    log_base=$(printf ".ralph/logs/iter-%02d-%s" "$iter" "$role")
    mkdir -p .ralph/logs

    local output_json="$log_base.log.json"
    local output_text="$log_base.log"
    local output_stderr="$log_base.log.stderr"

    if [ "$executor" = "grok" ]; then
        grok \
            --always-approve \
            --agents "$agents_json" \
            --agent "ralph-$role" \
            --model "$model" \
            --output-format json \
            -p "$message" > "$output_json" 2> "$output_stderr" &
    else
        claude \
            --dangerously-skip-permissions \
            --agents "$agents_json" \
            --agent "ralph-$role" \
            --model "$model" \
            --print \
            --output-format json \
            "$message" > "$output_json" 2> "$output_stderr" &
    fi
    local pid=$!

    local spin_idx=0
    local label
    if [ "$role" = "builder" ]; then
        label="Building iteration $iter ($executor:$model)"
    else
        label="Planning iteration $iter ($executor:$model)"
    fi

    while kill -0 $pid 2>/dev/null; do
        printf "\r%s %s..." "${SPINNER[$spin_idx]}" "$label"
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER[@]} ))
        sleep 0.1
    done

    wait $pid
    local exit_code=$?
    printf "\r\033[K"

    if [ "$exit_code" -ne 0 ]; then
        echo "✗ $executor exited $exit_code (see $output_json, stderr at $output_stderr)" >&2
        ITER_RESULT=""
        ITER_COST=0
        ITER_STOP_REASON="error_exit_code"
        return 1
    fi

    if ! jq -e '.' "$output_json" > /dev/null 2>&1; then
        echo "✗ $executor output is not valid JSON (see $output_json, stderr at $output_stderr)" >&2
        ITER_RESULT=""
        ITER_COST=0
        ITER_STOP_REASON="error_invalid_json"
        return 1
    fi

    if [ "$executor" = "grok" ]; then
        # grok --output-format json returns a single JSON object:
        #   { "text": ..., "stopReason": "EndTurn", "sessionId": ..., "requestId": ... }
        # grok.com login surfaces no per-call cost; drop the thought field.
        ITER_RESULT=$(jq -r '.text // ""' "$output_json")
        ITER_COST=0
        ITER_SESSION_ID=$(jq -r '.sessionId // ""' "$output_json")
        local grok_stop
        grok_stop=$(jq -r '.stopReason // "unknown"' "$output_json")
        case "$grok_stop" in
            EndTurn)      ITER_STOP_REASON="end_turn" ;;
            StopSequence) ITER_STOP_REASON="stop_sequence" ;;
            *)            ITER_STOP_REASON="$grok_stop" ;;
        esac
    else
        # claude --print --output-format json returns a stream of events as an array.
        # The completion is in the last element with type == "result".
        local result_event
        result_event=$(jq -c '[.[]? | select(.type == "result")] | .[0] // empty' "$output_json")

        if [ -z "$result_event" ]; then
            echo "✗ No result event found in claude output (see $output_json)" >&2
            ITER_RESULT=""
            ITER_COST=0
            ITER_STOP_REASON="error_no_result_event"
            return 1
        fi

        ITER_RESULT=$(echo "$result_event" | jq -r '.result // ""')
        ITER_COST=$(echo "$result_event" | jq -r '.total_cost_usd // 0')
        ITER_STOP_REASON=$(echo "$result_event" | jq -r '.stop_reason // "unknown"')
        ITER_SESSION_ID=$(echo "$result_event" | jq -r '.session_id // ""')

        local is_error
        is_error=$(echo "$result_event" | jq -r '.is_error // false')
        if [ "$is_error" = "true" ]; then
            local subtype api_err
            subtype=$(echo "$result_event" | jq -r '.subtype // "unknown"')
            api_err=$(echo "$result_event" | jq -r '.api_error_status // ""')
            echo "✗ claude reported is_error=true (subtype: $subtype, api_status: $api_err). See $output_json" >&2
            return 1
        fi
    fi

    ITER_LOG_PATH="$output_text"
    echo "$ITER_RESULT" > "$output_text"

    if [ "$ITER_STOP_REASON" != "end_turn" ] && [ "$ITER_STOP_REASON" != "stop_sequence" ]; then
        echo "✗ Non-terminal stop_reason: $ITER_STOP_REASON (see $output_json)" >&2
        return 1
    fi

    return 0
}

update_state_after_iteration() {
    local role="$1"
    local s
    s=$(state_read)

    local now iter prev_cost new_cost
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    iter=$(echo "$s" | jq -r '.iteration')
    prev_cost=$(echo "$s" | jq -r '.total_cost_usd // 0')
    new_cost=$(echo "$prev_cost + $ITER_COST" | bc -l 2>/dev/null || echo "$prev_cost")

    local cadence just_ran upcoming next_role
    cadence=$(echo "$s" | jq -r '.planner_cadence // 5')
    just_ran=$((iter + 1))
    upcoming=$((just_ran + 1))
    if [ $((upcoming % cadence)) -eq 0 ] && [ "$upcoming" -gt 0 ]; then
        next_role="planner"
    else
        next_role="builder"
    fi

    local last_commit last_sha
    last_commit=$(git log -1 --pretty=%s 2>/dev/null || echo "")
    last_sha=$(git log -1 --pretty=%h 2>/dev/null || echo "")

    local total complete incomplete
    total=$(jq '[.stories[]?] | length' .ralph/stories.json 2>/dev/null || echo "0")
    complete=$(jq '[.stories[]? | select(.passes == true)] | length' .ralph/stories.json 2>/dev/null || echo "0")
    incomplete=$((total - complete))

    local plan_note
    if [ "$role" = "planner" ]; then
        plan_note=$(extract_plan_note "$ITER_RESULT")
    else
        plan_note=$(echo "$s" | jq -r '.last_planner_note // ""')
    fi

    local last_exec last_eval
    last_exec=$(echo "$s" | jq -r '.last_builder_iteration // 0')
    last_eval=$(echo "$s" | jq -r '.last_planner_iteration // 0')
    if [ "$role" = "builder" ]; then
        last_exec=$just_ran
    else
        last_eval=$just_ran
    fi

    local updated
    updated=$(echo "$s" | jq \
        --arg now "$now" \
        --argjson iter "$just_ran" \
        --argjson exec "$last_exec" \
        --argjson eval "$last_eval" \
        --arg next_role "$next_role" \
        --argjson total "$total" \
        --argjson complete "$complete" \
        --argjson incomplete "$incomplete" \
        --arg last_commit "$last_commit" \
        --arg last_sha "$last_sha" \
        --arg plan_note "$plan_note" \
        --argjson cost "$new_cost" \
        --arg log_path "$ITER_LOG_PATH" \
        '
        .updated_at = $now |
        .iteration = $iter |
        .last_builder_iteration = $exec |
        .last_planner_iteration = $eval |
        .next_role = $next_role |
        .stories_total = $total |
        .stories_complete = $complete |
        .stories_incomplete = $incomplete |
        .last_commit = (if $last_commit == "" then null else $last_commit end) |
        .last_commit_sha = (if $last_sha == "" then null else $last_sha end) |
        .last_planner_note = (if $plan_note == "" then .last_planner_note else $plan_note end) |
        .total_cost_usd = $cost |
        .last_log_path = $log_path
        ')
    state_write_atomic "$updated"
}

mark_terminal_state() {
    local terminal_status="$1"
    local s
    s=$(state_read)
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local updated
    updated=$(echo "$s" | jq --arg now "$now" --arg st "$terminal_status" '.updated_at = $now | .status = $st | .pid = null')
    state_write_atomic "$updated"
}

validate_json_file() {
    local path="$1"
    local label="$2"

    if [ ! -f "$path" ]; then
        cat >&2 <<EOF
Error: $label missing.
  expected: $path

Run /ralph in Claude Code first to set up this project.
EOF
        return 1
    fi
    if ! jq -e . "$path" > /dev/null 2>&1; then
        cat >&2 <<EOF
Error: $label is corrupted (not valid JSON).
  file: $path

Recovery options:
  1. Restore from git:   git checkout $path
  2. Inspect the file:   cat $path
  3. Reset from scratch: re-run /ralph in Claude Code (overwrites $path)
EOF
        return 1
    fi
    return 0
}

run_loop() {
    local max_iter="$1"

    migrate_if_needed

    validate_json_file ".ralph/state.json" ".ralph/state.json" || exit 1
    validate_json_file ".ralph/stories.json" ".ralph/stories.json" || exit 1

    load_loop_config_from_state

    if [ ! -s ".ralph/brief.md" ]; then
        cat >&2 <<EOF
Error: .ralph/brief.md is missing or empty.
  expected: $PWD/.ralph/brief.md

The brief is the plan-time context every iteration loads. Run /ralph in
Claude Code to author one. Without it the builder has no idea what's
being built.
EOF
        exit 1
    fi
    if [ ! -f "$BUILDER_PROMPT" ] || [ ! -f "$PLANNER_PROMPT" ]; then
        cat >&2 <<EOF
Error: Ralph prompt files not found.
  expected: $BUILDER_PROMPT
  expected: $PLANNER_PROMPT

Reinstall the plugin:
  /plugin install ralph@by-mischa
EOF
        exit 1
    fi

    echo "$$" > .ralph/ralph.pid
    trap on_stop_signal TERM INT
    trap cleanup_on_exit EXIT

    local s now
    s=$(state_read)
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    s=$(echo "$s" | jq --arg now "$now" --argjson pid "$$" '.status = "running" | .updated_at = $now | .pid = $pid')
    state_write_atomic "$s"

    if [ "$max_iter" -eq 0 ]; then
        echo "Starting Ralph loop (no iteration cap)"
    else
        echo "Starting Ralph loop (max $max_iter iterations)"
    fi
    echo "Brief: $(head -1 .ralph/brief.md | sed 's/^#\{1,\} *//')"

    local iter_count=0
    while true; do
        if [ "$STOP_REQUESTED" = true ]; then
            mark_terminal_state "stopped"
            echo "Stopped after $iter_count iterations."
            exit 0
        fi

        if [ "$max_iter" -gt 0 ] && [ "$iter_count" -ge "$max_iter" ]; then
            mark_terminal_state "stopped_max_iter"
            echo "Reached max iterations ($max_iter). Run 'ralph' again to continue."
            exit 0
        fi

        local current_state next_role next_iter incomplete
        current_state=$(state_read)
        next_iter=$(echo "$current_state" | jq -r '.iteration + 1')
        next_role=$(echo "$current_state" | jq -r '.next_role')
        incomplete=$(jq '[.stories[]? | select(.passes == false)] | length' .ralph/stories.json 2>/dev/null || echo "0")

        if [ "$incomplete" -eq 0 ] && [ "$next_role" = "builder" ]; then
            mark_terminal_state "complete"
            echo "All stories complete."
            exit 0
        fi

        printf "────────────────────────────────────────────────────────────\n▸ Iteration %02d  •  %-7s  •  %s remaining\n" "$next_iter" "$next_role" "$incomplete"

        local message
        if [ "$next_role" = "builder" ]; then
            message="Run the next iteration. Implement exactly one story, then stop."
        else
            local last_eval_iter range_start
            last_eval_iter=$(echo "$current_state" | jq -r '.last_planner_iteration // 0')
            range_start=$((last_eval_iter + 1))
            message="Review iterations $range_start through $next_iter and the recent commits. Decide whether the plan still fits."
        fi

        if ! run_iteration "$next_iter" "$next_role" "$message"; then
            mark_terminal_state "error"
            echo "Iteration $next_iter failed. State set to 'error'. See .ralph/logs/."
            exit 1
        fi

        update_state_after_iteration "$next_role"
        iter_count=$((iter_count + 1))

        if echo "$ITER_RESULT" | grep -qF "$SENTINEL_COMPLETE"; then
            mark_terminal_state "complete"
            echo "✓ Loop complete."
            exit 0
        fi

        if [ "$next_role" = "planner" ] && echo "$ITER_RESULT" | grep -qF "$SENTINEL_REPLAN"; then
            mark_terminal_state "halted_replan"
            echo ""
            echo "Planner requested a replan. Loop halted."
            echo "Re-run /ralph in Claude Code to author a new brief."
            echo ""
            echo "Reason from planner:"
            echo "$ITER_RESULT" | sed -n 's/.*<replan-needed>\(.*\)<\/replan-needed>.*/\1/p' | head -5
            exit 0
        fi

        if [ "$next_role" = "planner" ] && echo "$ITER_RESULT" | grep -qF "$SENTINEL_PLAN_NOTE"; then
            local note
            note=$(extract_plan_note "$ITER_RESULT")
            [ -n "$note" ] && echo "Plan note: $note"
        fi

        sleep 1
    done
}

# ----- Entry point -----------------------------------------------------------

case "${1:-}" in
    -v|--version)
        echo "ralph $VERSION"
        exit 0
        ;;
    -h|--help)
        show_help
        exit 0
        ;;
    update)
        if [ -x "$INSTALLER" ]; then
            exec "$INSTALLER"
        else
            echo "Error: installer not found at $INSTALLER" >&2
            echo "Reinstall the plugin:" >&2
            echo "  /plugin install ralph@by-mischa" >&2
            exit 1
        fi
        ;;
    status)
        cmd_status
        exit 0
        ;;
    stop)
        cmd_stop
        exit 0
        ;;
    tail)
        cmd_tail
        ;;
esac

MAX_ITERATIONS=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --max-iter)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        --max-iter=*)
            MAX_ITERATIONS="${1#--max-iter=}"
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Run 'ralph --help' for usage." >&2
            exit 1
            ;;
    esac
done

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "Error: --max-iter must be a non-negative integer." >&2
    exit 1
fi

run_loop "$MAX_ITERATIONS"
