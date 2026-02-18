#!/usr/bin/env bash
# =============================================================================
# preview.sh — Preview dispatcher for grep mode
# =============================================================================
# Called by fzf as: preview.sh <file> <line>
# Shows file content with the matching line highlighted.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

FILE="$1"
LINE="${2:-1}"
[[ "$LINE" =~ ^[0-9]+$ ]] || LINE=1
(( LINE > 100000 )) && LINE=100000

[[ -f "$FILE" ]] || { echo "File not found: $FILE"; exit 0; }

BAT_CMD=$(_dispatch_read_cached "@_dispatch-bat" detect_bat)

if [[ -n "$BAT_CMD" ]]; then
    "$BAT_CMD" --color=always --style=numbers --highlight-line "$LINE" "$FILE"
else
    # Fallback: show region around the matching line
    head -n $((LINE + 50)) "$FILE" | tail -n 100
fi
