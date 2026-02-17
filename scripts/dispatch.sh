#!/usr/bin/env bash
# =============================================================================
# dispatch.sh — Unified file finder, content search, and session picker
# =============================================================================
# Ten modes, switchable mid-session via fzf's become action:
#
#   --mode=files          fd/find → fzf (normal filtering, bat preview)
#   --mode=grep           fzf --disabled + change:reload:rg (live search)
#   --mode=git            git status with stage/unstage toggle
#   --mode=dirs           directory picker (zoxide/fd/find)
#   --mode=sessions       tmux session picker/creator
#   --mode=session-new    directory-based session creation
#   --mode=windows        tmux window picker for a session
#   --mode=rename         inline file rename (fzf query = new name)
#   --mode=rename-session inline session rename (fzf query = new name)
#
# Mode switching (VSCode command palette style):
#   Files is the home mode. Prefixes step into sub-modes:
#   > prefix   — Files → grep (remainder becomes query)
#   @ prefix   — Files → sessions (remainder becomes query)
#   ! prefix   — Files → git status (remainder becomes query)
#   # prefix   — Files → directories (remainder becomes query)
#   ⌫ on empty — Sub-modes → files (return to home)
#
# Usage: dispatch.sh --mode=files|grep|git|dirs|sessions|session-new|windows|rename|rename-session
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

# Validate pane ID format if provided (tmux pane IDs are %N)
if [[ -n "$PANE_ID" && "$PANE_ID" != '#{pane_id}' && ! "$PANE_ID" =~ ^%[0-9]+$ ]]; then
    PANE_ID=""  # Clear invalid pane ID, will fall back to tmux option
fi

# Resolve pane ID: prefer --pane arg, fall back to @dispatch-origin-pane option.
# display-popup doesn't expand #{...} formats in the shell-command argument,
# so the binding uses run-shell to stash the pane ID in a global option first.
if [[ -z "$PANE_ID" || "$PANE_ID" == '#{pane_id}' ]]; then
    PANE_ID=$(get_tmux_option "@dispatch-origin-pane" "")
fi

# ─── Validate mode ──────────────────────────────────────────────────────────

case "$MODE" in
    files|grep|git|dirs|sessions|session-new|windows|rename|rename-session) ;;
    *)
        echo "Unknown mode: $MODE (expected: files, grep, git, dirs, sessions, windows, session-new)"
        exit 1
        ;;
esac

# ─── Read tmux options ───────────────────────────────────────────────────────

POPUP_EDITOR=$(detect_popup_editor "$(get_tmux_option "@dispatch-popup-editor" "")")
PANE_EDITOR=$(detect_pane_editor "$(get_tmux_option "@dispatch-pane-editor" "")")
FD_EXTRA_ARGS=$(get_tmux_option "@dispatch-fd-args" "")
RG_EXTRA_ARGS=$(get_tmux_option "@dispatch-rg-args" "")
HISTORY_ENABLED=$(get_tmux_option "@dispatch-history" "on")
FILE_TYPES=$(get_tmux_option "@dispatch-file-types" "")
GIT_INDICATORS=$(get_tmux_option "@dispatch-git-indicators" "on")

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
if [[ -n "$fzf_version" ]]; then
    _fzf_below() { [[ "$(printf '%s\n%s' "$1" "$fzf_version" | sort -V | head -n1)" != "$1" ]]; }
    if _fzf_below "0.38"; then
        echo "Error: fzf 0.38+ required for mode switching (found $fzf_version)."
        echo "Install latest: https://github.com/junegunn/fzf#installation"
    elif _fzf_below "0.45"; then
        echo "Warning: fzf 0.45+ recommended (found $fzf_version). Dynamic labels require 0.45+."
    fi
    unset -f _fzf_below
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

    # Parse file type filters (comma-separated extensions from @dispatch-file-types)
    # Two representations: array for direct find invocation, string for fzf reload command.
    local -a type_flags=()
    local type_flags_str=""
    local find_name_filter=""
    local -a find_name_args=()
    if [[ -n "$FILE_TYPES" ]]; then
        local -a exts
        IFS=',' read -ra exts <<< "$FILE_TYPES"
        local first=true
        local ext
        for ext in "${exts[@]}"; do
            ext="${ext## }"; ext="${ext%% }"  # trim whitespace
            [[ -n "$ext" ]] || continue
            type_flags+=(--extension "$ext")
            type_flags_str+=" --extension '$ext'"
            if $first; then
                find_name_args+=("(" -name "*.${ext}")
                find_name_filter="\\( -name '*.${ext}'"
                first=false
            else
                find_name_args+=(-o -name "*.${ext}")
                find_name_filter+=" -o -name '*.${ext}'"
            fi
        done
        [[ ${#find_name_args[@]} -gt 0 ]] && find_name_args+=(")")
        [[ -n "$find_name_filter" ]] && find_name_filter+=" \\)"
    fi

    # Extension filter applied after dedup — catches bookmarks/frecency that bypass fd/find.
    # Two representations: function for direct invocation, string for fzf reload command.
    local ext_filter_str=""
    _ext_filter() { cat; }  # no-op default
    if [[ -n "$FILE_TYPES" ]]; then
        local ext_re
        ext_re=$(IFS='|'; exts_arr=(); for e in "${exts[@]}"; do e="${e## }"; e="${e%% }"; [[ -n "$e" ]] && exts_arr+=("$e"); done; echo "${exts_arr[*]}")
        ext_filter_str="| grep -E '\\.($ext_re)$'"
        _ext_filter() { grep -E "\\.(${ext_re})$" || true; }
    fi

    if [[ -n "$FD_CMD" ]]; then
        local strip_prefix=""
        "$FD_CMD" --help 2>&1 | grep -q -- '--strip-cwd-prefix' && strip_prefix="--strip-cwd-prefix"
        file_cmd="$FD_CMD --type f --hidden --follow --exclude .git $strip_prefix$type_flags_str $FD_EXTRA_ARGS"
    else
        file_cmd="find . -type f -not -path '*/.git/*'${find_name_filter:+ $find_name_filter}"
    fi

    _run_file_cmd() {
        if [[ -n "$FD_CMD" ]]; then
            "$FD_CMD" --type f --hidden --follow --exclude .git \
                ${strip_prefix:+"$strip_prefix"} "${type_flags[@]}" "${fd_extra_args_arr[@]}"
        else
            find . -type f -not -path '*/.git/*' "${find_name_args[@]}"
        fi
    }

    # ─── File indicators (bookmarks + git status) ──────────────────────────────
    # Always tab-delimited: indicators\tfilename.
    # Indicator column: ★ for bookmarked, git icon for dirty files.
    local fzf_file="{2..}" fzf_files="{+2..}"
    local bf
    bf=$(_dispatch_bookmark_file)
    local git_active=false git_prefix=""
    if [[ "$GIT_INDICATORS" == "on" ]] && git rev-parse --is-inside-work-tree &>/dev/null; then
        git_active=true
        git_prefix=$(git rev-parse --show-prefix 2>/dev/null)
    fi
    local do_git=0
    $git_active && do_git=1

    # shellcheck disable=SC2016  # $0 etc. are awk variables, not bash
    local annotate_awk='BEGIN {
        if (bfile != "") {
            while ((getline line < bfile) > 0) {
                n = split(line, a, "\t")
                if (n >= 2 && a[1] == pwd) bm[a[2]] = 1
            }
            close(bfile)
        }
        if (do_git) {
            plen = length(prefix)
            cmd = "git status --porcelain 2>/dev/null"
            while ((cmd | getline line) > 0) {
                xy = substr(line, 1, 2)
                file = substr(line, 4)
                if (plen > 0) {
                    if (substr(file, 1, plen) != prefix) continue
                    file = substr(file, plen + 1)
                }
                x = substr(xy, 1, 1)
                y = substr(xy, 2, 1)
                if (x == "?" && y == "?")       gs[file] = "\033[33m?\033[0m"
                else if (x != " " && y != " ")  gs[file] = "\033[35m✹\033[0m"
                else if (x != " ")              gs[file] = "\033[32m✚\033[0m"
                else                            gs[file] = "\033[31m●\033[0m"
            }
            close(cmd)
        }
    }
    {
        f = $0; sub(/^\.\//, "", f)
        if (f in bm) ind = "\033[33m★\033[0m"
        else ind = " "
        if (do_git) {
            if (f in gs) ind = ind gs[f]
            else ind = ind " "
        }
        printf "%s\t%s\n", ind, $0
    }'

    _annotate_files() {
        awk -v bfile="$bf" -v pwd="$PWD" -v do_git="$do_git" -v prefix="$git_prefix" "$annotate_awk"
    }

    # File preview command (bat or head fallback)
    local file_preview
    if [[ -n "$BAT_CMD" ]]; then
        file_preview="$BAT_CMD --color=always --style=numbers --line-range=:500 $fzf_file"
    else
        file_preview="head -500 $fzf_file"
    fi

    # Welcome cheat sheet shown when query is empty
    local welcome_preview="echo -e '\\n  Type to search files\\n\\n  \\033[38;5;103m>\\033[0m  grep code\\n  \\033[38;5;103m@\\033[0m  switch sessions\\n  \\033[38;5;103m!\\033[0m  git status\\n  \\033[38;5;103m#\\033[0m  directories\\n\\n  \\033[38;5;103menter\\033[0m  open in editor\\n  \\033[38;5;103m^O\\033[0m     send to pane\\n  \\033[38;5;103m^Y\\033[0m     copy path\\n  \\033[38;5;103m^B\\033[0m     toggle bookmark\\n  \\033[38;5;103m^R\\033[0m     rename file\\n  \\033[38;5;103m^X\\033[0m     delete file'"

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
  echo \"become('$SCRIPT_DIR/dispatch.sh' --mode=grep --pane='$PANE_ID' --query={q})\"
elif [[ {q} == '@'* ]]; then
  echo \"become('$SCRIPT_DIR/dispatch.sh' --mode=sessions --pane='$PANE_ID' --query={q})\"
elif [[ {q} == '!'* ]]; then
  echo \"become('$SCRIPT_DIR/dispatch.sh' --mode=git --pane='$PANE_ID' --query={q})\"
elif [[ {q} == '#'* ]]; then
  echo \"become('$SCRIPT_DIR/dispatch.sh' --mode=dirs --pane='$PANE_ID' --query={q})\"
elif [[ -z {q} ]]; then
  echo \"execute-silent(touch '$welcome_flag')+refresh-preview+change-border-label( dispatch )+change-preview-label( guide )\"
else
  echo \"execute-silent(command rm -f '$welcome_flag')+refresh-preview+change-border-label( files )+change-preview-label( preview )\"
fi"

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    # Reloadable file list command (bookmarks + frecency + files, deduped).
    # Used by fzf reload bindings (ctrl-x, ctrl-b).
    # Quoting: outer "..." expands $SCRIPT_DIR/$PWD/$file_cmd at definition time;
    # inner '...' passed to bash -c protects awk's $0 and function calls from sh.
    local annotate_cmd="awk -v bfile='$bf' -v pwd='$PWD' -v do_git=$do_git -v prefix='$git_prefix' '${annotate_awk}'"
    local file_list_cmd
    if [[ "$HISTORY_ENABLED" == "on" ]]; then
        file_list_cmd="bash -c 'source \"$SCRIPT_DIR/helpers.sh\"; { bookmarks_for_pwd \"$PWD\"; recent_files_for_pwd \"$PWD\"; $file_cmd; } | dedup_lines' $ext_filter_str | $annotate_cmd"
    else
        file_list_cmd="bash -c 'source \"$SCRIPT_DIR/helpers.sh\"; { bookmarks_for_pwd \"$PWD\"; $file_cmd; } | dedup_lines' $ext_filter_str | $annotate_cmd"
    fi

    local result
    result=$(
        if [[ "$HISTORY_ENABLED" == "on" ]]; then
            { bookmarks_for_pwd "$PWD"; recent_files_for_pwd "$PWD"; _run_file_cmd; } | awk '!seen[$0]++' | _ext_filter
        else
            { bookmarks_for_pwd "$PWD"; _run_file_cmd; } | awk '!seen[$0]++' | _ext_filter
        fi | _annotate_files | fzf \
        "${base_opts[@]}" \
        --ansi --delimiter=$'\t' --nth=2.. --tabstop=3 \
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
        --bind "ctrl-r:become('$SCRIPT_DIR/dispatch.sh' --mode=rename --pane='$PANE_ID' --file=$fzf_file)" \
        --bind "ctrl-x:execute('$SCRIPT_DIR/actions.sh' delete-files $fzf_files)+reload:$file_list_cmd" \
        --bind "ctrl-b:execute-silent('$SCRIPT_DIR/actions.sh' bookmark-toggle '$PWD' $fzf_file)+reload:$file_list_cmd" \
        --bind "enter:execute('$SCRIPT_DIR/actions.sh' edit-file '$POPUP_EDITOR' '$PWD' '$HISTORY_ENABLED' $fzf_files)" \
    ) || exit 0

    # Strip indicator prefix from fzf output (indicator\tfile → file).
    # cut -f2- is a no-op for lines without tabs (the --expect key line).
    if [[ -n "$result" ]]; then
        result=$(cut -f2- <<< "$result")
    fi

    handle_file_result "$result"
}

# ─── Mode: grep ──────────────────────────────────────────────────────────────

run_grep_mode() {
    if [[ -z "$RG_CMD" ]]; then
        tmux display-message "ripgrep (rg) required for grep mode — install: brew/apt install ripgrep"
        exit 1
    fi

    # Preview command: preview.sh handles bat-or-head fallback internally
    local preview_cmd="'$SCRIPT_DIR/preview.sh' {1} {2}"

    # Strip leading > from prefix-based switch
    QUERY="${QUERY#>}"

    # Backspace-on-empty returns to files (home)
    local become_files_empty="$BECOME_FILES"

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
        --header 'enter open at line · ctrl-o pane · ctrl-r rename · ctrl-y copy · ⌫ files' \
        --bind "ctrl-r:become('$SCRIPT_DIR/dispatch.sh' --mode=rename --pane='$PANE_ID' --file={1})" \
        --bind "backward-eof:$become_files_empty" \
        --bind "enter:execute('$SCRIPT_DIR/actions.sh' edit-grep '$POPUP_EDITOR' '$PWD' '$HISTORY_ENABLED' {1} {2})" \
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
                local f
                for f in "${files[@]}"; do
                    [[ "$HISTORY_ENABLED" == "on" ]] && record_file_open "$PWD" "$f"
                    quoted_files="${quoted_files:+$quoted_files }$(printf '%q' "$f")"
                done
                tmux send-keys -t "$PANE_ID" "$(printf '%q' "$PANE_EDITOR") $quoted_files" Enter
            else
                tmux display-message "No target pane — use Ctrl+Y to copy instead"
            fi
            ;;
        *)
            # Enter is now handled by fzf execute() binding — this branch is a no-op
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
            # Copy file:line to system clipboard via tmux
            echo -n "$file:$line_num" | tmux load-buffer -w -
            tmux display-message "Copied: $file:$line_num"
            ;;
        ctrl-o)
            # Send open command to the originating pane (with line number)
            if [[ -n "$PANE_ID" ]]; then
                [[ "$HISTORY_ENABLED" == "on" ]] && record_file_open "$PWD" "$file"
                tmux send-keys -t "$PANE_ID" "$(printf '%q' "$PANE_EDITOR") +$line_num $(printf '%q' "$file")" Enter
            else
                tmux display-message "No target pane — use Ctrl+Y to copy instead"
            fi
            ;;
        *)
            # Enter is now handled by fzf execute() binding — this branch is a no-op
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

    local become_files="$BECOME_FILES"
    local become_new="become('$SCRIPT_DIR/dispatch.sh' --mode=session-new --pane='$PANE_ID')"

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    # Session list reload command (also used by ctrl-k kill binding)
    local session_list_cmd="'$SCRIPT_DIR/actions.sh' list-sessions"

    local result
    result=$(
        echo "$session_list" |
        fzf --print-query \
            "${base_opts[@]}" \
            --expect=ctrl-y \
            --query "$QUERY" \
            --prompt '@ ' \
            --delimiter=$'\t' \
            --nth=1 \
            --accept-nth=1 \
            --ansi \
            --no-sort \
            --border-label=' sessions ' \
            --header 'enter switch · ctrl-k kill · ctrl-r rename · ctrl-n new · ctrl-w windows · ⌫ files' \
            --preview "'$SCRIPT_DIR/session-preview.sh' {1}" \
            --bind "ctrl-r:become('$SCRIPT_DIR/dispatch.sh' --mode=rename-session --pane='$PANE_ID' --session={1})" \
            --bind "backward-eof:$become_files" \
            --bind "ctrl-n:$become_new" \
            --bind "ctrl-w:become('$SCRIPT_DIR/dispatch.sh' --mode=windows --pane='$PANE_ID' --session={1})" \
            --bind "ctrl-k:execute('$SCRIPT_DIR/actions.sh' kill-session {1})+reload:$session_list_cmd" \
    ) || exit 0

    handle_session_result "$result"
}

handle_session_result() {
    local result="$1"
    local query key selected
    local -a result_lines
    mapfile -t result_lines <<< "$result"

    query="${result_lines[0]}"
    key="${result_lines[1]:-}"
    selected="${result_lines[2]:-}"
    selected="${selected%%	*}"  # strip tab-delimited suffix (tab literal)

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
    local dir
    for dir in $session_dirs; do
        [[ -d "$dir" ]] && valid_dirs+=("$dir")
    done
    unset IFS

    if [[ ${#valid_dirs[@]} -eq 0 ]]; then
        tmux display-message "No session dirs found — set @dispatch-session-dirs '/path/one:/path/two'"
        exit 1
    fi

    # List subdirectories from all configured dirs (avoids eval)
    _run_dir_cmd() {
        local dir
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

    # Sanitize: replace any character not in [a-zA-Z0-9_-] with a dash
    session_name=$(printf '%s' "$session_name" | tr -c 'a-zA-Z0-9_-' '-')
    # Trim leading/trailing dashes
    session_name="${session_name#-}"
    session_name="${session_name%-}"

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
            --preview "'$SCRIPT_DIR/actions.sh' rename-preview $(printf '%q' "$FILE") {q}" \
            --border-label=' rename ' \
    ) || exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"

    local new_name
    new_name=$(head -1 <<< "$result")

    # Empty or unchanged → cancel
    if [[ -z "$new_name" || "$new_name" == "$FILE" ]]; then
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    # Path traversal guard — reject targets outside working directory
    local resolved
    resolved=$(realpath -m "$new_name" 2>/dev/null) || resolved="$new_name"
    if [[ "$resolved" != "$PWD"/* ]]; then
        tmux display-message "Cannot rename outside working directory"
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

# ─── Mode: dirs ───────────────────────────────────────────────────────────────

run_directory_mode() {
    # Strip leading # from prefix-based switch
    QUERY="${QUERY#\#}"

    local ZOXIDE_CMD
    ZOXIDE_CMD=$(detect_zoxide)

    # Directory listing command
    _run_dir_cmd() {
        if [[ -n "$ZOXIDE_CMD" ]]; then
            local dir
            while IFS= read -r dir; do
                printf '%s\n' "${dir/#"$HOME"/~}"
            done < <(zoxide query --list 2>/dev/null) || true
        elif [[ -n "$FD_CMD" ]]; then
            "$FD_CMD" --type d --hidden --follow --exclude .git
        else
            find . -type d -not -path '*/.git/*'
        fi
    }

    # Preview command — expand display ~ back to $HOME for tool access
    # Escape $HOME for safe sed usage (backslashes and delimiters)
    local home_escaped
    home_escaped=$(printf '%s' "$HOME" | sed 's/[|\&/]/\\&/g')
    local dir_preview
    if command -v tree &>/dev/null; then
        dir_preview="tree -C -L 2 \"\$(echo {} | sed \"s|^~|$home_escaped|\")\""
    elif ls --color=always /dev/null 2>/dev/null; then
        dir_preview="ls -la --color=always \"\$(echo {} | sed \"s|^~|$home_escaped|\")\""
    else
        dir_preview="ls -laG \"\$(echo {} | sed \"s|^~|$home_escaped|\")\""
    fi

    local become_files="$BECOME_FILES"

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(_run_dir_cmd | fzf \
        "${base_opts[@]}" \
        --expect=ctrl-y \
        --query "$QUERY" \
        --prompt '# ' \
        --preview "$dir_preview" \
        --border-label=' directories ' \
        --header 'enter cd · ctrl-y copy · ⌫ files' \
        --bind "backward-eof:$become_files" \
    ) || exit 0

    handle_directory_result "$result"
}

handle_directory_result() {
    local result="$1"
    local key dir

    key=$(head -1 <<< "$result")
    dir=$(tail -1 <<< "$result")
    [[ -z "$dir" ]] && exit 0

    # Expand display ~ back to $HOME for correct shell handling
    [[ "$dir" == "~"* ]] && dir="$HOME${dir#\~}"

    case "$key" in
        ctrl-y)
            echo -n "$dir" | tmux load-buffer -w -
            tmux display-message "Copied: $dir"
            ;;
        *)
            # Enter → send cd command to originating pane
            if [[ -n "$PANE_ID" ]]; then
                tmux send-keys -t "$PANE_ID" "cd $(printf '%q' "$dir")" Enter
            else
                tmux display-message "No target pane — use Ctrl+Y to copy instead"
            fi
            ;;
    esac
}

# ─── Mode: windows ────────────────────────────────────────────────────────────

run_windows_mode() {
    if [[ -z "$SESSION" ]]; then
        echo "No session specified for window picker."
        exit 1
    fi

    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux display-message "Session not found: $SESSION"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
    fi

    local win_list
    win_list=$(tmux list-windows -t "$SESSION" \
        -F '#{window_index}: #{window_name}  #{?window_active,*,}  (#{window_panes} panes)' 2>/dev/null)

    [[ -z "$win_list" ]] && { echo "No windows found."; exit 0; }

    local become_sessions="become('$SCRIPT_DIR/dispatch.sh' --mode=sessions --pane='$PANE_ID')"

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(
        echo "$win_list" |
        fzf \
            "${base_opts[@]}" \
            --no-cycle \
            --prompt '  ' \
            --border-label=" $SESSION windows " \
            --preview "'$SCRIPT_DIR/session-preview.sh' $(printf '%q' "$SESSION") {1}" \
            --bind "right:down" \
            --bind "left:up" \
            --bind "down:down+down" \
            --bind "up:up+up" \
            --bind "backward-eof:$become_sessions" \
    ) || exit 0

    [[ -z "$result" ]] && exit 0

    # Extract window index (first field before colon)
    local win_idx
    win_idx=$(awk -F: '{print $1}' <<< "$result")
    [[ "$win_idx" =~ ^[0-9]+$ ]] || exit 0

    tmux select-window -t "$SESSION:$win_idx"
    tmux switch-client -t "$SESSION"
}

# ─── Mode: git ────────────────────────────────────────────────────────────────

run_git_mode() {
    # Strip leading ! from prefix-based switch
    QUERY="${QUERY#!}"

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        tmux display-message "Not a git repository"
        exit 1
    fi

    # Git status: porcelain v1 → colored icons (ICON<tab>filepath)
    # Shared awk body used by both the initial load function and fzf reload string.
    # shellcheck disable=SC2016  # $0 etc. are awk variables, not bash
    local git_awk='{
        xy = substr($0, 1, 2)
        file = substr($0, 4)
        x = substr(xy, 1, 1)
        y = substr(xy, 2, 1)
        if (x == "?" && y == "?")       icon = "\033[33m?\033[0m"
        else if (x != " " && y != " ")  icon = "\033[35m✹\033[0m"
        else if (x != " ")              icon = "\033[32m✚\033[0m"
        else                            icon = "\033[31m●\033[0m"
        printf "%s\t%s\n", icon, file
    }'

    _run_git_status() { git status --porcelain 2>/dev/null | awk "$git_awk"; }

    # fzf reload string — single quotes around $git_awk protect awk's $0 from sh
    local git_status_cmd="git status --porcelain 2>/dev/null | awk '${git_awk}'"

    local become_files="$BECOME_FILES"

    # Load shared visual options
    local -a base_opts
    mapfile -t base_opts < <(build_fzf_base_opts)

    local result
    result=$(_run_git_status | fzf \
        "${base_opts[@]}" \
        --expect=ctrl-o,ctrl-y \
        --query "$QUERY" \
        --prompt '! ' \
        --ansi \
        --delimiter=$'\t' \
        --nth=2.. \
        --tabstop=3 \
        --preview "'$SCRIPT_DIR/git-preview.sh' {2..} {1}" \
        --preview-window 'right:60%:border-left' \
        --border-label=' git ' \
        --header 'tab stage/unstage · enter open · ctrl-o pane · ctrl-y copy · ⌫ files' \
        --bind "tab:execute-silent('$SCRIPT_DIR/actions.sh' git-toggle {2..})+reload:$git_status_cmd" \
        --bind "enter:execute('$SCRIPT_DIR/actions.sh' edit-file '$POPUP_EDITOR' '$PWD' '$HISTORY_ENABLED' {2..})" \
        --bind "backward-eof:$become_files" \
    ) || exit 0

    handle_git_result "$result"
}

handle_git_result() {
    local result="$1"
    local key line file

    key=$(head -1 <<< "$result")
    line=$(tail -1 <<< "$result")
    [[ -z "$line" ]] && exit 0

    # Extract file from tab-delimited format (icon\tfile)
    file=$(cut -f2 <<< "$line")
    [[ -z "$file" ]] && exit 0

    case "$key" in
        ctrl-y)
            echo -n "$file" | tmux load-buffer -w -
            tmux display-message "Copied: $file"
            ;;
        ctrl-o)
            if [[ -n "$PANE_ID" ]]; then
                [[ "$HISTORY_ENABLED" == "on" ]] && record_file_open "$PWD" "$file"
                tmux send-keys -t "$PANE_ID" "$(printf '%q' "$PANE_EDITOR") $(printf '%q' "$file")" Enter
            else
                tmux display-message "No target pane — use Ctrl+Y to copy instead"
            fi
            ;;
        *)
            # Enter is handled by fzf execute() binding
            ;;
    esac
}

# ─── Shared become string (used by grep, sessions, dirs, git) ────────────────

BECOME_FILES="become('$SCRIPT_DIR/dispatch.sh' --mode=files --pane='$PANE_ID')"

# ─── Dispatch ────────────────────────────────────────────────────────────────

case "$MODE" in
    files)          run_files_mode ;;
    grep)           run_grep_mode ;;
    git)            run_git_mode ;;
    dirs)           run_directory_mode ;;
    sessions)       run_session_mode ;;
    session-new)    run_session_new_mode ;;
    windows)        run_windows_mode ;;
    rename)         run_rename_mode ;;
    rename-session) run_rename_session_mode ;;
esac
