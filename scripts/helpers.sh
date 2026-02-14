#!/usr/bin/env bash
# =============================================================================
# helpers.sh — Shared utilities for tmux-dispatch
# =============================================================================

# Read a tmux option with fallback to default
get_tmux_option() {
    local option="$1" default="$2"
    local value
    value=$(tmux show-option -gqv "$option")
    echo "${value:-$default}"
}

# Tool detection — handles Debian/Ubuntu renamed binaries
detect_fd() {
    if command -v fd &>/dev/null; then
        echo fd
    elif command -v fdfind &>/dev/null; then
        echo fdfind
    fi
}

detect_bat() {
    if command -v bat &>/dev/null; then
        echo bat
    elif command -v batcat &>/dev/null; then
        echo batcat
    fi
}

detect_rg() {
    if command -v rg &>/dev/null; then
        echo rg
    fi
}

# Detect best available popup editor (terminal-only)
detect_popup_editor() {
    local configured="$1"
    if [[ -n "$configured" ]]; then
        echo "$configured"
    elif command -v nvim &>/dev/null; then
        echo nvim
    elif command -v vim &>/dev/null; then
        echo vim
    else
        echo vi
    fi
}

# Format epoch diff as relative time (e.g., "2s", "5m", "3h", "1d", "2w")
format_relative_time() {
    local diff="$1"
    if [ "$diff" -lt 60 ]; then
        echo "${diff}s"
    elif [ "$diff" -lt 3600 ]; then
        echo "$((diff / 60))m"
    elif [ "$diff" -lt 86400 ]; then
        echo "$((diff / 3600))h"
    elif [ "$diff" -lt 604800 ]; then
        echo "$((diff / 86400))d"
    else
        echo "$((diff / 604800))w"
    fi
}

# Version comparison — check if running tmux >= target version
tmux_version_at_least() {
    local target="$1"
    local current
    current=$(tmux -V | sed 's/[^0-9.]//g')
    # Dev/master builds produce empty or malformed versions — assume old tmux (safe fallback)
    [[ "$current" =~ ^[0-9]+\. ]] || return 1
    [[ "$(printf '%s\n%s' "$target" "$current" | sort -V | head -n1)" == "$target" ]]
}

# Shared fzf visual options used by all dispatch modes
build_fzf_base_opts() {
    local -a opts=(
        --height=100%
        --layout=reverse
        --highlight-line
        --pointer='▸'
        --border=rounded
        --preview-window='right:60%:border-left'
        --preview-label=' Preview '
        --color='bg+:236,fg+:39:bold,pointer:39,border:244,prompt:39,label:39:bold'
        --bind='ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up'
        --cycle
    )
    printf '%s\n' "${opts[@]}"
}

# Detect editor for send-to-pane (can be GUI)
detect_pane_editor() {
    local configured="$1"
    if [[ -n "$configured" ]]; then
        echo "$configured"
    elif [[ -n "${EDITOR:-}" ]]; then
        echo "$EDITOR"
    elif command -v nvim &>/dev/null; then
        echo nvim
    elif command -v vim &>/dev/null; then
        echo vim
    else
        echo vi
    fi
}

# ─── File history ──────────────────────────────────────────────────────────

# Portable reverse-file (tac on Linux, tail -r on macOS)
_dispatch_tac() {
    if command -v tac &>/dev/null; then tac "$@"; else tail -r "$@"; fi
}

# Returns history file path, creates dir if needed
_dispatch_history_file() {
    local dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-dispatch"
    [[ -d "$dir" ]] || mkdir -p "$dir"
    echo "$dir/history"
}

# Background maintenance — trims to 1000 lines when exceeding 2000
_dispatch_history_trim() {
    local history_file="$1" max_lines=2000 keep_lines=1000
    local count
    count=$(wc -l < "$history_file" 2>/dev/null) || return 0
    if [[ "$count" -gt "$max_lines" ]]; then
        local tmp="${history_file}.tmp.$$"
        tail -n "$keep_lines" "$history_file" > "$tmp" && \mv "$tmp" "$history_file"
    fi
}

# Append entry + async trim
record_file_open() {
    local pwd_dir="$1" file_path="$2"
    file_path="${file_path#./}"  # normalize find's ./ prefix
    local history_file
    history_file=$(_dispatch_history_file)
    printf '%s\t%s\n' "$pwd_dir" "$file_path" >> "$history_file"
    _dispatch_history_trim "$history_file" &
}

# Retrieve recent files (newest first, deduped, existence-checked)
recent_files_for_pwd() {
    local pwd_dir="$1" max="${2:-50}"
    local history_file
    history_file=$(_dispatch_history_file)
    [[ -f "$history_file" ]] || return 0
    local count=0
    declare -A seen
    while IFS=$'\t' read -r dir file; do
        [[ "$dir" == "$pwd_dir" ]] || continue
        [[ -n "${seen[$file]+x}" ]] && continue
        seen[$file]=1
        [[ -f "$pwd_dir/$file" ]] || continue
        printf '%s\n' "$file"
        ((count++))
        [[ "$count" -ge "$max" ]] && break
    done < <(_dispatch_tac "$history_file")
    return 0
}
