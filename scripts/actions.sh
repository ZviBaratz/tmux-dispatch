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

# ─── kill-window ─────────────────────────────────────────────────────────

action_kill_window() {
    local session="$1" win_idx="$2"
    [[ -z "$session" || -z "$win_idx" ]] && return 0

    # Strip trailing colon from fzf {1} field (format: "N:")
    win_idx="${win_idx%%:*}"

    # Refuse to kill the last window in a session
    local win_count
    win_count=$(tmux list-windows -t "=$session" 2>/dev/null | wc -l)
    if [[ "$win_count" -le 1 ]]; then
        tmux display-message "Cannot kill last window in session"
        return 0
    fi

    if tmux has-session -t "=$session" 2>/dev/null; then
        tmux kill-window -t "=$session:$win_idx"
        tmux display-message "Killed window: $session:$win_idx"
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

# ─── open-url ────────────────────────────────────────────────────────────────

action_open_url() {
    local url="$1"
    [[ -z "$url" ]] && return 0
    local open_cmd=""
    if [[ -n "${BROWSER:-}" ]]; then
        open_cmd="$BROWSER"
    elif command -v xdg-open &>/dev/null; then
        open_cmd="xdg-open"
    elif command -v open &>/dev/null; then
        open_cmd="open"
    fi
    if [[ -n "$open_cmd" ]]; then
        tmux run-shell -b "$open_cmd $(printf '%q' "$url") >/dev/null 2>&1"
        tmux display-message "Opened: ${url//#/##}"
    else
        printf '%s' "$url" | tmux load-buffer -w -
        tmux display-message "No browser found — copied URL"
    fi
}

# ─── smart-open ───────────────────────────────────────────────────────────

action_smart_open() {
    local type="$1" token="$2" pane_id="${3:-}" pane_editor="${4:-}" patterns_file="${5:-}"
    [[ -z "$token" ]] && return 0
    case "$type" in
        url)  action_open_url "$token" ;;
        path|diff|file)
            local file="${token%%:*}"
            local line_num="${token#*:}"; line_num="${line_num%%:*}"
            [[ "$line_num" =~ ^[0-9]+$ ]] || line_num=1
            if [[ -n "$pane_id" && -n "$pane_editor" ]]; then
                tmux send-keys -t "$pane_id" "$pane_editor +$line_num $(printf '%q' "$file")" Enter
                tmux display-message "Opened: $file:$line_num"
            else
                printf '%s' "$token" | tmux load-buffer -w -
                tmux display-message "No editor target — copied: $token"
            fi
            ;;
        hash)
            if git rev-parse --is-inside-work-tree &>/dev/null \
               && git cat-file -t "$token" &>/dev/null; then
                if [[ -n "$pane_id" ]]; then
                    tmux send-keys -t "$pane_id" "git show $token" Enter
                    tmux display-message "Showing: ${token:0:8}..."
                else
                    printf '%s' "$token" | tmux load-buffer -w -
                    tmux display-message "Copied: $token"
                fi
            else
                printf '%s' "$token" | tmux load-buffer -w -
                tmux display-message "Copied: $token"
            fi
            ;;
        *)
            # Look up custom action from patterns.conf
            local custom_action=""
            if [[ -n "${patterns_file:-}" && -f "$patterns_file" ]]; then
                while IFS=$'\t' read -r ptype _pcolor _pregex paction; do
                    if [[ "$ptype" == "$type" ]]; then
                        custom_action="$paction"; break
                    fi
                done < <(_parse_custom_patterns "$patterns_file")
            fi
            case "$custom_action" in
                open-url\ *)
                    local url="${custom_action#open-url }"
                    url="${url//\{\}/$token}"
                    action_open_url "$url"
                    ;;
                send\ *)
                    local cmd="${custom_action#send }"
                    cmd="${cmd//\{\}/$token}"
                    if [[ -n "$pane_id" ]]; then
                        tmux send-keys -t "$pane_id" "$cmd" Enter
                        tmux display-message "Sent: ${cmd:0:40}"
                    else
                        printf '%s' "$token" | tmux load-buffer -w -
                        tmux display-message "No pane — copied: $token"
                    fi
                    ;;
                *)
                    printf '%s' "$token" | tmux load-buffer -w -
                    tmux display-message "Copied: $token"
                    ;;
            esac
            ;;
    esac
}

# ─── bookmark-remove ─────────────────────────────────────────────────────

action_bookmark_remove() {
    local abs_path="$1"
    [[ -z "$abs_path" ]] && return 0
    # Expand tilde
    abs_path="${abs_path/#\~/$HOME}"
    local bf
    bf=$(_dispatch_bookmark_file)
    [[ -f "$bf" ]] || return 0
    local tmp
    tmp=$(mktemp "${bf}.XXXXXX") || return 1
    # Remove any entry whose dir/file resolves to this absolute path
    while IFS=$'\t' read -r dir file; do
        [[ "$dir/$file" == "$abs_path" ]] && continue
        printf '%s\t%s\n' "$dir" "$file"
    done < "$bf" > "$tmp"
    \mv "$tmp" "$bf"
    tmux display-message "Unbookmarked: ${abs_path/#$HOME/\~}"
}

# ─── list-panes ──────────────────────────────────────────────────────────────

action_list_panes() {
    local current_pane="${1:-}"
    tmux list-panes -a -F '#{pane_id}|#{session_name}|#{window_index}|#{pane_index}|#{pane_current_command}|#{pane_current_path}|#{pane_active}|#{window_active}|#{pane_width}|#{pane_height}|#{pane_dead}|#{window_name}' 2>/dev/null |
    while IFS='|' read -r pid session _ pane_idx command path active win_active width height dead win_name; do
        # shellcheck disable=SC2088
        local short_path="${path/#"$HOME"/"~"}"
        local ref="${session}:${win_name}.${pane_idx}"
        local meta="\033[90m${command} · ${width}×${height}\033[0m"

        # Indicators
        local indicators=""
        if [[ "$pid" == "$current_pane" ]]; then
            indicators=" \033[32m(current)\033[0m"
        elif [[ "$active" == "1" && "$win_active" == "1" ]]; then
            indicators=" \033[33m*\033[0m"
        fi
        [[ "$dead" == "1" ]] && indicators="${indicators} \033[31m(dead)\033[0m"

        printf '%s\t  %s  %s  %b%b\n' "$pid" "$ref" "$short_path" "$meta" "$indicators"
    done
}

# ─── kill-pane ───────────────────────────────────────────────────────────────

action_kill_pane() {
    local current_pane="${1:-}"
    local target_pane="${2:-}"
    [[ -z "$target_pane" ]] && return 0

    # Refuse to kill origin pane
    if [[ "$target_pane" == "$current_pane" ]]; then
        tmux display-message "Cannot kill current pane"
        return 0
    fi

    # Verify pane exists
    if ! tmux display-message -t "$target_pane" -p '#{pane_id}' &>/dev/null; then
        tmux display-message "Pane not found: $target_pane"
        return 0
    fi

    tmux kill-pane -t "$target_pane"
    tmux display-message "Killed pane: $target_pane"
}

# ─── join-pane ───────────────────────────────────────────────────────────────

action_join_pane() {
    local current_pane="${1:-}"
    local target_pane="${2:-}"
    [[ -z "$target_pane" ]] && return 0

    # Refuse self-join
    if [[ "$target_pane" == "$current_pane" ]]; then
        tmux display-message "Cannot join pane to itself"
        return 0
    fi

    if ! tmux join-pane -s "$target_pane" -t "$current_pane" 2>/dev/null; then
        tmux display-message "Cannot move pane (may be only pane in window)"
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
    kill-window)            action_kill_window "$@" ;;
    open-url)               action_open_url "$@" ;;
    smart-open)             action_smart_open "$@" ;;
    bookmark-toggle)        action_bookmark_toggle "$@" ;;
    bookmark-remove)        action_bookmark_remove "$@" ;;
    list-panes)             action_list_panes "$@" ;;
    kill-pane)              action_kill_pane "$@" ;;
    join-pane)              action_join_pane "$@" ;;
    *)
        echo "Unknown action: $action"
        echo "Usage: actions.sh <action> [args...]"
        exit 1
        ;;
esac
