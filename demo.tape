# VHS recording script for tmux-dispatch demo
# Run with: vhs demo.tape
# Produces: demo.gif
# Requires: vhs (https://github.com/charmbracelet/vhs), tmux, fzf, fd, bat, rg

Output assets/demo.gif
Set Shell bash
Set FontSize 14
Set Width 1200
Set Height 700
Set Padding 10

# ─── Set up a sample project with colorful content ──────────────────────────

Type "mkdir -p /tmp/demo-project/src /tmp/demo-project/tests /tmp/demo-project/docs /tmp/demo-project/scripts"
Enter
Sleep 300ms

# Create files with enough content for bat to syntax-highlight
Type@0 "cat > /tmp/demo-project/src/main.sh << 'EOF'"
Enter
Type@0 "#!/usr/bin/env bash"
Enter
Type@0 "# Main entry point for the application"
Enter
Type@0 "source ./src/utils.sh"
Enter
Type@0 ""
Enter
Type@0 "main() {"
Enter
Type@0 "    local name=\"\${1:-world}\""
Enter
Type@0 "    echo \"$(greet \"$name\") — running v$(version)\""
Enter
Type@0 "}"
Enter
Type@0 ""
Enter
Type@0 "main \"\$@\""
Enter
Type@0 "EOF"
Enter
Sleep 200ms

Type@0 "cat > /tmp/demo-project/src/utils.sh << 'EOF'"
Enter
Type@0 "#!/usr/bin/env bash"
Enter
Type@0 "# Shared utility functions"
Enter
Type@0 ""
Enter
Type@0 "greet() { echo \"Hello, \$1!\"; }"
Enter
Type@0 "version() { echo \"1.2.0\"; }"
Enter
Type@0 "EOF"
Enter
Sleep 200ms

Type@0 "cat > /tmp/demo-project/tests/test_main.sh << 'EOF'"
Enter
Type@0 "#!/usr/bin/env bash"
Enter
Type@0 "# Test suite for main.sh"
Enter
Type@0 "source ./src/utils.sh"
Enter
Type@0 ""
Enter
Type@0 "test_greet() {"
Enter
Type@0 "    result=\"$(greet 'Alice')\""
Enter
Type@0 "    [ \"$result\" = \"Hello, Alice!\" ] && echo 'PASS: greet' || echo 'FAIL: greet'"
Enter
Type@0 "}"
Enter
Type@0 ""
Enter
Type@0 "test_greet"
Enter
Type@0 "EOF"
Enter
Sleep 200ms

Type@0 "cat > /tmp/demo-project/docs/README.md << 'EOF'"
Enter
Type@0 "# Demo Project"
Enter
Type@0 ""
Enter
Type@0 "A sample project to demonstrate **tmux-dispatch**."
Enter
Type@0 ""
Enter
Type@0 "## Usage"
Enter
Type@0 ""
Enter
Type@0 "Run \`./src/main.sh\` to greet the world."
Enter
Type@0 "EOF"
Enter
Sleep 200ms

Type@0 "cat > /tmp/demo-project/scripts/deploy.sh << 'EOF'"
Enter
Type@0 "#!/usr/bin/env bash"
Enter
Type@0 "set -euo pipefail"
Enter
Type@0 "echo \"Deploying version $(cat VERSION)...\""
Enter
Type@0 "echo \"Hello from deploy script\""
Enter
Type@0 "EOF"
Enter
Sleep 200ms

Type@0 "echo '1.2.0' > /tmp/demo-project/VERSION"
Enter
Sleep 200ms

# ─── Start tmux and load the plugin ─────────────────────────────────────────

# Get the plugin directory (where demo.tape lives)
Type "PLUGIN_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]:-$0}\")\" && pwd)\""
Enter
Sleep 200ms
Type "cd /tmp/demo-project && tmux new-session -d -s demo"
Enter
Sleep 500ms
Type "tmux run-shell \"$PLUGIN_DIR/dispatch.tmux\" && tmux attach -t demo"
Enter
Sleep 1.5s
Type "clear"
Enter
Sleep 1s

# ─── 1. File finder — welcome cheat sheet ───────────────────────────────────

# Open file finder with Alt+O
Alt+o
Sleep 2.5s

# ─── 2. Type to filter files (bat preview appears) ─────────────────────────

Type@150ms "main"
Sleep 2s

# ─── 3. Switch to grep mode with > prefix ──────────────────────────────────

# Clear the query first, then type > to switch modes
Ctrl+u
Sleep 500ms
Type@150ms ">greet"
Sleep 2.5s

# ─── 4. Show grep results ──────────────────────────────────────────────────

# Clear and try another search
Ctrl+u
Sleep 300ms
Type@150ms "Hello"
Sleep 2s

# ─── 5. Return to files via backspace on empty ─────────────────────────────

Ctrl+u
Sleep 300ms
Backspace
Sleep 2s

# ─── 6. Switch to sessions with @ prefix ───────────────────────────────────

Type@150ms "@"
Sleep 2s

# ─── 7. Close ──────────────────────────────────────────────────────────────

Escape
Sleep 1s

# ─── Clean up ───────────────────────────────────────────────────────────────

Type "exit"
Enter
Sleep 500ms
Type "tmux kill-session -t demo 2>/dev/null; rm -rf /tmp/demo-project"
Enter
