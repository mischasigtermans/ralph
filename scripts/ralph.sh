#!/bin/bash
# Ralph - Autonomous AI development loop for Claude Code
# Usage: ralph [max_iterations]

set -e

MAX_ITERATIONS=${1:-20}
PROMPT_FILE="$HOME/.claude/ralph-prompt.md"

# Braille spinner frames
SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
# Fallback to ASCII if Unicode doesn't work
if ! echo -e "⠋" | grep -q "⠋" 2>/dev/null; then
    SPINNER=("|" "/" "-" "\\")
fi

# Validate prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: Ralph prompt file not found at $PROMPT_FILE"
    echo "Run the install script first: ./install.sh"
    exit 1
fi

# Validate .ralph/stories.json exists
if [ ! -f ".ralph/stories.json" ]; then
    echo "Error: .ralph/stories.json not found in current directory"
    echo "Run '/ralph' in Claude Code first to generate requirements"
    exit 1
fi

# Initialize .ralph/progress.txt if it doesn't exist
if [ ! -f ".ralph/progress.txt" ]; then
    PROJECT_NAME=$(jq -r '.project // "Project"' .ralph/stories.json)
    cat > .ralph/progress.txt << EOF
# $PROJECT_NAME Progress Log

---

EOF
    echo "Created .ralph/progress.txt"
fi

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Ralph Iteration $i / $MAX_ITERATIONS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check remaining stories
    incomplete=$(jq '[.stories[] | select(.passes == false)] | length' .ralph/stories.json 2>/dev/null || echo "0")

    if [ "$incomplete" -eq 0 ]; then
        echo "✓ All stories complete!"
        exit 0
    fi

    # Get next story info
    next_story=$(jq -r '[.stories[] | select(.passes == false)] | sort_by(.priority) | .[0] | "\(.id): \(.title)"' .ralph/stories.json 2>/dev/null || echo "Unknown")

    echo "Remaining: $incomplete stories"
    echo "Next: $next_story"
    echo ""

    # Read prompt and escape backticks for bash
    PROMPT_CONTENT=$(sed 's/`/\\`/g' "$PROMPT_FILE")

    # Create temp file for output
    OUTPUT_FILE=$(mktemp)

    # Run Claude in background
    eval "claude --dangerously-skip-permissions --print \"\$PROMPT_CONTENT\"" > "$OUTPUT_FILE" 2>&1 &
    CLAUDE_PID=$!

    # Show spinner while Claude works
    spin_idx=0
    while kill -0 $CLAUDE_PID 2>/dev/null; do
        printf "\r${SPINNER[$spin_idx]} Ralph is working on iteration $i..."
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER[@]} ))
        sleep 0.1
    done

    # Get exit code
    wait $CLAUDE_PID
    exit_code=$?

    # Read output
    OUTPUT=$(cat "$OUTPUT_FILE")
    rm -f "$OUTPUT_FILE"

    # Clear spinner line and show result
    if [ $exit_code -eq 0 ]; then
        printf "\r✓ Ralph completed iteration $i\n"
    else
        printf "\r✗ Ralph iteration $i failed (exit code: $exit_code)\n"
    fi

    echo ""

    # Check for completion signal
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✓ Ralph completed all tasks!"
        echo "Finished at iteration $i of $MAX_ITERATIONS".
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
    fi

    echo "Continuing in 2 seconds..."
    sleep 2
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠ Reached max iterations ($MAX_ITERATIONS)"
echo "Run 'ralph' again to continue."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 1
