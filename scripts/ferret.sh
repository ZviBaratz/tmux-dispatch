#!/usr/bin/env bash
# =============================================================================
# ferret.sh — Unified file finder, content search, and session picker
# =============================================================================
# Four modes, switchable mid-session via fzf's become action:
#
#   --mode=files       fd/find → fzf (normal filtering, bat preview)
#   --mode=grep        fzf --disabled + change:reload:rg (live search)
#   --mode=sessions    tmux session picker/creator
#   --mode=session-new directory-based session creation
#
# Mode switching (VSCode command palette style):
#   Files is the home mode. Prefixes step into sub-modes:
#   > prefix   — Files → grep (remainder becomes query)
#   @ prefix   — Files → sessions (remainder becomes query)
#   ⌫ on empty — Grep/sessions → files (return to home)
#
# Usage: ferret.sh --mode=files|grep|sessions|session-new [--pane=ID] [--query=TEXT]
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

POPUP_EDITOR=$(detect_popup_editor "$(get_tmux_option "@ferret-popup-editor" "")")
PANE_EDITOR=$(detect_pane_editor "$(get_tmux_option "@ferret-pane-editor" "")")
FD_EXTRA_ARGS=$(get_tmux_option "@ferret-fd-args" "")
RG_EXTRA_ARGS=$(get_tmux_option "@ferret-rg-args" "")

# ─── Detect tools ────────────────────────────────────────────────────────────

FD_CMD=$(detect_fd)
BAT_CMD=$(detect_bat)
RG_CMD=$(detect_rg)

# ─── Require fzf ────────────────────────────────────────────────────────────

command -v fzf &>/dev/null || {
    echo "fzf is required for tmux-ferret."
    echo "Install: apt install fzf  OR  brew install fzf  OR  https://github.com/junegunn/fzf#installation"
    exit 1
}

fzf_version=$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ -n "$fzf_version" ]] && [[ "$(printf '%s\n%s' "0.45" "$fzf_version" | sort -V | head -n1)" != "0.45" ]]; then
    echo "Warning: fzf 0.45+ recommended (found $fzf_version). Dynamic labels require 0.45+."
fi

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

    # File preview command (bat or head fallback)
    local file_preview
    if [[ -n "$BAT_CMD" ]]; then
        file_preview="$BAT_CMD --color=always --style=numbers --line-range=:500 {}"
    else
        file_preview="head -500 {}"
    fi

    # Welcome cheat sheet shown when query is empty
    local welcome_preview="echo -e '\\n  Type to search files\\n\\n  >  grep code\\n  @  switch sessions\\n\\n  Enter  open in editor\\n  ^O     send to pane\\n  ^Y     copy path'"

    # Initial preview: welcome if no query, file preview otherwise
    local initial_preview="$welcome_preview"
    local initial_border_label=" Ferret "
    local initial_preview_label=" Guide "
    if [[ -n "$QUERY" ]]; then
        initial_preview="$file_preview"
        initial_border_label=" Files "
        initial_preview_label=" Preview "
    fi

    # change:transform handles three concerns:
    # 1. > prefix → become grep mode
    # 2. @ prefix → become sessions mode
    # 3. empty ↔ non-empty → toggle welcome/file preview and border label
    local change_transform
    change_transform="if [[ {q} == '>'* ]]; then
  echo \"become('$SCRIPT_DIR/ferret.sh' --mode=grep --pane='$PANE_ID' --query=\\\"\$FZF_QUERY\\\")\"
elif [[ {q} == '@'* ]]; then
  echo \"become('$SCRIPT_DIR/ferret.sh' --mode=sessions --pane='$PANE_ID' --query=\\\"\$FZF_QUERY\\\")\"
elif [[ -z {q} ]]; then
  echo \"change-preview($welcome_preview)+change-border-label( Ferret )+change-preview-label( Guide )\"
else
  echo \"change-preview($file_preview)+change-border-label( Files )+change-preview-label( Preview )\"
fi"

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(eval "$file_cmd" | fzf \
        "${base_opts[@]}" \
        --expect=ctrl-o,ctrl-y \
        --multi \
        --query "$QUERY" \
        --prompt '  ' \
        --preview "$initial_preview" \
        --preview-label="$initial_preview_label" \
        --border-label="$initial_border_label" \
        --bind "change:transform:$change_transform" \
    ) || exit 0

    handle_file_result "$result"
}

# ─── Mode: grep ──────────────────────────────────────────────────────────────

run_grep_mode() {
    if [[ -z "$RG_CMD" ]]; then
        echo "ripgrep (rg) is required for content search."
        echo "Install: apt install ripgrep  OR  brew install ripgrep  OR  mise use -g ripgrep@latest"
        read -r -p "Press Enter to close..."
        exit 1
    fi

    # Preview command: preview.sh handles bat-or-head fallback internally
    local preview_cmd="'$SCRIPT_DIR/preview.sh' {1} {2}"

    # Strip leading > from prefix-based switch
    QUERY="${QUERY#>}"

    # Backspace-on-empty returns to files (home)
    local become_files_empty="become('$SCRIPT_DIR/ferret.sh' --mode=files --pane='$PANE_ID')"

    # Live reload rg on every keystroke
    local rg_reload="$RG_CMD --line-number --no-heading --color=always --smart-case $RG_EXTRA_ARGS -- {q} || true"

    # Seed results if we have an initial query from mode switch
    local initial_cmd=":"
    if [[ -n "$QUERY" ]]; then
        initial_cmd="$RG_CMD --line-number --no-heading --color=always --smart-case $RG_EXTRA_ARGS -- $(printf '%q' "$QUERY") || true"
    fi

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(eval "$initial_cmd" | fzf \
        "${base_opts[@]}" \
        --expect=ctrl-o,ctrl-y \
        --disabled \
        --query "$QUERY" \
        --prompt '> ' \
        --ansi \
        --delimiter ':' \
        --bind "change:reload:$rg_reload" \
        --preview "$preview_cmd" \
        --preview-window 'right:60%:border-left:+{2}/2' \
        --border-label=' Grep ' \
        --bind "backward-eof:$become_files_empty" \
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

# ─── Mode: sessions ─────────────────────────────────────────────────────────

run_session_mode() {
    # Strip leading @ from prefix-based switch
    QUERY="${QUERY#@}"

    # Build session list: name<TAB>  name · Nw · age [· attached]
    local now session_list
    now=$(date +%s)
    session_list=$(
        tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}' 2>/dev/null |
        while IFS='|' read -r name wins attached activity; do
            age=$(format_relative_time $((now - activity)))
            # Display: name in default color, metadata in grey
            meta="\033[90m· ${wins}w · ${age}"
            [ "${attached:-0}" -gt 0 ] && meta="${meta} · attached"
            meta="${meta}\033[0m"
            printf '%s\t  %s %b\n' "$name" "$name" "$meta"
        done
    )

    [ -z "$session_list" ] && { echo "No sessions found."; exit 0; }

    local become_files="become('$SCRIPT_DIR/ferret.sh' --mode=files --pane='$PANE_ID')"
    local become_new="become('$SCRIPT_DIR/ferret.sh' --mode=session-new --pane='$PANE_ID')"

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(
        echo "$session_list" |
        fzf --print-query \
            "${base_opts[@]}" \
            --expect=ctrl-k,ctrl-y \
            --query "$QUERY" \
            --prompt '@ ' \
            --delimiter=$'\t' \
            --with-nth=2.. \
            --nth=1 \
            --accept-nth=1 \
            --ansi \
            --no-sort \
            --border-label=' Sessions ' \
            --preview "'$SCRIPT_DIR/session-preview.sh' {1}" \
            --bind "backward-eof:$become_files" \
            --bind "ctrl-n:$become_new" \
    ) || exit 0

    handle_session_result "$result"
}

handle_session_result() {
    local result="$1"
    local query key selected

    query=$(head -1 <<< "$result")
    key=$(sed -n '2p' <<< "$result")
    selected=$(tail -1 <<< "$result" | cut -f1)

    # If nothing selected by cursor, use the typed query as session name
    if [[ -z "$selected" || "$selected" == "$key" ]]; then
        selected="$query"
    fi
    [[ -z "$selected" ]] && exit 0

    case "$key" in
        ctrl-y)
            # Copy session name to clipboard via tmux
            echo -n "$selected" | tmux load-buffer -w -
            tmux display-message "Copied: $selected"
            ;;
        ctrl-k)
            # Kill session (refuse to kill current)
            local current
            current=$(tmux display-message -p '#{session_name}' 2>/dev/null)
            if [[ "$selected" == "$current" ]]; then
                tmux display-message "Cannot kill current session"
            elif tmux has-session -t "$selected" 2>/dev/null; then
                tmux kill-session -t "$selected"
                tmux display-message "Killed session: $selected"
            else
                tmux display-message "Session not found: $selected"
            fi
            ;;
        *)
            # Switch to session, or create if it doesn't exist
            tmux switch-client -t "$selected" 2>/dev/null ||
                { tmux new-session -d -s "$selected" && tmux switch-client -t "$selected"; }
            ;;
    esac
}

# ─── Mode: session-new ──────────────────────────────────────────────────────

run_session_new_mode() {
    local session_dirs
    session_dirs=$(get_tmux_option "@ferret-session-dirs" "$HOME/Projects")

    # Build directory listing from all configured dirs (colon-separated)
    local dir_cmd=""
    local IFS=':'
    for dir in $session_dirs; do
        [[ -d "$dir" ]] || continue
        if [[ -n "$FD_CMD" ]]; then
            local part="$FD_CMD --type d --max-depth 1 --min-depth 1 . '$dir'"
        else
            local part="find '$dir' -mindepth 1 -maxdepth 1 -type d"
        fi
        if [[ -n "$dir_cmd" ]]; then
            dir_cmd="$dir_cmd; $part"
        else
            dir_cmd="$part"
        fi
    done
    unset IFS

    if [[ -z "$dir_cmd" ]]; then
        echo "No valid session directories found."
        echo "Configure with: set -g @ferret-session-dirs '/path/one:/path/two'"
        read -r -p "Press Enter to close..."
        exit 1
    fi

    # Preview with ls or tree
    local preview_cmd
    if command -v tree &>/dev/null; then
        preview_cmd="tree -C -L 2 {}"
    else
        preview_cmd="ls -la --color=always {}"
    fi

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local selected
    selected=$(eval "$dir_cmd" | sort | fzf \
        "${base_opts[@]}" \
        --border-label=' New Session ' \
        --preview "$preview_cmd" \
    ) || exit 0

    [[ -z "$selected" ]] && exit 0

    local session_name
    session_name=$(basename "$selected")

    # Sanitize session name (tmux doesn't allow dots or colons)
    session_name="${session_name//./-}"
    session_name="${session_name//:/-}"

    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux switch-client -t "$session_name"
    else
        tmux new-session -d -s "$session_name" -c "$selected" && \
            tmux switch-client -t "$session_name"
    fi
}

# ─── Dispatch ────────────────────────────────────────────────────────────────

case "$MODE" in
    files)       run_files_mode ;;
    grep)        run_grep_mode ;;
    sessions)    run_session_mode ;;
    session-new) run_session_new_mode ;;
    *)
        echo "Unknown mode: $MODE (expected: files, grep, sessions, session-new)"
        exit 1
        ;;
esac
