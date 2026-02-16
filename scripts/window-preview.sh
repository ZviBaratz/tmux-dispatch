#!/usr/bin/env bash
# =============================================================================
# window-preview.sh — Render a single window's active pane for fzf preview
# =============================================================================
# Shows a pane content snapshot for the active pane of a given window.
#
# Usage: window-preview.sh <session> <window_index>
# Environment: FZF_PREVIEW_LINES, FZF_PREVIEW_COLUMNS (set by fzf)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

session="$1"
win_idx="${2%%:*}"  # strip trailing colon if present (e.g., "1:" → "1")
cols=${FZF_PREVIEW_COLUMNS:-80}
lines=${FZF_PREVIEW_LINES:-30}

if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "  Session not found: $session"
    exit 0
fi

# Get active pane ID for this window
pid=$(tmux display-message -t "${session}:${win_idx}" -p '#{pane_id}' 2>/dev/null)
if [[ -z "$pid" ]]; then
    echo "  Window not found: ${session}:${win_idx}"
    exit 0
fi

# Get window info
win_info=$(tmux list-windows -t "$session" -F '#{window_index}|#{window_name}|#{window_panes}' 2>/dev/null |
    awk -F'|' -v idx="$win_idx" '$1 == idx { print $2 "|" $3 }')
win_name=$(cut -d'|' -f1 <<< "$win_info")
pane_count=$(cut -d'|' -f2 <<< "$win_info")

# Header
printf "\033[1;36m ── %s:%s %s ──\033[0m \033[38;5;244m%s pane(s)\033[0m\n" \
    "$session" "$win_idx" "$win_name" "${pane_count:-1}"

inner_h=$((lines - 1))
[[ "$inner_h" -lt 1 ]] && inner_h=1

# Capture pane content with ANSI, strip trailing blanks, take bottom lines
tmux capture-pane -e -J -t "$pid" -p 2>/dev/null | \
    perl -CSD -e '
        use strict; use warnings;
        my $W = $ARGV[0];
        my $H = $ARGV[1];
        my @lines = <STDIN>;
        chomp @lines;

        # Strip trailing blank lines
        while (@lines) {
            my $vis = $lines[-1];
            $vis =~ s/\033\[[0-9;]*m//g;
            last if $vis =~ /\S/;
            pop @lines;
        }

        # Take last $H lines
        if (@lines > $H) {
            @lines = @lines[-$H .. -1];
        }

        # Pad to exactly $H lines
        while (@lines < $H) {
            unshift @lines, "";
        }

        for my $line (@lines) {
            my $out = "";
            my $vw = 0;
            my $truncated = 0;

            while ($line =~ /(\033\[[0-9;]*m)|(.)/gs) {
                if (defined $1) {
                    $out .= $1 unless $truncated;
                } else {
                    if ($vw >= $W) {
                        $truncated = 1;
                        next;
                    }
                    $out .= $2;
                    $vw++;
                }
            }
            $out .= "\033[0m";
            print "$out\n";
        }
    ' "$cols" "$inner_h"
