#!/usr/bin/env bash
# =============================================================================
# pane-preview.sh — Render a single tmux pane preview for fzf
# =============================================================================
# Shows pane metadata header and live content snapshot.
#
# Usage: pane-preview.sh <pane_id>
# Environment: FZF_PREVIEW_LINES, FZF_PREVIEW_COLUMNS (set by fzf)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

pane_id="${1:-}"

if [[ -z "$pane_id" || ! "$pane_id" =~ ^%[0-9]+$ ]]; then
    echo "  Pane not found"
    exit 0
fi

# Validate pane exists
if ! tmux display-message -t "$pane_id" -p '#{pane_id}' &>/dev/null; then
    echo "  Pane not found: $pane_id"
    exit 0
fi

cols=${FZF_PREVIEW_COLUMNS:-80}
lines=${FZF_PREVIEW_LINES:-30}

# --- Gather pane metadata ---

pane_data=$(tmux display-message -t "$pane_id" -p \
    '#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_current_command}|#{pane_current_path}|#{pane_width}|#{pane_height}|#{pane_active}|#{pane_dead}' 2>/dev/null)

IFS='|' read -r session _ win_name pane_idx command path width height active dead <<< "$pane_data"

# Tilde-collapse path
# shellcheck disable=SC2088
path="${path/#"$HOME"/"~"}"

ref="${session}:${win_name}.${pane_idx}"

# --- Header ---

printf '\033[1;36m ── %s ──\033[0m\n' "$ref"

# Metadata line
meta="${command} · ${width}×${height}"
[[ "$active" == "1" ]] && meta="${meta} · active"
[[ "$dead" == "1" ]] && meta="${meta} · dead"
printf ' \033[38;5;244m%s\033[0m\n' "$path"
printf ' \033[38;5;244m%s\033[0m\n' "$meta"

# --- Pane content ---

content_lines=$((lines - 3))  # minus header (ref + path + meta)
[[ "$content_lines" -lt 1 ]] && content_lines=1

tmux capture-pane -e -J -t "$pane_id" -p 2>/dev/null | \
    perl -CSD -e '
        use strict; use warnings;
        my $W = $ARGV[0];
        my $H = $ARGV[1];
        my @lines = <STDIN>;
        chomp @lines;

        # Strip trailing blank lines (ignore SGR when checking blankness)
        while (@lines) {
            my $vis = $lines[-1];
            $vis =~ s/\033\[[0-9;]*m//g;
            last if $vis =~ /\S/;
            pop @lines;
        }

        # Take last $H lines (bottom of pane where prompts live)
        if (@lines > $H) {
            @lines = @lines[-$H .. -1];
        }

        # Pad to exactly $H lines if fewer exist
        while (@lines < $H) {
            unshift @lines, "";
        }

        for my $line (@lines) {
            # Count visible width and truncate/pad
            my $out = "";
            my $vw = 0;
            my $truncated = 0;

            while ($line =~ /(\033\[[0-9;]*m)|(.)/gs) {
                if (defined $1) {
                    # SGR escape — zero width, always include unless truncated
                    $out .= $1 unless $truncated;
                } else {
                    if ($vw >= $W) {
                        $truncated = 1;
                        next;
                    }
                    if ($vw == $W - 1 && length($line) > pos($line)) {
                        # Check if remaining has visible chars
                        my $rest = substr($line, pos($line));
                        my $vis_rest = $rest;
                        $vis_rest =~ s/\033\[[0-9;]*m//g;
                        if (length($vis_rest) > 0) {
                            $out .= "\x{2026}";  # ellipsis
                            $vw++;
                            $truncated = 1;
                            next;
                        }
                    }
                    $out .= $2;
                    $vw++;
                }
            }

            # Pad short lines with spaces
            if ($vw < $W) {
                $out .= " " x ($W - $vw);
            }
            $out .= "\033[0m";
            print "$out\n";
        }
    ' "$cols" "$content_lines"
