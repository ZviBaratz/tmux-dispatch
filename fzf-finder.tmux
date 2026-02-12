#!/usr/bin/env bash
# =============================================================================
# fzf-finder.tmux — TPM entry point for tmux-fzf-finder
# =============================================================================
# Registers keybindings for file finding and content search popups.
# Reads @finder-* tmux options for configuration.
#
# Install via TPM:
#   set -g @plugin 'ZviBaratz/tmux-fzf-finder'
# =============================================================================

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/scripts/helpers.sh"

FINDER="$CURRENT_DIR/scripts/finder.sh"

# ─── Read user configuration ─────────────────────────────────────────────────

find_key=$(get_tmux_option "@finder-find-key" "M-f")
grep_key=$(get_tmux_option "@finder-grep-key" "M-s")
prefix_key=$(get_tmux_option "@finder-prefix-key" "e")
popup_size=$(get_tmux_option "@finder-popup-size" "85%")

# ─── Bind a key to launch finder in a popup or split ─────────────────────────

bind_finder() {
    local key_flag="$1"  # "-n" for prefix-free, "" for prefix
    local key="$2"
    local mode="$3"
    local cmd="$FINDER --mode=$mode --pane='#{pane_id}'"

    if tmux display-popup -C 2>/dev/null; then
        # tmux 3.2+: floating popup
        if [[ -n "$key_flag" ]]; then
            tmux bind-key "$key_flag" "$key" display-popup -E \
                -w "$popup_size" -h "$popup_size" \
                -d "#{pane_current_path}" "$cmd"
        else
            tmux bind-key "$key" display-popup -E \
                -w "$popup_size" -h "$popup_size" \
                -d "#{pane_current_path}" "$cmd"
        fi
    else
        # tmux < 3.2: split-window fallback
        if [[ -n "$key_flag" ]]; then
            tmux bind-key "$key_flag" "$key" split-window -v -l 80% \
                -c "#{pane_current_path}" "$cmd"
        else
            tmux bind-key "$key" split-window -v -l 80% \
                -c "#{pane_current_path}" "$cmd"
        fi
    fi
}

# ─── Register keybindings ────────────────────────────────────────────────────

# Prefix-free keybindings (skip if set to "none")
[[ "$find_key" != "none" ]] && bind_finder "-n" "$find_key" "files"
[[ "$grep_key" != "none" ]] && bind_finder "-n" "$grep_key" "grep"

# Prefix keybinding for discoverability
[[ "$prefix_key" != "none" ]] && bind_finder "" "$prefix_key" "files"
