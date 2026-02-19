#!/usr/bin/env bash
# Note: no "set -euo pipefail" — this file is sourced by other scripts.
# Strict mode is set by the sourcing scripts (dispatch.sh, actions.sh, etc.).
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

# Shared fzf visual options used by all dispatch modes.
# Pass "none" as $1 to skip the built-in color scheme (inherits terminal/FZF_DEFAULT_OPTS colors).
build_fzf_base_opts() {
    local theme="${1:-default}"
    local -a opts=(
        --height=100%
        --layout=reverse
        --highlight-line
        --pointer='▏'
        --border=rounded
        --preview-window='right:60%:border-line'
        --info=inline-right
        --no-separator
        --no-scrollbar
        --bind='ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up'
        --cycle
    )
    if [[ "$theme" != "none" ]]; then
        opts+=(
            --color='bg+:#1e2030,fg+:#c8d3f5:bold,hl:#82aaff,hl+:#82aaff:bold'
            --color='pointer:#82aaff,border:#2a2f4a,prompt:#82aaff,label:#65719e'
            --color='info:#545a7e,separator:#2a2f4a,scrollbar:#2a2f4a'
            --color='preview-border:#2a2f4a,preview-label:#65719e'
            --color='header:#65719e,gutter:-1'
        )
    fi
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
        local tmp
        tmp=$(mktemp "${history_file}.XXXXXX") || return 0
        if tail -n "$keep_lines" "$history_file" > "$tmp"; then
            \mv "$tmp" "$history_file"
        else
            \rm -f "$tmp"
        fi
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
        count=$((count + 1))
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
        local tmp
        tmp=$(mktemp "${bf}.XXXXXX") || return 1
        grep -vxF "$entry" "$bf" > "$tmp" || true
        \mv "$tmp" "$bf"
        echo "removed"
    else
        printf '%s\n' "$entry" >> "$bf"
        echo "added"
    fi
}

# Deduplicate stdin preserving order (safe to call inside bash -c strings)
dedup_lines() { awk '!seen[$0]++'; }

# Escape a value for safe embedding in single-quoted shell strings.
# Replaces each ' with '\'' (end-quote, backslash-quote, start-quote).
# Used to safely embed paths in fzf bind strings: execute('cmd' '$escaped_path')
_sq_escape() { printf '%s' "${1//\'/\'\\\'\'}"; }

# Parse custom token patterns from patterns.conf.
# Input: config file path
# Output: tab-separated lines: type\tcolor_code\tregex\taction
# Skips comments, blank lines, invalid type names, and built-in type names.
# Colors cycle through bright ANSI palette (91-96) to avoid built-in dim colors.
_parse_custom_patterns() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local -a palette=(91 92 93 94 95 96)
    local idx=0
    local line ptype pregex paction rest
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        # Split on " | " (space-pipe-space) — manual split to preserve | in regex
        rest="$line"
        ptype="${rest%% | *}"
        [[ "$ptype" == "$rest" ]] && continue  # no delimiter found
        rest="${rest#* | }"
        # Second field is regex, third (optional) is action
        if [[ "$rest" == *" | "* ]]; then
            pregex="${rest%% | *}"
            paction="${rest#* | }"
        else
            pregex="$rest"
            paction=""
        fi
        # Trim whitespace
        ptype="${ptype#"${ptype%%[![:space:]]*}"}"
        ptype="${ptype%"${ptype##*[![:space:]]}"}"
        pregex="${pregex#"${pregex%%[![:space:]]*}"}"
        pregex="${pregex%"${pregex##*[![:space:]]}"}"
        paction="${paction#"${paction%%[![:space:]]*}"}"
        paction="${paction%"${paction##*[![:space:]]}"}"
        # Validate type name: lowercase, hyphens, digits, max 10 chars
        [[ "$ptype" =~ ^[a-z][a-z0-9-]{0,9}$ ]] || continue
        # Reject built-in type names
        case "$ptype" in url|path|file|hash|ip|uuid|diff) continue ;; esac
        # Skip empty regex
        [[ -z "$pregex" ]] && continue
        # Default action
        [[ -z "$paction" ]] && paction="copy"
        # Assign color from cycling palette
        local color="${palette[$((idx % ${#palette[@]}))]}"
        idx=$((idx + 1))
        printf '%s\t%s\t%s\t%s\n' "$ptype" "$color" "$pregex" "$paction"
    done < "$file"
}

# Display error message to the user via tmux status line
_dispatch_error() { tmux display-message "dispatch: $1"; }

# Read a cached value from a tmux server variable, with fallback to live detection.
# Used by dispatch.sh to avoid re-detecting tools on every popup open.
# Usage: _dispatch_read_cached "@_dispatch-fd" detect_fd
_dispatch_read_cached() {
    local var="$1" fallback_fn="$2"
    local val
    val=$(tmux show -sv "$var" 2>/dev/null) || val=""
    if [[ -n "$val" ]]; then
        echo "$val"
    else
        "$fallback_fn"
    fi
}

# Resolve a path to absolute form, normalizing . and .. components.
# Works even when path components don't yet exist (like GNU realpath -m).
# Falls back to pure bash on macOS where realpath lacks -m.
_resolve_path() {
    local path="$1"
    [[ "$path" != /* ]] && path="$PWD/$path"
    # Try GNU realpath -m first (Linux, macOS with coreutils)
    realpath -m "$path" 2>/dev/null && return 0
    # Fallback: normalize . and .. components with pure bash
    local -a parts=()
    local seg
    IFS='/' read -ra segments <<< "$path"
    for seg in "${segments[@]}"; do
        case "$seg" in
            ''|'.') ;;
            '..') parts=("${parts[@]:0:${#parts[@]}-1}") ;;
            *) parts+=("$seg") ;;
        esac
    done
    printf '/%s\n' "$(IFS='/'; echo "${parts[*]}")"
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

# Return all bookmarks as tilde-collapsed absolute paths, deduped, existence-checked.
all_bookmarks() {
    local bf
    bf=$(_dispatch_bookmark_file)
    [[ -f "$bf" ]] || return 0
    local -A seen=()
    while IFS=$'\t' read -r dir file; do
        local abs="$dir/$file"
        [[ -f "$abs" ]] || continue
        [[ -v "seen[$abs]" ]] && continue
        seen[$abs]=1
        # Tilde-collapse: replace $HOME prefix with ~
        # Note: ~ must be quoted to prevent tilde expansion in replacement
        printf '%s\n' "${abs/#$HOME/"~"}"
    done < "$bf"
}
