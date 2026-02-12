#!/usr/bin/env bash
# =============================================================================
# helpers.sh — Shared utilities for tmux-fzf-finder
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

# Version comparison — check if running tmux >= target version
tmux_version_at_least() {
    local target="$1"
    local current
    current=$(tmux -V | sed 's/[^0-9.]//g')
    [[ "$(printf '%s\n%s' "$target" "$current" | sort -V | head -n1)" == "$target" ]]
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
