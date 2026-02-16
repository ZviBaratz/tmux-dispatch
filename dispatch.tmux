#!/usr/bin/env bash
# =============================================================================
# dispatch.tmux — TPM entry point for tmux-dispatch
# =============================================================================
# Registers keybindings for file finding and content search popups.
# Reads @dispatch-* tmux options for configuration.
#
# Install via TPM:
#   set -g @plugin 'ZviBaratz/tmux-dispatch'
# =============================================================================

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/scripts/helpers.sh"

DISPATCH="$CURRENT_DIR/scripts/dispatch.sh"

# ─── Read user configuration ─────────────────────────────────────────────────

find_key=$(get_tmux_option "@dispatch-find-key" "M-o")
grep_key=$(get_tmux_option "@dispatch-grep-key" "M-s")
session_key=$(get_tmux_option "@dispatch-session-key" "M-w")
prefix_key=$(get_tmux_option "@dispatch-prefix-key" "e")
session_prefix_key=$(get_tmux_option "@dispatch-session-prefix-key" "none")
popup_size=$(get_tmux_option "@dispatch-popup-size" "85%")

# ─── Bind a key to launch finder in a popup or split ─────────────────────────

bind_finder() {
    local key_flag="$1"  # "-n" for prefix-free, "" for prefix
    local key="$2"
    local mode="$3"
    # display-popup does not expand #{...} formats in -e or the shell-command.
    # run-shell is the only tmux command documented to expand formats before
    # passing to the shell, so we use it to stash the pane ID in a global
    # option, then read it back inside the popup script.
    local cmd="$DISPATCH --mode=$mode"

    if tmux_version_at_least "3.2"; then
        # tmux 3.2+: run-shell (foreground) sets the pane ID, then display-popup opens
        tmux bind-key ${key_flag:+"$key_flag"} "$key" \
            run-shell 'tmux set-option -g @dispatch-origin-pane "#{pane_id}"' \\\; \
            display-popup -E \
            -w "$popup_size" -h "$popup_size" \
            -d "#{pane_current_path}" "$cmd"
    else
        # tmux < 3.2: split-window fallback
        tmux bind-key ${key_flag:+"$key_flag"} "$key" \
            run-shell 'tmux set-option -g @dispatch-origin-pane "#{pane_id}"' \\\; \
            split-window -v -l 80% \
            -c "#{pane_current_path}" "$cmd"
    fi
}

# ─── Register keybindings ────────────────────────────────────────────────────

# Prefix-free keybindings (skip if set to "none")
[[ "$find_key" != "none" ]] && bind_finder "-n" "$find_key" "files"
[[ "$grep_key" != "none" ]] && bind_finder "-n" "$grep_key" "grep"
[[ "$session_key" != "none" ]] && bind_finder "-n" "$session_key" "sessions"

# Prefix keybindings for discoverability
[[ "$prefix_key" != "none" ]] && bind_finder "" "$prefix_key" "files"
[[ "$session_prefix_key" != "none" ]] && bind_finder "" "$session_prefix_key" "sessions"

true  # ensure TPM sees exit 0
