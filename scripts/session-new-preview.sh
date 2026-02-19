#!/usr/bin/env bash
# =============================================================================
# session-new-preview.sh — Git-aware preview for session-new mode
# =============================================================================
# Called by fzf as: session-new-preview.sh <path>
# For git repos: shows branch, tracking info, dirty files, recent commits.
# For non-git dirs: shows tree or ls listing.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

DIR="$1"
[[ -d "$DIR" ]] || { echo "Directory not found: $DIR"; exit 0; }

# ─── Git repo preview ─────────────────────────────────────────────────────
if [[ -d "$DIR/.git" ]] || git -C "$DIR" rev-parse --is-inside-work-tree &>/dev/null; then

    # Branch + tracking info
    branch=$(git -C "$DIR" symbolic-ref --short HEAD 2>/dev/null) || \
        branch=$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null) || \
        branch="unknown"

    tracking=""
    upstream=$(git -C "$DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || true
    if [[ -n "$upstream" ]]; then
        ahead=$(git -C "$DIR" rev-list --count '@{upstream}..HEAD' 2>/dev/null) || ahead=0
        behind=$(git -C "$DIR" rev-list --count 'HEAD..@{upstream}' 2>/dev/null) || behind=0
        if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
            tracking="  ↑${ahead} ↓${behind}"
        elif [[ "$ahead" -gt 0 ]]; then
            tracking="  ↑${ahead}"
        elif [[ "$behind" -gt 0 ]]; then
            tracking="  ↓${behind}"
        fi
    fi

    printf '\033[1;36m⎇ %s\033[0m\033[38;5;244m%s\033[0m\n' "$branch" "$tracking"
    echo ""

    # Dirty file count + first 5 dirty files
    status_output=$(git -C "$DIR" status --porcelain 2>/dev/null) || true
    if [[ -n "$status_output" ]]; then
        dirty_count=$(printf '%s\n' "$status_output" | wc -l)
        dirty_count=$((dirty_count))  # trim whitespace from wc
        printf '\033[33m%d changed file%s:\033[0m\n' "$dirty_count" "$( [[ "$dirty_count" -eq 1 ]] && echo "" || echo "s" )"
        printf '%s\n' "$status_output" | head -5 | while IFS= read -r line; do
            printf '  %s\n' "$line"
        done
        if [[ "$dirty_count" -gt 5 ]]; then
            printf '  \033[38;5;244m… and %d more\033[0m\n' "$((dirty_count - 5))"
        fi
    else
        printf '\033[32mclean working tree\033[0m\n'
    fi
    echo ""

    # Recent commits
    printf '\033[1mRecent commits:\033[0m\n'
    git -C "$DIR" log --oneline --decorate --color=always -10 2>/dev/null || \
        echo "  (no commits yet)"

    exit 0
fi

# ─── Non-git directory preview ─────────────────────────────────────────────
if command -v tree &>/dev/null; then
    tree -C -L 2 "$DIR"
elif ls --color=always /dev/null 2>/dev/null; then
    ls -la --color=always "$DIR"
else
    ls -laG "$DIR"
fi
