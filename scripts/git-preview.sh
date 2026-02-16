#!/usr/bin/env bash
# =============================================================================
# git-preview.sh — Git diff preview for git mode
# =============================================================================
# Called by fzf as: git-preview.sh <file> <status>
# Shows staged diff for staged files, unstaged diff otherwise.
# Falls back to file content for untracked/clean files.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

FILE="$1"
STATUS="${2:-}"
# fzf passes {1} with ANSI color codes (e.g. \033[32m✚\033[0m) — strip them
# shellcheck disable=SC2001  # ANSI regex requires sed, not ${//}
STATUS=$(sed 's/\x1b\[[0-9;]*m//g' <<< "$STATUS")

[[ -f "$FILE" ]] || { echo "File not found: $FILE"; exit 0; }

BAT_CMD=$(detect_bat)

# Determine which diff to show based on status icon
# Status icons: ✚ (staged), ● (modified), ✹ (both), ? (untracked)
diff_output=""
if [[ "$STATUS" == "✚" ]]; then
    diff_output=$(git diff --cached -- "$FILE" 2>/dev/null)
elif [[ "$STATUS" == "✹" ]]; then
    # Both staged and unstaged — show combined
    diff_output=$(git diff HEAD -- "$FILE" 2>/dev/null)
else
    diff_output=$(git diff -- "$FILE" 2>/dev/null)
fi

# If no diff (untracked/clean), show file content
if [[ -z "$diff_output" ]]; then
    if [[ -n "$BAT_CMD" ]]; then
        "$BAT_CMD" --color=always --style=numbers --line-range=:500 "$FILE"
    else
        head -500 "$FILE"
    fi
else
    if [[ -n "$BAT_CMD" ]]; then
        echo "$diff_output" | "$BAT_CMD" --color=always --language=diff --style=plain
    else
        echo "$diff_output"
    fi
fi
