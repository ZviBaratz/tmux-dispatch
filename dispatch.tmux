#!/usr/bin/env bash
# Note: no "set -euo pipefail" — TPM sources this file and strict mode
# can interfere with other plugins or TPM's own error handling.
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

# ─── Cache tool paths in server variables ───────────────────────────────────
# Runs once at plugin load. dispatch.sh reads these instead of re-detecting
# on every popup open. Server variables persist for the tmux server lifetime.
# Underscore prefix (@_dispatch-*) distinguishes from user-facing options.
tmux set -s @_dispatch-fd "$(detect_fd)"
tmux set -s @_dispatch-bat "$(detect_bat)"
tmux set -s @_dispatch-rg "$(detect_rg)"
tmux set -s @_dispatch-zoxide "$(detect_zoxide)"
tmux set -s @_dispatch-fzf-version "$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"

DISPATCH="$CURRENT_DIR/scripts/dispatch.sh"

# ─── Read user configuration ─────────────────────────────────────────────────

find_key=$(get_tmux_option "@dispatch-find-key" "M-o")
grep_key=$(get_tmux_option "@dispatch-grep-key" "M-s")
session_key=$(get_tmux_option "@dispatch-session-key" "M-w")
prefix_key=$(get_tmux_option "@dispatch-prefix-key" "e")
session_prefix_key=$(get_tmux_option "@dispatch-session-prefix-key" "none")
git_key=$(get_tmux_option "@dispatch-git-key" "none")
extract_key=$(get_tmux_option "@dispatch-extract-key" "none")
dirs_key=$(get_tmux_option "@dispatch-dirs-key" "none")
scrollback_key=$(get_tmux_option "@dispatch-scrollback-key" "none")
commands_key=$(get_tmux_option "@dispatch-commands-key" "none")
resume_key=$(get_tmux_option "@dispatch-resume-key" "none")
popup_size=$(get_tmux_option "@dispatch-popup-size" "85%")

# ─── Bind a key to launch finder in a popup or split ─────────────────────────

bind_finder() {
    local key_flag="$1"  # "-n" for prefix-free, "" for prefix
    local key="$2"
    local mode="$3"
    local extra="${4:-}"  # optional extra args (e.g., --view=tokens)
    # display-popup does not expand #{...} formats in -e or the shell-command.
    # run-shell is the only tmux command documented to expand formats before
    # passing to the shell, so we use it to stash the pane ID in a global
    # option, then read it back inside the popup script.
    local cmd="$DISPATCH --mode=$mode${extra:+ $extra}"

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
[[ "$git_key" != "none" ]] && bind_finder "-n" "$git_key" "git"
[[ "$extract_key" != "none" ]] && bind_finder "-n" "$extract_key" "scrollback" "--view=tokens"
[[ "$dirs_key" != "none" ]] && bind_finder "-n" "$dirs_key" "dirs"
[[ "$scrollback_key" != "none" ]] && bind_finder "-n" "$scrollback_key" "scrollback"
[[ "$commands_key" != "none" ]] && bind_finder "-n" "$commands_key" "commands"
[[ "$resume_key" != "none" ]] && bind_finder "-n" "$resume_key" "resume"

# Prefix keybindings for discoverability
[[ "$prefix_key" != "none" ]] && bind_finder "" "$prefix_key" "files"
[[ "$session_prefix_key" != "none" ]] && bind_finder "" "$session_prefix_key" "sessions"

true  # ensure TPM sees exit 0
