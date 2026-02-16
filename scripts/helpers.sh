#!/usr/bin/env bash
# =============================================================================
# helpers.sh — Shared utilities for tmux-dispatch
# =============================================================================

# ─── PATH augmentation ──────────────────────────────────────────────────────
# tmux's run-shell / display-popup may not inherit the user's login PATH.
# Ensure common tool locations are reachable (idempotent, no duplicates).
_dispatch_augment_path() {
    local -a dirs=(
        /opt/homebrew/bin          # macOS Homebrew (Apple Silicon)
        /usr/local/bin             # macOS Homebrew (Intel) / Linux manual installs
        "$HOME/.local/bin"         # pip, pipx, cargo, etc.
        "$HOME/.cargo/bin"         # Rust / cargo installs
        "$HOME/.nix-profile/bin"   # Nix single-user
        /run/current-system/sw/bin # NixOS system profile
    )
    # mise/asdf shims — only if the shim dir exists
    [[ -d "$HOME/.local/share/mise/shims" ]] && dirs+=("$HOME/.local/share/mise/shims")
    [[ -d "$HOME/.asdf/shims" ]] && dirs+=("$HOME/.asdf/shims")
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] && [[ ":$PATH:" != *":$d:"* ]] && PATH="$PATH:$d"
    done
    export PATH
}
_dispatch_augment_path

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

detect_zoxide() {
    if command -v zoxide &>/dev/null; then echo zoxide; fi
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
        --pointer='▏'
        --border=rounded
        --preview-window='right:60%:border-line'
        --info=hidden
        --no-separator
        --no-scrollbar
        --color='bg+:#1e2030,fg+:#c8d3f5:bold,hl:#82aaff,hl+:#82aaff:bold'
        --color='pointer:#82aaff,border:#2a2f4a,prompt:#82aaff,label:#65719e'
        --color='info:#545a7e,separator:#2a2f4a,scrollbar:#2a2f4a'
        --color='preview-border:#2a2f4a,preview-label:#65719e'
        --color='header:#65719e,gutter:-1'
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
    printf '%s\t%s\t%s\n' "$pwd_dir" "$file_path" "$(date +%s)" >> "$history_file"
    _dispatch_history_trim "$history_file" &
}

# Retrieve files ranked by frecency (frequency + recency), deduped, existence-checked.
# Score formula: sum of 10 / (age_hours + 1) per access.
# Old-format entries (no timestamp) get age_hours=168 (1 week, low score).
recent_files_for_pwd() {
    local pwd_dir="$1" max="${2:-50}"
    local history_file
    history_file=$(_dispatch_history_file)
    [[ -f "$history_file" ]] || return 0
    local count=0
    awk -F'\t' -v pwd="$pwd_dir" -v now="$(date +%s)" '
        $1 == pwd {
            ts = ($3 != "" ? $3 + 0 : now - 604800)
            age_h = (now - ts) / 3600
            if (age_h < 0) age_h = 0
            score[$2] += 10 / (age_h + 1)
        }
        END {
            for (f in score) print score[f], f
        }
    ' "$history_file" | sort -rn | while read -r _score file; do
        [[ -f "$pwd_dir/$file" ]] || continue
        printf '%s\n' "$file"
        ((count++))
        [[ "$count" -ge "$max" ]] && break
    done
    return 0
}

# ─── Bookmarks ────────────────────────────────────────────────────────────

_dispatch_bookmark_file() {
    local dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-dispatch"
    [[ -d "$dir" ]] || mkdir -p "$dir"
    echo "$dir/bookmarks"
}

toggle_bookmark() {
    local pwd_dir="$1" file_path="$2"
    file_path="${file_path#./}"
    local bf
    bf=$(_dispatch_bookmark_file)
    local entry="$pwd_dir"$'\t'"$file_path"
    if grep -qxF "$entry" "$bf" 2>/dev/null; then
        grep -vxF "$entry" "$bf" > "${bf}.tmp" || true
        \mv "${bf}.tmp" "$bf"
        echo "removed"
    else
        printf '%s\n' "$entry" >> "$bf"
        echo "added"
    fi
}

bookmarks_for_pwd() {
    local pwd_dir="$1"
    local bf
    bf=$(_dispatch_bookmark_file)
    [[ -f "$bf" ]] || return 0
    while IFS=$'\t' read -r dir file; do
        [[ "$dir" == "$pwd_dir" ]] || continue
        [[ -f "$pwd_dir/$file" ]] || continue
        printf '%s\n' "$file"
    done < "$bf"
}
