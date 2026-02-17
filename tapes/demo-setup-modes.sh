#!/usr/bin/env bash
# ─── Setup for per-mode VHS demo tapes ──────────────────────────────────────
# Extended version of demo-setup.sh with git state, extra sessions, bookmarks,
# and history for mode-specific recordings.
# Run from the repo root: bash tapes/demo-setup-modes.sh
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Use a separate tmux socket so the demo is fully isolated from real sessions
TMUX_SOCKET="demo-vhs"

# Clean previous demo state
tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
command rm -rf /tmp/demo-project

# ─── Sample project ────────────────────────────────────────────────────────

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

# ─── Git state (for git mode demo) ─────────────────────────────────────────

cd /tmp/demo-project
git init -q
git add -A
git commit -q -m "initial commit"

# Modified file (unstaged) — add a new function to utils.sh
cat >> /tmp/demo-project/src/utils.sh << 'CONTENT'

log() { echo "[$(date +%H:%M:%S)] $*"; }
CONTENT

# Staged change — modify deploy.sh and stage it
cat >> /tmp/demo-project/scripts/deploy.sh << 'CONTENT'

echo "Deploy complete."
CONTENT
git add scripts/deploy.sh

# New untracked file
cat > /tmp/demo-project/src/config.sh << 'CONTENT'
#!/usr/bin/env bash
# Application configuration
APP_NAME="demo-app"
APP_PORT=8080
CONTENT

cd "$PLUGIN_DIR"

# ─── Bookmarks ──────────────────────────────────────────────────────────────

bookmark_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-dispatch"
mkdir -p "$bookmark_dir"
printf '%s\t%s\n' "/tmp/demo-project" "src/main.sh" > "$bookmark_dir/bookmarks"

# ─── History / frecency ────────────────────────────────────────────────────

now=$(date +%s)
history_file="$bookmark_dir/history"
# Recent entries — main.sh accessed more frequently for higher frecency score
{
    printf '%s\t%s\t%s\n' "/tmp/demo-project" "src/main.sh" "$((now - 60))"
    printf '%s\t%s\t%s\n' "/tmp/demo-project" "src/main.sh" "$((now - 3600))"
    printf '%s\t%s\t%s\n' "/tmp/demo-project" "src/main.sh" "$((now - 7200))"
    printf '%s\t%s\t%s\n' "/tmp/demo-project" "src/utils.sh" "$((now - 300))"
    printf '%s\t%s\t%s\n' "/tmp/demo-project" "src/utils.sh" "$((now - 1800))"
} > "$history_file"

# ─── tmux sessions ─────────────────────────────────────────────────────────

# Primary demo session
tmux -L "$TMUX_SOCKET" new-session -d -s demo -c /tmp/demo-project

# Load the dispatch plugin
tmux -L "$TMUX_SOCKET" run-shell "$PLUGIN_DIR/dispatch.tmux"

# Force vim for demo (overrides $EDITOR which may be code/VSCode)
tmux -L "$TMUX_SOCKET" set-option -g @dispatch-popup-editor "vim"
tmux -L "$TMUX_SOCKET" set-option -g @dispatch-pane-editor "vim"

# Second session with 4 windows (api-server)
tmux -L "$TMUX_SOCKET" new-session -d -s api-server -c /tmp
tmux -L "$TMUX_SOCKET" send-keys -t api-server "echo 'API server running on :8080'" Enter
tmux -L "$TMUX_SOCKET" new-window -t api-server -n logs
tmux -L "$TMUX_SOCKET" send-keys -t api-server:logs "echo 'Watching logs...'" Enter
tmux -L "$TMUX_SOCKET" new-window -t api-server -n tests
tmux -L "$TMUX_SOCKET" send-keys -t api-server:tests "echo 'Running test suite — 42 passed, 0 failed'" Enter
tmux -L "$TMUX_SOCKET" new-window -t api-server -n db
tmux -L "$TMUX_SOCKET" send-keys -t api-server:db "echo 'PostgreSQL 16.2 — connected to api_dev'" Enter

# Third session with 1 window (frontend)
tmux -L "$TMUX_SOCKET" new-session -d -s frontend -c /tmp
tmux -L "$TMUX_SOCKET" send-keys -t frontend "echo 'Frontend dev server on :3000'" Enter

echo "Demo ready. Attach with: tmux -L $TMUX_SOCKET attach -t demo"
