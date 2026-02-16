#!/usr/bin/env bash
# ─── Setup for demo.tape ─────────────────────────────────────────────────────
# Creates sample project + tmux sessions for the VHS recording.
# Run from the repo root: bash demo-setup.sh
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use a separate tmux socket so the demo is fully isolated from real sessions
TMUX_SOCKET="demo-vhs"

# Clean previous demo state
tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
command rm -rf /tmp/demo-project

# ─── Sample project ──────────────────────────────────────────────────────────

mkdir -p /tmp/demo-project/{src,tests,docs,scripts}

cat > /tmp/demo-project/src/main.sh << 'CONTENT'
#!/usr/bin/env bash
# Main entry point for the application
source ./src/utils.sh

main() {
    local name="${1:-world}"
    echo "$(greet "$name") — running v$(version)"
}

main "$@"
CONTENT

cat > /tmp/demo-project/src/utils.sh << 'CONTENT'
#!/usr/bin/env bash
# Shared utility functions

greet() { echo "Hello, $1!"; }
version() { echo "1.2.0"; }
CONTENT

cat > /tmp/demo-project/tests/test_main.sh << 'CONTENT'
#!/usr/bin/env bash
# Test suite for main.sh
source ./src/utils.sh

test_greet() {
    result="$(greet 'Alice')"
    [ "$result" = "Hello, Alice!" ] && echo 'PASS: greet' || echo 'FAIL: greet'
}

test_greet
CONTENT

cat > /tmp/demo-project/docs/README.md << 'CONTENT'
# Demo Project

A sample project to demonstrate **tmux-dispatch**.

## Usage

Run `./src/main.sh` to greet the world.
CONTENT

cat > /tmp/demo-project/scripts/deploy.sh << 'CONTENT'
#!/usr/bin/env bash
set -euo pipefail
echo "Deploying version $(cat VERSION)..."
echo "Hello from deploy script"
CONTENT

echo '1.2.0' > /tmp/demo-project/VERSION

# ─── tmux sessions ───────────────────────────────────────────────────────────

# Primary demo session
tmux -L "$TMUX_SOCKET" new-session -d -s demo -c /tmp/demo-project
tmux -L "$TMUX_SOCKET" run-shell "$PLUGIN_DIR/dispatch.tmux"

# Force vim for demo (overrides $EDITOR which may be code/VSCode)
tmux -L "$TMUX_SOCKET" set-option -g @dispatch-popup-editor "vim"
tmux -L "$TMUX_SOCKET" set-option -g @dispatch-pane-editor "vim"

# Second session with 2 windows (makes session preview grid interesting)
tmux -L "$TMUX_SOCKET" new-session -d -s api-server -c /tmp
tmux -L "$TMUX_SOCKET" send-keys -t api-server "echo 'API server running on :8080'" Enter
tmux -L "$TMUX_SOCKET" new-window -t api-server -n logs
tmux -L "$TMUX_SOCKET" send-keys -t api-server:logs "echo 'Watching logs...'" Enter

echo "Demo ready. Attach with: tmux -L $TMUX_SOCKET attach -t demo"
