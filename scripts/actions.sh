#!/usr/bin/env bash
# =============================================================================
# actions.sh — In-place file & session actions for tmux-dispatch
# =============================================================================
# Called by fzf execute() binds. Runs interactively (has a TTY) and exits
# so fzf can reload() the list afterward.
#
# Usage: actions.sh <action> [args...]
#   edit-file     <editor> <pwd> <history> <file>...  Open files in editor
#   edit-grep     <editor> <pwd> <history> <file> <line>  Open file at line
#   delete-files  <file>...        Delete one or more files (with confirmation)
#   rename-session <session-name>  Rename a tmux session
#   kill-session  <session-name>   Kill a tmux session (guards current)
#   list-sessions                  Print session list for fzf reload
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

# ─── edit-file ───────────────────────────────────────────────────────────────

action_edit_file() {
    local editor="$1"; shift
    local pwd_dir="$1"; shift
    local history_enabled="$1"; shift
    [[ $# -eq 0 ]] && return 0
    if [[ "$history_enabled" == "on" ]]; then
        for f in "$@"; do record_file_open "$pwd_dir" "$f"; done
    fi
    "$editor" "$@"
}

# ─── edit-grep ───────────────────────────────────────────────────────────────

action_edit_grep() {
    local editor="$1" pwd_dir="$2" history_enabled="$3" file="$4" line_num="$5"
    [[ -z "$file" ]] && return 0
    [[ "$line_num" =~ ^[0-9]+$ ]] || line_num=1
    [[ "$history_enabled" == "on" ]] && record_file_open "$pwd_dir" "$file"
    "$editor" "+$line_num" "$file"
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
    command rm -- "${files[@]}"
    printf ' \033[32mDeleted.\033[0m\n'
    sleep 0.3
}

# ─── rename-session ───────────────────────────────────────────────────────────

action_rename_session() {
    local session="$1"
    tmux has-session -t "=$session" 2>/dev/null || {
        echo "Session not found: $session"
        read -r
        exit 1
    }

    printf '\n \033[1mrename session\033[0m \033[90m────────────────\033[0m\n'
    printf ' %s  →\n\n' "$session"
    read -e -r -i "$session" -p " New name: " new_name

    [[ -z "$new_name" || "$new_name" == "$session" ]] && exit 0

    if tmux has-session -t "=$new_name" 2>/dev/null; then
        printf '\n \033[31mSession already exists: %s\033[0m\n' "$new_name"
        read -r -p " Press Enter to cancel..."
        exit 1
    fi

    tmux rename-session -t "=$session" "$new_name"
    printf ' \033[32mRenamed.\033[0m\n'
    sleep 0.3
}

# ─── list-sessions ────────────────────────────────────────────────────────────

action_list_sessions() {
    local now current
    now=$(date +%s)
    current=$(tmux display-message -p '#{session_name}' 2>/dev/null)
    tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}' 2>/dev/null |
    while IFS='|' read -r name wins attached activity; do
        age=$(format_relative_time $((now - activity)))
        meta="\033[90m· ${wins}w · ${age}"
        [ "${attached:-0}" -gt 0 ] && meta="${meta} · attached"
        [[ "$name" == "$current" ]] && meta="${meta} · \033[32mcurrent\033[90m"
        meta="${meta}\033[0m"
        printf '%s\t  %b\n' "$name" "$meta"
    done
}

# ─── rename-preview (for inline rename mode) ────────────────────────────────

action_rename_preview() {
    local original="$1"
    local new_name="$2"

    printf '\n'
    printf '  \033[90m%s\033[0m\n' "$original"
    printf '  ↓\n'
    printf '  \033[1m%s\033[0m\n' "$new_name"
    printf '\n'

    if [[ -z "$new_name" ]]; then
        printf '  \033[90m(empty name)\033[0m\n'
    elif [[ "$new_name" == "$original" ]]; then
        printf '  \033[90m(unchanged)\033[0m\n'
    elif [[ -e "$new_name" ]]; then
        printf '  \033[31m✗ already exists\033[0m\n'
    else
        printf '  \033[32m✓ available\033[0m\n'
        local dir
        dir=$(dirname "$new_name")
        if [[ ! -d "$dir" ]]; then
            printf '  \033[33m(will create %s)\033[0m\n' "$dir/"
        fi
    fi
}

# ─── rename-session-preview (for inline rename mode) ─────────────────────────

action_rename_session_preview() {
    local original="$1"
    local new_name="$2"

    printf '\n'
    printf '  \033[90m%s\033[0m\n' "$original"
    printf '  ↓\n'
    printf '  \033[1m%s\033[0m\n' "$new_name"
    printf '\n'

    if [[ -z "$new_name" ]]; then
        printf '  \033[90m(empty name)\033[0m\n'
    elif [[ "$new_name" == "$original" ]]; then
        printf '  \033[90m(unchanged)\033[0m\n'
    elif tmux has-session -t "=$new_name" 2>/dev/null; then
        printf '  \033[31m✗ session already exists\033[0m\n'
    else
        printf '  \033[32m✓ available\033[0m\n'
    fi
}

# ─── bookmark-toggle ─────────────────────────────────────────────────────────

action_bookmark_toggle() {
    local pwd_dir="$1" file="$2"
    [[ -z "$file" ]] && return 0
    local result
    result=$(toggle_bookmark "$pwd_dir" "$file")
    if [[ "$result" == "added" ]]; then
        tmux display-message "Bookmarked: $file"
    else
        tmux display-message "Unbookmarked: $file"
    fi
}

# ─── kill-session ─────────────────────────────────────────────────────────

action_kill_session() {
    local session="$1"
    [[ -z "$session" ]] && return 0

    # Refuse to kill the current session
    local current
    current=$(tmux display-message -p '#{session_name}' 2>/dev/null)
    if [[ "$session" == "$current" ]]; then
        tmux display-message "Cannot kill current session"
        return 0
    fi

    if tmux has-session -t "=$session" 2>/dev/null; then
        tmux kill-session -t "=$session"
        tmux display-message "Killed session: $session"
    else
        tmux display-message "Session not found: $session"
    fi
}

# ─── git-toggle ──────────────────────────────────────────────────────────────

action_git_toggle() {
    local file="$1"
    [[ -z "$file" ]] && return 0
    # Check if file is staged (index has changes)
    local staged
    staged=$(git diff --cached --name-only -- "$file" 2>/dev/null)
    if [[ -n "$staged" ]]; then
        git restore --staged -- "$file" 2>/dev/null || \
            tmux display-message "git toggle failed for: $file"
    else
        git add -- "$file" 2>/dev/null || \
            tmux display-message "git toggle failed for: $file"
    fi
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────

action="${1:-}"
shift || true

case "$action" in
    edit-file)              action_edit_file "$@" ;;
    edit-grep)              action_edit_grep "$@" ;;
    delete-files)           action_delete_files "$@" ;;
    rename-session)         action_rename_session "$@" ;;
    rename-preview)         action_rename_preview "$@" ;;
    rename-session-preview) action_rename_session_preview "$@" ;;
    list-sessions)          action_list_sessions ;;
    git-toggle)             action_git_toggle "$@" ;;
    kill-session)           action_kill_session "$@" ;;
    bookmark-toggle)        action_bookmark_toggle "$@" ;;
    *)
        echo "Unknown action: $action"
        echo "Usage: actions.sh <action> [args...]"
        exit 1
        ;;
esac
