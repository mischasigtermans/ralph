#!/bin/bash
# Ralph installer - sets up the bash script and prompt file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"

echo "Ralph Installer"
echo "==============="
echo ""

# Create directory if needed
mkdir -p "$INSTALL_DIR"

# Symlink ralph script (remove existing first)
echo "→ Linking ralph to $INSTALL_DIR/"
rm -f "$INSTALL_DIR/ralph"
ln -s "$SCRIPT_DIR/ralph.sh" "$INSTALL_DIR/ralph"

echo ""
echo "✓ Installation complete!"
echo ""

# Check if install dir is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "⚠ $INSTALL_DIR is not in your PATH"
    echo ""
    echo "Add this line to your shell config (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
    echo "Then restart your terminal or run: source ~/.zshrc"
else
    echo "You can now use 'ralph' from any directory."
fi

echo ""
echo "Usage:"
echo "  1. Run '/ralph' in Claude Code to set up your project"
echo "  2. Run 'ralph' or 'ralph 10' from terminal to start the loop"
