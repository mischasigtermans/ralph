#!/bin/bash
# Ralph - Autonomous AI development loop for Claude Code

set -e

VERSION="1.1.2"

# Help text
show_help() {
    echo "ralph - Autonomous AI development loop for Claude Code"
    echo ""
    echo "Usage:"
    echo "  ralph              Run until all stories complete"
    echo "  ralph 50           Limit to 50 iterations"
    echo "  ralph --roadmap    Run phases from .ralph/roadmap.json (Loopception)"
    echo "  ralph --pause      Pause between phases (with --roadmap)"
    echo "  ralph update       Re-run installer to refresh symlink"
    echo "  ralph -v, --version"
    echo "  ralph -h, --help"
}

# Compare versions (returns 0 if $1 > $2)
version_gt() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ] && [ "$1" != "$2" ]
}

# Check for plugin updates
check_version() {
    local plugin_json=$(ls "$HOME/.claude/plugins/cache/rydeventures-claude-plugins/ralph"/*/.claude-plugin/plugin.json 2>/dev/null | tail -1)
    if [ -n "$plugin_json" ]; then
        local plugin_version=$(jq -r '.version // empty' "$plugin_json" 2>/dev/null)
        if [ -n "$plugin_version" ] && version_gt "$plugin_version" "$VERSION"; then
            echo "Update available: $VERSION → $plugin_version"
            read -p "Update now? [Y/n] " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                INSTALLER=$(ls "$HOME/.claude/plugins/cache/rydeventures-claude-plugins/ralph"/*/scripts/install.sh 2>/dev/null | tail -1)
                if [ -n "$INSTALLER" ]; then
                    exec "$INSTALLER"
                fi
            fi
            exit 0
        fi
    fi
}

# Handle immediate commands first
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
        INSTALLER=$(ls "$HOME/.claude/plugins/cache/rydeventures-claude-plugins/ralph"/*/scripts/install.sh 2>/dev/null | tail -1)
        if [ -n "$INSTALLER" ]; then
            exec "$INSTALLER"
        else
            echo "Error: Plugin not found. Install via Claude Code first:"
            echo "  /plugin install ralph@rydeventures-claude-plugins"
            exit 1
        fi
        ;;
esac

# Check for updates on normal runs
check_version

# Defaults
MAX_ITERATIONS=0
ROADMAP_MODE=false
PAUSE_BETWEEN_PHASES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --roadmap)
            ROADMAP_MODE=true
            shift
            ;;
        --pause)
            PAUSE_BETWEEN_PHASES=true
            shift
            ;;
        *)
            MAX_ITERATIONS="$1"
            shift
            ;;
    esac
done

# Check if roadmap exists but --roadmap wasn't used
if [ "$ROADMAP_MODE" = false ] && [ -f ".ralph/roadmap.json" ]; then
    echo "Found .ralph/roadmap.json"
    read -p "Run in roadmap mode? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        ROADMAP_MODE=true
    fi
fi

# Find prompt file: plugin cache first, fallback to ~/.claude/
PLUGIN_DIR=$(ls -d "$HOME/.claude/plugins/cache/rydeventures-claude-plugins/ralph"/*/ 2>/dev/null | tail -1)
if [ -n "$PLUGIN_DIR" ] && [ -f "${PLUGIN_DIR}scripts/ralph-prompt.md" ]; then
    PROMPT_FILE="${PLUGIN_DIR}scripts/ralph-prompt.md"
elif [ -f "$HOME/.claude/ralph-prompt.md" ]; then
    PROMPT_FILE="$HOME/.claude/ralph-prompt.md"
else
    PROMPT_FILE=""
fi

# Braille spinner frames
SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
if ! echo -e "⠋" | grep -q "⠋" 2>/dev/null; then
    SPINNER=("|" "/" "-" "\\")
fi

# Run Claude with spinner
run_claude() {
    local prompt="$1"
    local message="$2"

    local output_file=$(mktemp)
    local escaped_prompt=$(echo "$prompt" | sed 's/`/\\`/g')

    eval "claude --dangerously-skip-permissions --print \"\$escaped_prompt\"" > "$output_file" 2>&1 &
    local pid=$!

    local spin_idx=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r${SPINNER[$spin_idx]} $message"
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER[@]} ))
        sleep 0.1
    done

    wait $pid
    local exit_code=$?

    CLAUDE_OUTPUT=$(cat "$output_file")
    rm -f "$output_file"

    return $exit_code
}

# Get next incomplete phase from roadmap.json
get_next_phase() {
    jq -r '.phases[] | select(.complete == false) | @json' .ralph/roadmap.json 2>/dev/null | head -1
}

# Mark phase complete by ID in roadmap.json
mark_phase_complete() {
    local phase_id="$1"
    local tmp_file=$(mktemp)
    jq "(.phases[] | select(.id == $phase_id)).complete = true" .ralph/roadmap.json > "$tmp_file"
    mv "$tmp_file" .ralph/roadmap.json
}

# Run story loop until all stories complete or max iterations
run_story_loop() {
    local max_iter="$1"
    local iter=1

    while [ "$max_iter" -eq 0 ] || [ "$iter" -le "$max_iter" ]; do
        if [ "$max_iter" -eq 0 ]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Ralph Iteration $iter"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        else
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Ralph Iteration $iter / $max_iter"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        fi
        echo ""

        # Check remaining stories
        local incomplete=$(jq '[.stories[] | select(.passes == false)] | length' .ralph/stories.json 2>/dev/null || echo "0")

        if [ "$incomplete" -eq 0 ]; then
            echo "✓ All stories complete!"
            return 0
        fi

        # Get next story info
        local next_story=$(jq -r '[.stories[] | select(.passes == false)] | sort_by(.priority) | .[0] | "\(.id): \(.title)"' .ralph/stories.json 2>/dev/null || echo "Unknown")

        echo "Remaining: $incomplete stories"
        echo "Next: $next_story"
        echo ""

        # Run Claude
        local prompt_content=$(cat "$PROMPT_FILE")
        if run_claude "$prompt_content" "Ralph is working on iteration $iter..."; then
            printf "\r✓ Ralph completed iteration $iter\n"
        else
            printf "\r✗ Ralph iteration $iter failed\n"
        fi
        echo ""

        # Check for completion signal
        if echo "$CLAUDE_OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "✓ Ralph completed all stories!"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            return 0
        fi

        echo "Continuing in 2 seconds..."
        sleep 2
        ((iter++))
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠ Reached max iterations ($max_iter)"
    echo "Run 'ralph' again to continue."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    return 1
}

# Roadmap mode: run phases
run_roadmap_mode() {
    local phase_num=1

    echo "Starting Ralph Roadmap Mode"
    echo ""

    local phase_json
    while phase_json=$(get_next_phase) && [ -n "$phase_json" ]; do
        local phase_id=$(echo "$phase_json" | jq -r '.id')
        local phase_title=$(echo "$phase_json" | jq -r '.title')
        local phase_description=$(echo "$phase_json" | jq -r '.description | map("  - " + .) | join("\n")')

        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║ Phase $phase_num: $phase_title"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""

        # Build phase prompt for /ralph
        local phase_prompt="Run /ralph for this phase:

Phase: $phase_title
$phase_description

Create stories only for this phase. Preserve learnings.txt if it exists."

        echo "Setting up phase..."
        if run_claude "$phase_prompt" "Ralph is setting up phase $phase_num..."; then
            printf "\r✓ Phase setup complete\n"
        else
            printf "\r✗ Phase setup failed\n"
            return 1
        fi
        echo ""

        # Check for ready signal
        if ! echo "$CLAUDE_OUTPUT" | grep -q "<ready>PHASE_READY</ready>"; then
            echo "Warning: Phase setup did not signal ready, continuing anyway..."
        fi

        # Run story loop for this phase (infinite iterations)
        if ! run_story_loop 0; then
            echo "Phase did not complete successfully"
            return 1
        fi

        # Mark phase complete
        mark_phase_complete "$phase_id"
        echo ""
        echo "✓ Phase $phase_num marked complete"
        echo ""

        # Pause if requested
        if [ "$PAUSE_BETWEEN_PHASES" = true ]; then
            echo "Press Enter to continue to next phase..."
            read -r
        fi

        ((phase_num++))
    done

    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║ All phases complete!"
    echo "╚══════════════════════════════════════════════════════════════╝"
    return 0
}

# ============================================================================
# Main
# ============================================================================

# Roadmap mode
if [ "$ROADMAP_MODE" = true ]; then
    if [ ! -f ".ralph/roadmap.json" ]; then
        echo "Error: .ralph/roadmap.json not found"
        echo "Run '/ralph' in Claude Code first to create a roadmap"
        exit 1
    fi

    # Prompt file needed for story iterations
    if [ -z "$PROMPT_FILE" ]; then
        echo "Error: Ralph prompt file not found."
        echo ""
        echo "Either install the plugin in Claude Code:"
        echo "  /plugin install ralph@rydeventures-claude-plugins"
        echo ""
        echo "Or copy ralph-prompt.md to ~/.claude/"
        exit 1
    fi

    run_roadmap_mode
    exit $?
fi

# Standard mode: validate and run story loop
if [ -z "$PROMPT_FILE" ]; then
    echo "Error: Ralph prompt file not found."
    echo ""
    echo "Either install the plugin in Claude Code:"
    echo "  /plugin install ralph@rydeventures-claude-plugins"
    echo ""
    echo "Or copy ralph-prompt.md to ~/.claude/"
    exit 1
fi

if [ ! -f ".ralph/stories.json" ]; then
    echo "Error: .ralph/stories.json not found in current directory"
    echo "Run '/ralph' in Claude Code first to generate requirements"
    exit 1
fi

# Initialize progress.txt if needed
if [ ! -f ".ralph/progress.txt" ]; then
    PROJECT_NAME=$(jq -r '.project // "Project"' .ralph/stories.json)
    cat > .ralph/progress.txt << EOF
# $PROJECT_NAME Progress Log

---

EOF
    echo "Created .ralph/progress.txt"
fi

if [ "$MAX_ITERATIONS" -eq 0 ]; then
    echo "Starting Ralph"
else
    echo "Starting Ralph - Max iterations: $MAX_ITERATIONS"
fi
echo ""

run_story_loop "$MAX_ITERATIONS"
exit $?
