#!/usr/bin/env bash
# =============================================================================
# actions.sh — In-place file & session actions for tmux-dispatch
# =============================================================================
# Called by fzf execute() binds. Runs interactively (has a TTY) and exits
# so fzf can reload() the list afterward.
#
# Usage: actions.sh <action> [args...]
#   rename-file   <filepath>       Rename a single file
#   delete-files  <file>...        Delete one or more files (with confirmation)
#   rename-session <session-name>  Rename a tmux session
#   list-sessions                  Print session list for fzf reload
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

# ─── rename-file ──────────────────────────────────────────────────────────────

action_rename_file() {
    local file="$1"
    [[ -f "$file" ]] || { echo "File not found: $file"; read -r; exit 1; }

    printf '\n \033[1mrename\033[0m \033[90m─────────────────────\033[0m\n'
    printf ' %s  →\n\n' "$file"
    read -e -r -i "$file" -p " New name: " new_name

    [[ -z "$new_name" || "$new_name" == "$file" ]] && exit 0

    if [[ -e "$new_name" ]]; then
        printf '\n \033[31mAlready exists: %s\033[0m\n' "$new_name"
        read -r -p " Press Enter to cancel..."
        exit 1
    fi

    local dir
    dir=$(dirname "$new_name")
    [[ -d "$dir" ]] || mkdir -p "$dir"
    mv "$file" "$new_name"
    printf ' \033[32mRenamed.\033[0m\n'
    sleep 0.3
}

# ─── delete-files ─────────────────────────────────────────────────────────────

action_delete_files() {
    local files=("$@")
    [[ ${#files[@]} -eq 0 ]] && exit 0

    printf '\n \033[1mdelete\033[0m \033[90m─────────────────────\033[0m\n'
    for f in "${files[@]}"; do printf '   %s\n' "$f"; done
    printf '\n Delete %d file(s)? [y/N]: ' "${#files[@]}"
    read -r ans

    [[ "$ans" == [yY] ]] || exit 0
    rm "${files[@]}"
    printf ' \033[32mDeleted.\033[0m\n'
    sleep 0.3
}

# ─── rename-session ───────────────────────────────────────────────────────────

action_rename_session() {
    local session="$1"
    tmux has-session -t "$session" 2>/dev/null || {
        echo "Session not found: $session"
        read -r
        exit 1
    }

    printf '\n \033[1mrename session\033[0m \033[90m────────────────\033[0m\n'
    printf ' %s  →\n\n' "$session"
    read -e -r -i "$session" -p " New name: " new_name

    [[ -z "$new_name" || "$new_name" == "$session" ]] && exit 0

    if tmux has-session -t "$new_name" 2>/dev/null; then
        printf '\n \033[31mSession already exists: %s\033[0m\n' "$new_name"
        read -r -p " Press Enter to cancel..."
        exit 1
    fi

    tmux rename-session -t "$session" "$new_name"
    printf ' \033[32mRenamed.\033[0m\n'
    sleep 0.3
}

# ─── list-sessions ────────────────────────────────────────────────────────────

action_list_sessions() {
    local now
    now=$(date +%s)
    tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}' 2>/dev/null |
    while IFS='|' read -r name wins attached activity; do
        age=$(format_relative_time $((now - activity)))
        meta="\033[90m· ${wins}w · ${age}"
        [ "${attached:-0}" -gt 0 ] && meta="${meta} · attached"
        meta="${meta}\033[0m"
        printf '%s\t  %s %b\n' "$name" "$name" "$meta"
    done
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────

action="${1:-}"
shift || true

case "$action" in
    rename-file)     action_rename_file "$@" ;;
    delete-files)    action_delete_files "$@" ;;
    rename-session)  action_rename_session "$@" ;;
    list-sessions)   action_list_sessions ;;
    *)
        echo "Unknown action: $action"
        echo "Usage: actions.sh <rename-file|delete-files|rename-session|list-sessions> [args...]"
        exit 1
        ;;
esac
