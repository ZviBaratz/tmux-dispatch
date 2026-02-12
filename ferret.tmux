#!/usr/bin/env bash
# =============================================================================
# ferret.tmux — TPM entry point for tmux-ferret
# =============================================================================
# Registers keybindings for file finding and content search popups.
# Reads @ferret-* tmux options for configuration.
#
# Install via TPM:
#   set -g @plugin 'ZviBaratz/tmux-ferret'
# =============================================================================

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/scripts/helpers.sh"

FERRET="$CURRENT_DIR/scripts/ferret.sh"

# ─── Read user configuration ─────────────────────────────────────────────────

find_key=$(get_tmux_option "@ferret-find-key" "M-f")
grep_key=$(get_tmux_option "@ferret-grep-key" "M-s")
prefix_key=$(get_tmux_option "@ferret-prefix-key" "e")
popup_size=$(get_tmux_option "@ferret-popup-size" "85%")

# ─── Bind a key to launch finder in a popup or split ─────────────────────────

bind_finder() {
    local key_flag="$1"  # "-n" for prefix-free, "" for prefix
    local key="$2"
    local mode="$3"
    local cmd="$FERRET --mode=$mode --pane='#{pane_id}'"

    if tmux_version_at_least "3.2"; then
        # tmux 3.2+: floating popup
        tmux bind-key ${key_flag:+"$key_flag"} "$key" display-popup -E \
            -w "$popup_size" -h "$popup_size" \
            -d "#{pane_current_path}" "$cmd"
    else
        # tmux < 3.2: split-window fallback
        tmux bind-key ${key_flag:+"$key_flag"} "$key" split-window -v -l 80% \
            -c "#{pane_current_path}" "$cmd"
    fi
}

# ─── Register keybindings ────────────────────────────────────────────────────

# Prefix-free keybindings (skip if set to "none")
[[ "$find_key" != "none" ]] && bind_finder "-n" "$find_key" "files"
[[ "$grep_key" != "none" ]] && bind_finder "-n" "$grep_key" "grep"

# Prefix keybinding for discoverability
[[ "$prefix_key" != "none" ]] && bind_finder "" "$prefix_key" "files"
