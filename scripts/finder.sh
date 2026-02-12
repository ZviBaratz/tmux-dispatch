#!/usr/bin/env bash
# =============================================================================
# finder.sh — Unified file finder and content search for tmux popups
# =============================================================================
# Two modes, switchable mid-session via fzf's become action:
#
#   --mode=files  fd/find → fzf (normal filtering, bat preview)
#   --mode=grep   fzf --disabled + change:reload:rg (live search)
#
# Actions (both modes):
#   Enter   — Edit in popup (vim/nvim)
#   Ctrl+O  — Send "$EDITOR [+line] file" to originating pane
#   Ctrl+Y  — Copy file path to system clipboard via tmux
#   Ctrl+G/F — Switch between modes (query preserved)
#
# Usage: finder.sh --mode=files|grep [--pane=ID] [--query=TEXT]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

# ─── Parse arguments ─────────────────────────────────────────────────────────

MODE="files"
PANE_ID=""
QUERY=""

for arg in "$@"; do
    case "$arg" in
        --mode=*)   MODE="${arg#--mode=}" ;;
        --pane=*)   PANE_ID="${arg#--pane=}" ;;
        --query=*)  QUERY="${arg#--query=}" ;;
    esac
done

# ─── Read tmux options ───────────────────────────────────────────────────────

POPUP_EDITOR=$(detect_popup_editor "$(get_tmux_option "@finder-popup-editor" "")")
PANE_EDITOR=$(detect_pane_editor "$(get_tmux_option "@finder-pane-editor" "")")
FD_EXTRA_ARGS=$(get_tmux_option "@finder-fd-args" "")
RG_EXTRA_ARGS=$(get_tmux_option "@finder-rg-args" "")

# ─── Detect tools ────────────────────────────────────────────────────────────

FD_CMD=$(detect_fd)
BAT_CMD=$(detect_bat)
RG_CMD=$(detect_rg)

# ─── Mode: files ─────────────────────────────────────────────────────────────

run_files_mode() {
    # File listing command
    local file_cmd
    if [[ -n "$FD_CMD" ]]; then
        local strip_prefix=""
        $FD_CMD --help 2>&1 | grep -q -- '--strip-cwd-prefix' && strip_prefix="--strip-cwd-prefix"
        file_cmd="$FD_CMD --type f --hidden --follow --exclude .git $strip_prefix $FD_EXTRA_ARGS"
    else
        file_cmd="find . -type f -not -path '*/.git/*'"
    fi

    # Preview command
    local preview_cmd
    if [[ -n "$BAT_CMD" ]]; then
        preview_cmd="$BAT_CMD --color=always --style=numbers --line-range=:500 {}"
    else
        preview_cmd="head -500 {}"
    fi

    # Mode switch binding: Ctrl+G → grep mode
    local become_grep="become('$SCRIPT_DIR/finder.sh' --mode=grep --pane='$PANE_ID' --query=\"{q}\")"

    local result
    result=$(eval "$file_cmd" | fzf \
        --expect=ctrl-o,ctrl-y \
        --multi \
        --query "$QUERY" \
        --preview "$preview_cmd" \
        --preview-window 'right:60%' \
        --header 'Find files │ Enter=edit │ ^O=pane │ ^Y=copy │ Tab=select │ ^G=grep' \
        --border \
        --cycle \
        --bind "ctrl-g:$become_grep" \
        --bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
    ) || exit 0

    handle_file_result "$result"
}

# ─── Mode: grep ──────────────────────────────────────────────────────────────

run_grep_mode() {
    if [[ -z "$RG_CMD" ]]; then
        echo "ripgrep (rg) is required for content search."
        echo "Install: apt install ripgrep  OR  mise use -g ripgrep@latest"
        read -r -p "Press Enter to close..."
        exit 1
    fi

    # Preview command: preview.sh handles bat-or-head fallback internally
    local preview_cmd="'$SCRIPT_DIR/preview.sh' {1} {2}"

    # Mode switch binding: Ctrl+F → files mode
    local become_files="become('$SCRIPT_DIR/finder.sh' --mode=files --pane='$PANE_ID' --query=\"{q}\")"

    # Build rg reload command
    local rg_reload="reload:$RG_CMD --line-number --no-heading --color=always --smart-case $RG_EXTRA_ARGS -- {q} || true"

    # Seed results if we have an initial query from mode switch
    local initial_cmd=":"
    if [[ -n "$QUERY" ]]; then
        initial_cmd="$RG_CMD --line-number --no-heading --color=always --smart-case $RG_EXTRA_ARGS -- $(printf '%q' "$QUERY") || true"
    fi

    local result
    result=$(eval "$initial_cmd" | fzf \
        --expect=ctrl-o,ctrl-y \
        --disabled \
        --query "$QUERY" \
        --ansi \
        --delimiter ':' \
        --bind "change:$rg_reload" \
        --preview "$preview_cmd" \
        --preview-window 'right:60%:+{2}/2' \
        --header 'Live grep │ Enter=edit │ ^O=pane │ ^Y=copy │ ^F=file mode' \
        --border \
        --cycle \
        --bind "ctrl-f:$become_files" \
        --bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
    ) || exit 0

    handle_grep_result "$result"
}

# ─── Result handlers ─────────────────────────────────────────────────────────

handle_file_result() {
    local result="$1"
    local key
    local -a files

    key=$(head -1 <<< "$result")
    mapfile -t files < <(tail -n +2 <<< "$result")
    [[ ${#files[@]} -eq 0 ]] && exit 0

    case "$key" in
        ctrl-y)
            # Copy paths to system clipboard via tmux (newline-separated)
            printf '%s\n' "${files[@]}" | tmux load-buffer -w -
            tmux display-message "Copied ${#files[@]} path(s)"
            ;;
        ctrl-o)
            # Send open command to the originating pane
            if [[ -n "$PANE_ID" ]]; then
                local quoted_files=""
                for f in "${files[@]}"; do
                    quoted_files+=" $(printf '%q' "$f")"
                done
                tmux send-keys -t "$PANE_ID" "$PANE_EDITOR$quoted_files" Enter
            else
                tmux display-message "No target pane available"
            fi
            ;;
        *)
            # Open in popup editor
            exec "$POPUP_EDITOR" "${files[@]}"
            ;;
    esac
}

handle_grep_result() {
    local result="$1"
    local key line file line_num

    key=$(head -1 <<< "$result")
    line=$(tail -1 <<< "$result")
    [[ -z "$line" ]] && exit 0

    # Extract file and line number from rg output (file:line:content)
    file=$(cut -d: -f1 <<< "$line")
    line_num=$(cut -d: -f2 <<< "$line")
    [[ -z "$file" ]] && exit 0

    case "$key" in
        ctrl-y)
            # Copy path to system clipboard via tmux
            echo -n "$file" | tmux load-buffer -w -
            tmux display-message "Copied: $file"
            ;;
        ctrl-o)
            # Send open command to the originating pane (with line number)
            if [[ -n "$PANE_ID" ]]; then
                tmux send-keys -t "$PANE_ID" "$PANE_EDITOR +$line_num $(printf '%q' "$file")" Enter
            else
                tmux display-message "No target pane available"
            fi
            ;;
        *)
            # Open in popup editor at matching line
            exec "$POPUP_EDITOR" "+$line_num" "$file"
            ;;
    esac
}

# ─── Dispatch ────────────────────────────────────────────────────────────────

case "$MODE" in
    files) run_files_mode ;;
    grep)  run_grep_mode ;;
    *)
        echo "Unknown mode: $MODE (expected: files, grep)"
        exit 1
        ;;
esac
