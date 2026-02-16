#!/usr/bin/env bash
# =============================================================================
# dispatch.sh — Unified file finder, content search, and session picker
# =============================================================================
# Six modes, switchable mid-session via fzf's become action:
#
#   --mode=files          fd/find → fzf (normal filtering, bat preview)
#   --mode=grep           fzf --disabled + change:reload:rg (live search)
#   --mode=sessions       tmux session picker/creator
#   --mode=session-new    directory-based session creation
#   --mode=rename         inline file rename (fzf query = new name)
#   --mode=rename-session inline session rename (fzf query = new name)
#
# Mode switching (VSCode command palette style):
#   Files is the home mode. Prefixes step into sub-modes:
#   > prefix   — Files → grep (remainder becomes query)
#   @ prefix   — Files → sessions (remainder becomes query)
#   ⌫ on empty — Grep/sessions → files (return to home)
#
# Usage: dispatch.sh --mode=files|grep|sessions|session-new|rename|rename-session
#        [--pane=ID] [--query=TEXT] [--file=PATH] [--session=NAME]
# =============================================================================

set -euo pipefail

# ─── Require bash 4.0+ ──────────────────────────────────────────────────────
# mapfile, declare -A (associative arrays), and [[ -v ]] need bash 4.0+.
# macOS ships bash 3.2 — users need: brew install bash
if ((BASH_VERSINFO[0] < 4)); then
    echo "tmux-dispatch requires bash 4.0+ (found ${BASH_VERSION})."
    echo "macOS users: brew install bash"
    echo "Then ensure the Homebrew bash is first in your PATH."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

# ─── Parse arguments ─────────────────────────────────────────────────────────

MODE="files"
PANE_ID=""
QUERY=""
FILE=""
SESSION=""

for arg in "$@"; do
    case "$arg" in
        --mode=*)    MODE="${arg#--mode=}" ;;
        --pane=*)    PANE_ID="${arg#--pane=}" ;;
        --query=*)   QUERY="${arg#--query=}" ;;
        --file=*)    FILE="${arg#--file=}" ;;
        --session=*) SESSION="${arg#--session=}" ;;
    esac
done

# Resolve pane ID: prefer --pane arg, fall back to @dispatch-origin-pane option.
# display-popup doesn't expand #{...} formats in the shell-command argument,
# so the binding uses run-shell to stash the pane ID in a global option first.
if [[ -z "$PANE_ID" || "$PANE_ID" == '#{pane_id}' ]]; then
    PANE_ID=$(get_tmux_option "@dispatch-origin-pane" "")
fi

# ─── Validate mode ──────────────────────────────────────────────────────────

case "$MODE" in
    files|grep|sessions|session-new|rename|rename-session) ;;
    *)
        echo "Unknown mode: $MODE (expected: files, grep, sessions, session-new)"
        exit 1
        ;;
esac

# ─── Read tmux options ───────────────────────────────────────────────────────

POPUP_EDITOR=$(detect_popup_editor "$(get_tmux_option "@dispatch-popup-editor" "")")
PANE_EDITOR=$(detect_pane_editor "$(get_tmux_option "@dispatch-pane-editor" "")")
FD_EXTRA_ARGS=$(get_tmux_option "@dispatch-fd-args" "")
RG_EXTRA_ARGS=$(get_tmux_option "@dispatch-rg-args" "")
HISTORY_ENABLED=$(get_tmux_option "@dispatch-history" "on")

# ─── Detect tools ────────────────────────────────────────────────────────────

FD_CMD=$(detect_fd)
BAT_CMD=$(detect_bat)
RG_CMD=$(detect_rg)

# ─── Require fzf ────────────────────────────────────────────────────────────

command -v fzf &>/dev/null || {
    echo "fzf is required for tmux-dispatch."
    echo "Install: apt install fzf  OR  brew install fzf  OR  https://github.com/junegunn/fzf#installation"
    exit 1
}

fzf_version=$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ -n "$fzf_version" ]] && [[ "$(printf '%s\n%s' "0.45" "$fzf_version" | sort -V | head -n1)" != "0.45" ]]; then
    echo "Warning: fzf 0.45+ recommended (found $fzf_version). Dynamic labels require 0.45+."
fi

# ─── Mode: files ─────────────────────────────────────────────────────────────

run_files_mode() {
    # File listing command — built as both a string (for fzf reload bindings)
    # and invoked directly via _run_file_cmd (avoids eval for the initial pipe).
    # Note: fzf reload bindings execute strings via sh -c; FD_EXTRA_ARGS is a
    # trust boundary (set by the user themselves via tmux options, not external input).
    local file_cmd
    local -a fd_extra_args_arr=()
    [[ -n "$FD_EXTRA_ARGS" ]] && read -ra fd_extra_args_arr <<< "$FD_EXTRA_ARGS"

    if [[ -n "$FD_CMD" ]]; then
        local strip_prefix=""
        $FD_CMD --help 2>&1 | grep -q -- '--strip-cwd-prefix' && strip_prefix="--strip-cwd-prefix"
        file_cmd="$FD_CMD --type f --hidden --follow --exclude .git $strip_prefix $FD_EXTRA_ARGS"
    else
        file_cmd="find . -type f -not -path '*/.git/*'"
    fi

    _run_file_cmd() {
        if [[ -n "$FD_CMD" ]]; then
            "$FD_CMD" --type f --hidden --follow --exclude .git \
                ${strip_prefix:+"$strip_prefix"} "${fd_extra_args_arr[@]}"
        else
            find . -type f -not -path '*/.git/*'
        fi
    }

    # File preview command (bat or head fallback)
    local file_preview
    if [[ -n "$BAT_CMD" ]]; then
        file_preview="$BAT_CMD --color=always --style=numbers --line-range=:500 {}"
    else
        file_preview="head -500 {}"
    fi

    # Welcome cheat sheet shown when query is empty
    local welcome_preview="echo -e '\\n  Type to search files\\n\\n  \\033[38;5;103m>\\033[0m  grep code\\n  \\033[38;5;103m@\\033[0m  switch sessions\\n\\n  \\033[38;5;103menter\\033[0m  open in editor\\n  \\033[38;5;103m^O\\033[0m     send to pane\\n  \\033[38;5;103m^Y\\033[0m     copy path\\n  \\033[38;5;103m^R\\033[0m     rename file\\n  \\033[38;5;103m^X\\033[0m     delete file'"

    # Flag file: preview shows welcome on first run (flag exists), file preview after
    local welcome_flag
    welcome_flag=$(mktemp "${TMPDIR:-/tmp}/dispatch-XXXXXX")
    trap 'command rm -f "$welcome_flag"' EXIT

    # Smart preview: when flag exists → welcome + delete flag; otherwise → file preview
    local smart_preview="if [ -f '$welcome_flag' ]; then command rm -f '$welcome_flag'; $welcome_preview; else $file_preview; fi"

    local initial_border_label=" dispatch "
    local initial_preview_label=" guide "
    if [[ -n "$QUERY" ]]; then
        command rm -f "$welcome_flag"  # skip welcome when query is provided
        initial_border_label=" files "
        initial_preview_label=" preview "
    fi

    # change:transform handles three concerns:
    # 1. > prefix → become grep mode
    # 2. @ prefix → become sessions mode
    # 3. empty ↔ non-empty → toggle welcome/file preview and border label
    #
    # Uses execute-silent + refresh-preview to update the flag file and re-run
    # the smart preview, rather than change-preview which would replace the
    # stateful preview command with a static one.
    local change_transform
    change_transform="if [[ {q} == '>'* ]]; then
  echo \"become('$SCRIPT_DIR/dispatch.sh' --mode=grep --pane='$PANE_ID' --query=\\\"\$FZF_QUERY\\\")\"
elif [[ {q} == '@'* ]]; then
  echo \"become('$SCRIPT_DIR/dispatch.sh' --mode=sessions --pane='$PANE_ID' --query=\\\"\$FZF_QUERY\\\")\"
elif [[ -z {q} ]]; then
  echo \"execute-silent(touch '$welcome_flag')+refresh-preview+change-border-label( dispatch )+change-preview-label( guide )\"
else
  echo \"execute-silent(command rm -f '$welcome_flag')+refresh-preview+change-border-label( files )+change-preview-label( preview )\"
fi"

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(
        if [[ "$HISTORY_ENABLED" == "on" ]]; then
            { recent_files_for_pwd "$PWD"; _run_file_cmd; } | awk '!seen[$0]++'
        else
            _run_file_cmd
        fi | fzf \
        "${base_opts[@]}" \
        --expect=ctrl-o,ctrl-y \
        --multi \
        --query "$QUERY" \
        --prompt '  ' \
        --preview "$smart_preview" \
        --preview-label="$initial_preview_label" \
        --border-label="$initial_border_label" \
        --bind "change:transform:$change_transform" \
        --bind "focus:change-border-label( files )+change-preview-label( preview )" \
        --bind "start:unbind(focus)" \
        --bind "down:rebind(focus)+down" \
        --bind "up:rebind(focus)+up" \
        --bind "ctrl-r:become('$SCRIPT_DIR/dispatch.sh' --mode=rename --pane='$PANE_ID' --file={})" \
        --bind "ctrl-x:execute('$SCRIPT_DIR/actions.sh' delete-files {+})+reload($file_cmd)" \
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
    local become_files_empty="become('$SCRIPT_DIR/dispatch.sh' --mode=files --pane='$PANE_ID')"

    # Live reload rg on every keystroke (fzf executes via sh -c — must be a string).
    # RG_EXTRA_ARGS is a trust boundary: set by the user via tmux options, not external input.
    local rg_reload="$RG_CMD --line-number --no-heading --color=always --smart-case $RG_EXTRA_ARGS -- {q} || true"

    # Split RG_EXTRA_ARGS for safe direct invocation (avoids eval)
    local -a rg_extra_args_arr=()
    [[ -n "$RG_EXTRA_ARGS" ]] && read -ra rg_extra_args_arr <<< "$RG_EXTRA_ARGS"

    # Seed results directly if we have an initial query from mode switch
    _run_initial_rg() {
        if [[ -n "$QUERY" ]]; then
            "$RG_CMD" --line-number --no-heading --color=always --smart-case \
                "${rg_extra_args_arr[@]}" -- "$QUERY" || true
        fi
    }

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(_run_initial_rg | fzf \
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
        --border-label=' grep ' \
        --bind "ctrl-r:become('$SCRIPT_DIR/dispatch.sh' --mode=rename --pane='$PANE_ID' --file={1})" \
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
                    [[ "$HISTORY_ENABLED" == "on" ]] && record_file_open "$PWD" "$f"
                    quoted_files="${quoted_files:+$quoted_files }$(printf '%q' "$f")"
                done
                tmux send-keys -t "$PANE_ID" "$PANE_EDITOR $quoted_files" Enter
            else
                tmux display-message "No target pane available"
            fi
            ;;
        *)
            # Open in popup editor
            if [[ "$HISTORY_ENABLED" == "on" ]]; then
                for f in "${files[@]}"; do record_file_open "$PWD" "$f"; done
            fi
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
                [[ "$HISTORY_ENABLED" == "on" ]] && record_file_open "$PWD" "$file"
                tmux send-keys -t "$PANE_ID" "$PANE_EDITOR +$line_num $(printf '%q' "$file")" Enter
            else
                tmux display-message "No target pane available"
            fi
            ;;
        *)
            # Open in popup editor at matching line
            [[ "$HISTORY_ENABLED" == "on" ]] && record_file_open "$PWD" "$file"
            exec "$POPUP_EDITOR" "+$line_num" "$file"
            ;;
    esac
}

# ─── Mode: sessions ─────────────────────────────────────────────────────────

run_session_mode() {
    # Strip leading @ from prefix-based switch
    QUERY="${QUERY#@}"

    # Build session list via shared helper (also used by reload)
    local session_list
    session_list=$("$SCRIPT_DIR/actions.sh" list-sessions)

    [ -z "$session_list" ] && { echo "No sessions found."; exit 0; }

    local become_files="become('$SCRIPT_DIR/dispatch.sh' --mode=files --pane='$PANE_ID')"
    local become_new="become('$SCRIPT_DIR/dispatch.sh' --mode=session-new --pane='$PANE_ID')"

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
            --nth=1 \
            --accept-nth=1 \
            --ansi \
            --no-sort \
            --border-label=' sessions ' \
            --preview "'$SCRIPT_DIR/session-preview.sh' {1}" \
            --bind "ctrl-r:become('$SCRIPT_DIR/dispatch.sh' --mode=rename-session --pane='$PANE_ID' --session={1})" \
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
    session_dirs=$(get_tmux_option "@dispatch-session-dirs" "$HOME/Projects")

    # Collect valid session directories (colon-separated)
    local -a valid_dirs=()
    local IFS=':'
    for dir in $session_dirs; do
        [[ -d "$dir" ]] && valid_dirs+=("$dir")
    done
    unset IFS

    if [[ ${#valid_dirs[@]} -eq 0 ]]; then
        echo "No valid session directories found."
        echo "Configure with: set -g @dispatch-session-dirs '/path/one:/path/two'"
        read -r -p "Press Enter to close..."
        exit 1
    fi

    # List subdirectories from all configured dirs (avoids eval)
    _run_dir_cmd() {
        for dir in "${valid_dirs[@]}"; do
            if [[ -n "$FD_CMD" ]]; then
                "$FD_CMD" --type d --max-depth 1 --min-depth 1 . "$dir"
            else
                find "$dir" -mindepth 1 -maxdepth 1 -type d
            fi
        done
    }

    # Preview with ls or tree (ls -G for macOS BSD, --color for GNU)
    local preview_cmd
    if command -v tree &>/dev/null; then
        preview_cmd="tree -C -L 2 {}"
    elif ls --color=always /dev/null 2>/dev/null; then
        preview_cmd="ls -la --color=always {}"
    else
        preview_cmd="ls -laG {}"
    fi

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local selected
    selected=$(_run_dir_cmd | sort | fzf \
        "${base_opts[@]}" \
        --border-label=' new session ' \
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

# ─── Mode: rename ─────────────────────────────────────────────────────────

run_rename_mode() {
    [[ -z "$FILE" ]] && exit 1
    if [[ ! -f "$FILE" ]]; then
        tmux display-message "File not found: $FILE"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(
        echo "$FILE" | fzf \
            "${base_opts[@]}" \
            --disabled \
            --print-query \
            --query "$FILE" \
            --prompt '→ ' \
            --header 'enter confirm · esc cancel' \
            --preview "'$SCRIPT_DIR/actions.sh' rename-preview '$FILE' {q}" \
            --border-label=' rename ' \
    ) || exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"

    local new_name
    new_name=$(head -1 <<< "$result")

    # Empty or unchanged → cancel
    if [[ -z "$new_name" || "$new_name" == "$FILE" ]]; then
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    # Conflict check
    if [[ -e "$new_name" ]]; then
        tmux display-message "Already exists: $new_name"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    # Perform rename
    local dir
    dir=$(dirname "$new_name")
    [[ -d "$dir" ]] || mkdir -p "$dir"
    command mv "$FILE" "$new_name"

    exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
}

# ─── Mode: rename-session ────────────────────────────────────────────────────

run_rename_session_mode() {
    [[ -z "$SESSION" ]] && exit 1
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux display-message "Session not found: $SESSION"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
    fi

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(
        echo "$SESSION" | fzf \
            "${base_opts[@]}" \
            --disabled \
            --print-query \
            --query "$SESSION" \
            --prompt '→ ' \
            --header 'enter confirm · esc cancel' \
            --preview "'$SCRIPT_DIR/actions.sh' rename-session-preview '$SESSION' {q}" \
            --border-label=' rename session ' \
    ) || exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"

    local new_name
    new_name=$(head -1 <<< "$result")

    # Empty or unchanged → cancel
    if [[ -z "$new_name" || "$new_name" == "$SESSION" ]]; then
        exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
    fi

    # Conflict check
    if tmux has-session -t "$new_name" 2>/dev/null; then
        tmux display-message "Session already exists: $new_name"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
    fi

    tmux rename-session -t "$SESSION" "$new_name"

    exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
}

# ─── Dispatch ────────────────────────────────────────────────────────────────

case "$MODE" in
    files)          run_files_mode ;;
    grep)           run_grep_mode ;;
    sessions)       run_session_mode ;;
    session-new)    run_session_new_mode ;;
    rename)         run_rename_mode ;;
    rename-session) run_rename_session_mode ;;
esac
