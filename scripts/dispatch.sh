#!/usr/bin/env bash
# =============================================================================
# dispatch.sh — Unified file finder, content search, and session picker
# =============================================================================
# Twelve modes, switchable mid-session via fzf's become action:
#
#   --mode=files          fd/find → fzf (normal filtering, bat preview)
#   --mode=grep           fzf --disabled + change:reload:rg (live search)
#   --mode=git            git status with stage/unstage toggle
#   --mode=dirs           directory picker (zoxide/fd/find)
#   --mode=sessions       tmux session picker/creator
#   --mode=session-new    directory-based session creation
#   --mode=windows        tmux window picker for a session
#   --mode=pathfind       absolute path file browsing (/ prefix)
#   --mode=rename         inline file rename (fzf query = new name)
#   --mode=rename-session inline session rename (fzf query = new name)
#   --mode=scrollback     search tmux scrollback (lines + token extraction)
#   --mode=commands        custom command palette
#   --mode=marks          global bookmarks viewer
#
# Mode switching (VSCode command palette style):
#   Files is the home mode. Prefixes step into sub-modes:
#   > prefix   — Files → grep (remainder becomes query)
#   @ prefix   — Files → sessions (remainder becomes query)
#   ! prefix   — Files → git status (remainder becomes query)
#   # prefix   — Files → directories (remainder becomes query)
#   $ prefix   — Files → scrollback search (remainder becomes query)
#   & prefix   — Files → scrollback extract/tokens (remainder becomes query)
#   : prefix   — Files → custom commands (remainder becomes query)
#   ~ prefix   — Files → files from $HOME
#   ⌫ on empty — Sub-modes → files (return to home)
#
# Usage: dispatch.sh --mode=files|grep|git|dirs|sessions|session-new|windows|rename|rename-session|scrollback|commands|marks
#        [--pane=ID] [--query=TEXT] [--file=PATH] [--session=NAME] [--view=lines|tokens]
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

# Force fzf to use bash for subcommands (avoids zsh NOMATCH on glob chars)
export SHELL="$BASH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

# ─── Parse arguments ─────────────────────────────────────────────────────────

MODE="files"
PANE_ID=""
QUERY=""
FILE=""
SESSION=""
SCROLLBACK_VIEW=""
GIT_VIEW=""

for arg in "$@"; do
    case "$arg" in
        --mode=*)      MODE="${arg#--mode=}" ;;
        --pane=*)      PANE_ID="${arg#--pane=}" ;;
        --query=*)     QUERY="${arg#--query=}" ;;
        --file=*)      FILE="${arg#--file=}" ;;
        --session=*)   SESSION="${arg#--session=}" ;;
        --view=*)      SCROLLBACK_VIEW="${arg#--view=}" ;;
        --git-view=*)  GIT_VIEW="${arg#--git-view=}" ;;
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
    files|grep|git|dirs|sessions|session-new|windows|rename|rename-session|scrollback|commands|marks|resume) ;;
    *)
        echo "Unknown mode: $MODE (expected: files, grep, git, dirs, sessions, windows, session-new, scrollback, commands, marks, resume)"
        exit 1
        ;;
esac

# ─── Resolve resume mode ──────────────────────────────────────────────────
if [[ "$MODE" == "resume" ]]; then
    MODE=$(tmux show -sv @_dispatch-last-mode 2>/dev/null) || MODE=""
    QUERY=$(tmux show -sv @_dispatch-last-query 2>/dev/null) || QUERY=""
    [[ -z "$MODE" ]] && MODE="files"
fi

# ─── Read tmux options (batched) ─────────────────────────────────────────────
# One tmux subprocess instead of separate show-option calls.
POPUP_EDITOR="" PANE_EDITOR="" FD_EXTRA_ARGS="" RG_EXTRA_ARGS=""
HISTORY_ENABLED="on" FILE_TYPES="" GIT_INDICATORS="on" ICONS_ENABLED="on" DISPATCH_THEME="default"
SCROLLBACK_LINES="10000" SCROLLBACK_VIEW_DEFAULT="lines" SESSION_DEPTH="3"
COMMANDS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-dispatch/commands.conf"
PATTERNS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-dispatch/patterns.conf"
while IFS= read -r line; do
    key="${line%% *}"
    val="${line#* }"
    val="${val#\"}" ; val="${val%\"}"
    val="${val#\'}" ; val="${val%\'}"
    case "$key" in
        @dispatch-popup-editor)    POPUP_EDITOR="$val" ;;
        @dispatch-pane-editor)     PANE_EDITOR="$val" ;;
        @dispatch-fd-args)         FD_EXTRA_ARGS="$val" ;;
        @dispatch-rg-args)         RG_EXTRA_ARGS="$val" ;;
        @dispatch-history)         HISTORY_ENABLED="$val" ;;
        @dispatch-file-types)      FILE_TYPES="$val" ;;
        @dispatch-git-indicators)  GIT_INDICATORS="$val" ;;
        @dispatch-icons)           ICONS_ENABLED="$val" ;;
        @dispatch-theme)           DISPATCH_THEME="$val" ;;
        @dispatch-scrollback-lines) SCROLLBACK_LINES="$val" ;;
        @dispatch-scrollback-view) SCROLLBACK_VIEW_DEFAULT="$val" ;;
        @dispatch-commands-file) COMMANDS_FILE="$val" ;;
        @dispatch-session-depth)       SESSION_DEPTH="$val" ;;
        @dispatch-patterns-file)       PATTERNS_FILE="$val" ;;
    esac
done < <(tmux show-options -g 2>/dev/null | grep '^@dispatch-')
POPUP_EDITOR=$(detect_popup_editor "$POPUP_EDITOR")
PANE_EDITOR=$(detect_pane_editor "$PANE_EDITOR")
# Apply default scrollback view if not overridden by --view= CLI arg
[[ -z "$SCROLLBACK_VIEW" ]] && SCROLLBACK_VIEW="$SCROLLBACK_VIEW_DEFAULT"

# ─── Read cached tool paths ──────────────────────────────────────────────────
FD_CMD=$(_dispatch_read_cached "@_dispatch-fd" detect_fd)
BAT_CMD=$(_dispatch_read_cached "@_dispatch-bat" detect_bat)
RG_CMD=$(_dispatch_read_cached "@_dispatch-rg" detect_rg)

# ─── Nerd Font icon fragments (for awk pipelines) ────────────────────────────
# Sets three awk code fragments via parent scope for splicing into annotate_awk
# and git_awk: icon_func (function def), icon_begin (BEGIN block mappings),
# icon_line (per-line printf format). When icons are off, all are no-ops.

_icon_awk_fragments() {
    if [[ "$ICONS_ENABLED" != "on" ]]; then
        icon_func=""
        icon_begin=""
        # shellcheck disable=SC2016  # $0 etc. are awk variables, not bash
        icon_line='printf "%s\t%s\n", ind, $0'
        # shellcheck disable=SC2016
        icon_git_line='printf "%s\t%s\n", icon, file'
        return
    fi

    # Generate Nerd Font characters from codepoints (keeps source readable)
    local i
    printf -v i '\xEF\x80\x96'; local nf_default="$i"    # U+F016
    printf -v i '\xEE\x9C\xBC'; local nf_python="$i"     # U+E73C
    printf -v i '\xEE\x9D\x8E'; local nf_js="$i"         # U+E74E
    printf -v i '\xEE\x98\xA8'; local nf_ts="$i"          # U+E628
    printf -v i '\xEE\x9E\xA8'; local nf_rust="$i"        # U+E7A8
    printf -v i '\xEE\x98\xA7'; local nf_go="$i"          # U+E627
    printf -v i '\xEE\x9E\x91'; local nf_ruby="$i"        # U+E791
    printf -v i '\xEE\x98\xA0'; local nf_lua="$i"         # U+E620
    printf -v i '\xEF\x92\x89'; local nf_term="$i"        # U+F489
    printf -v i '\xEE\x9C\xBE'; local nf_md="$i"          # U+E73E
    printf -v i '\xEE\x98\x8B'; local nf_json="$i"        # U+E60B
    printf -v i '\xEE\x9C\xB6'; local nf_html="$i"        # U+E736
    printf -v i '\xEE\x9D\x89'; local nf_css="$i"         # U+E749
    printf -v i '\xEE\x98\x83'; local nf_sass="$i"        # U+E603
    printf -v i '\xEE\x98\x9E'; local nf_c="$i"           # U+E61E
    printf -v i '\xEE\x98\x9D'; local nf_cpp="$i"         # U+E61D
    printf -v i '\xEE\x9C\xB8'; local nf_java="$i"        # U+E738
    printf -v i '\xEE\x98\xB4'; local nf_kotlin="$i"      # U+E634
    printf -v i '\xEE\x9D\x95'; local nf_swift="$i"       # U+E755
    printf -v i '\xEE\x9C\xBD'; local nf_php="$i"         # U+E73D
    printf -v i '\xEE\x9D\xA9'; local nf_perl="$i"        # U+E769
    printf -v i '\xEE\x98\xAB'; local nf_vim="$i"         # U+E62B
    printf -v i '\xEE\x98\x95'; local nf_config="$i"      # U+E615
    printf -v i '\xEE\x9C\x86'; local nf_db="$i"          # U+E706
    printf -v i '\xEF\x80\xA3'; local nf_lock="$i"        # U+F023
    printf -v i '\xEF\x80\xBE'; local nf_image="$i"       # U+F03E
    printf -v i '\xEF\x86\x87'; local nf_archive="$i"     # U+F187
    printf -v i '\xEF\x87\x81'; local nf_pdf="$i"         # U+F1C1
    printf -v i '\xEF\x85\x9C'; local nf_text="$i"        # U+F15C
    printf -v i '\xEE\x9E\xB0'; local nf_docker="$i"      # U+E7B0
    printf -v i '\xEE\x99\x9D'; local nf_git="$i"         # U+E65D
    printf -v i '\xEE\x9C\x9E'; local nf_npm="$i"         # U+E71E
    printf -v i '\xEE\x9D\xB7'; local nf_haskell="$i"     # U+E777
    printf -v i '\xEE\x98\xAD'; local nf_elixir="$i"      # U+E62D
    printf -v i '\xEF\x8C\x93'; local nf_nix="$i"         # U+F313
    printf -v i '\xEE\x98\x8A'; local nf_license="$i"     # U+E60A
    printf -v i '\xEF\x85\xAD'; local nf_r="$i"           # U+F16D
    printf -v i '\xEE\x9C\xAA'; local nf_react="$i"       # U+E7BA

    # shellcheck disable=SC2016  # $0 etc. are awk variables, not bash
    icon_func='function get_icon(path,   name, ext) {
    name = path; sub(/.*\//, "", name); sub(/^\.\//, "", name)
    if (name in icon_name) return icon_name[name]
    ext = name
    if (match(ext, /\.[^.]+$/)) {
        ext = tolower(substr(ext, RSTART + 1))
        if (ext in icon_ext) return icon_ext[ext]
    }
    return def_icon
}
'

    # BEGIN block: extension + filename mappings with ANSI colors
    # Colors: 31=red, 32=green, 33=yellow, 34=blue, 35=magenta, 36=cyan, 37=gray
    icon_begin="def_icon = \"\033[37m${nf_default} \033[0m\"
    icon_ext[\"py\"] = \"\033[33m${nf_python} \033[0m\"
    icon_ext[\"js\"] = \"\033[33m${nf_js} \033[0m\"
    icon_ext[\"jsx\"] = \"\033[36m${nf_react} \033[0m\"
    icon_ext[\"ts\"] = \"\033[34m${nf_ts} \033[0m\"
    icon_ext[\"tsx\"] = \"\033[34m${nf_react} \033[0m\"
    icon_ext[\"rs\"] = \"\033[31m${nf_rust} \033[0m\"
    icon_ext[\"go\"] = \"\033[36m${nf_go} \033[0m\"
    icon_ext[\"rb\"] = \"\033[31m${nf_ruby} \033[0m\"
    icon_ext[\"lua\"] = \"\033[34m${nf_lua} \033[0m\"
    icon_ext[\"sh\"] = \"\033[32m${nf_term} \033[0m\"
    icon_ext[\"bash\"] = \"\033[32m${nf_term} \033[0m\"
    icon_ext[\"zsh\"] = \"\033[32m${nf_term} \033[0m\"
    icon_ext[\"fish\"] = \"\033[32m${nf_term} \033[0m\"
    icon_ext[\"md\"] = \"\033[37m${nf_md} \033[0m\"
    icon_ext[\"json\"] = \"\033[33m${nf_json} \033[0m\"
    icon_ext[\"yaml\"] = \"\033[37m${nf_config} \033[0m\"
    icon_ext[\"yml\"] = \"\033[37m${nf_config} \033[0m\"
    icon_ext[\"html\"] = \"\033[33m${nf_html} \033[0m\"
    icon_ext[\"htm\"] = \"\033[33m${nf_html} \033[0m\"
    icon_ext[\"css\"] = \"\033[34m${nf_css} \033[0m\"
    icon_ext[\"scss\"] = \"\033[35m${nf_sass} \033[0m\"
    icon_ext[\"sass\"] = \"\033[35m${nf_sass} \033[0m\"
    icon_ext[\"c\"] = \"\033[34m${nf_c} \033[0m\"
    icon_ext[\"h\"] = \"\033[34m${nf_c} \033[0m\"
    icon_ext[\"cpp\"] = \"\033[34m${nf_cpp} \033[0m\"
    icon_ext[\"hpp\"] = \"\033[34m${nf_cpp} \033[0m\"
    icon_ext[\"cc\"] = \"\033[34m${nf_cpp} \033[0m\"
    icon_ext[\"java\"] = \"\033[31m${nf_java} \033[0m\"
    icon_ext[\"kt\"] = \"\033[35m${nf_kotlin} \033[0m\"
    icon_ext[\"swift\"] = \"\033[33m${nf_swift} \033[0m\"
    icon_ext[\"php\"] = \"\033[35m${nf_php} \033[0m\"
    icon_ext[\"pl\"] = \"\033[36m${nf_perl} \033[0m\"
    icon_ext[\"vim\"] = \"\033[32m${nf_vim} \033[0m\"
    icon_ext[\"conf\"] = \"\033[37m${nf_config} \033[0m\"
    icon_ext[\"cfg\"] = \"\033[37m${nf_config} \033[0m\"
    icon_ext[\"ini\"] = \"\033[37m${nf_config} \033[0m\"
    icon_ext[\"toml\"] = \"\033[37m${nf_config} \033[0m\"
    icon_ext[\"xml\"] = \"\033[33m${nf_html} \033[0m\"
    icon_ext[\"sql\"] = \"\033[33m${nf_db} \033[0m\"
    icon_ext[\"lock\"] = \"\033[37m${nf_lock} \033[0m\"
    icon_ext[\"png\"] = \"\033[35m${nf_image} \033[0m\"
    icon_ext[\"jpg\"] = \"\033[35m${nf_image} \033[0m\"
    icon_ext[\"jpeg\"] = \"\033[35m${nf_image} \033[0m\"
    icon_ext[\"gif\"] = \"\033[35m${nf_image} \033[0m\"
    icon_ext[\"svg\"] = \"\033[35m${nf_image} \033[0m\"
    icon_ext[\"ico\"] = \"\033[35m${nf_image} \033[0m\"
    icon_ext[\"webp\"] = \"\033[35m${nf_image} \033[0m\"
    icon_ext[\"ttf\"] = \"\033[37m${nf_default} \033[0m\"
    icon_ext[\"otf\"] = \"\033[37m${nf_default} \033[0m\"
    icon_ext[\"woff\"] = \"\033[37m${nf_default} \033[0m\"
    icon_ext[\"woff2\"] = \"\033[37m${nf_default} \033[0m\"
    icon_ext[\"zip\"] = \"\033[31m${nf_archive} \033[0m\"
    icon_ext[\"tar\"] = \"\033[31m${nf_archive} \033[0m\"
    icon_ext[\"gz\"] = \"\033[31m${nf_archive} \033[0m\"
    icon_ext[\"bz2\"] = \"\033[31m${nf_archive} \033[0m\"
    icon_ext[\"xz\"] = \"\033[31m${nf_archive} \033[0m\"
    icon_ext[\"7z\"] = \"\033[31m${nf_archive} \033[0m\"
    icon_ext[\"pdf\"] = \"\033[31m${nf_pdf} \033[0m\"
    icon_ext[\"txt\"] = \"\033[37m${nf_text} \033[0m\"
    icon_ext[\"log\"] = \"\033[37m${nf_text} \033[0m\"
    icon_ext[\"nix\"] = \"\033[34m${nf_nix} \033[0m\"
    icon_ext[\"ex\"] = \"\033[35m${nf_elixir} \033[0m\"
    icon_ext[\"exs\"] = \"\033[35m${nf_elixir} \033[0m\"
    icon_ext[\"hs\"] = \"\033[35m${nf_haskell} \033[0m\"
    icon_ext[\"r\"] = \"\033[34m${nf_r} \033[0m\"
    icon_ext[\"zig\"] = \"\033[33m${nf_default} \033[0m\"
    icon_ext[\"jl\"] = \"\033[35m${nf_default} \033[0m\"
    icon_name[\"Dockerfile\"] = \"\033[34m${nf_docker} \033[0m\"
    icon_name[\"Makefile\"] = \"\033[37m${nf_config} \033[0m\"
    icon_name[\"LICENSE\"] = \"\033[33m${nf_license} \033[0m\"
    icon_name[\".gitignore\"] = \"\033[31m${nf_git} \033[0m\"
    icon_name[\".gitconfig\"] = \"\033[31m${nf_git} \033[0m\"
    icon_name[\".gitmodules\"] = \"\033[31m${nf_git} \033[0m\"
    icon_name[\".env\"] = \"\033[33m${nf_config} \033[0m\"
    icon_name[\".editorconfig\"] = \"\033[37m${nf_config} \033[0m\"
    icon_name[\"package.json\"] = \"\033[31m${nf_npm} \033[0m\"
    icon_name[\"Cargo.toml\"] = \"\033[31m${nf_rust} \033[0m\"
    icon_name[\"go.mod\"] = \"\033[36m${nf_go} \033[0m\"
    icon_name[\"docker-compose.yml\"] = \"\033[34m${nf_docker} \033[0m\"
    icon_name[\"docker-compose.yaml\"] = \"\033[34m${nf_docker} \033[0m\"
    icon_name[\"tsconfig.json\"] = \"\033[34m${nf_ts} \033[0m\"
    icon_name[\"README.md\"] = \"\033[33m${nf_md} \033[0m\""

    # Per-line output formats (3 columns: indicator, icon, path)
    # shellcheck disable=SC2016
    icon_line='printf "%s\t%s\t%s\n", ind, get_icon(f), $0'
    # shellcheck disable=SC2016
    icon_git_line='printf "%s\t%s\t%s\n", icon, get_icon(file), file'
}

# ─── Escape values for fzf bind strings ──────────────────────────────────────
# fzf execute()/become() commands run via $SHELL -c. Variables embedded in
# single-quoted arguments need ' escaped as '\'' to prevent command breakage
# when paths contain single quotes (e.g. /home/user/it's-a-project/).
SQ_SCRIPT_DIR=$(_sq_escape "$SCRIPT_DIR")
SQ_PWD=$(_sq_escape "$PWD")
SQ_POPUP_EDITOR=$(_sq_escape "$POPUP_EDITOR")
SQ_PANE_ID=$(_sq_escape "$PANE_ID")
SQ_HISTORY=$(_sq_escape "$HISTORY_ENABLED")

# Shared become string used by grep, sessions, dirs, git to switch back to files
BECOME_FILES="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=files --pane='$SQ_PANE_ID')"

# ─── Empty state helper ───────────────────────────────────────────────────
# Show a minimal fzf with the error as --header so the user sees it in context
# (prompt, border-label) instead of a fleeting tmux status-bar message.
# Backspace → files mode; Esc → close popup.
_show_empty_state() {
    local message="$1"
    local prompt="$2"
    local border_label="$3"
    printf '' | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --header "$message" \
        --prompt "$prompt" \
        --border-label "$border_label" \
        --border-label-pos 'center:bottom' \
        --bind "backward-eof:$BECOME_FILES"
    exit 0
}

# ─── Require fzf ────────────────────────────────────────────────────────────

command -v fzf &>/dev/null || {
    echo "fzf is required for tmux-dispatch."
    echo "Install: apt install fzf  OR  brew install fzf  OR  https://github.com/junegunn/fzf#installation"
    exit 1
}

fzf_version=$(tmux show -sv @_dispatch-fzf-version 2>/dev/null) || fzf_version=""
if [[ -z "$fzf_version" ]]; then
    fzf_version=$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
fi
if [[ -n "$fzf_version" ]]; then
    _fzf_below() { [[ "$(printf '%s\n%s' "$1" "$fzf_version" | sort -V | head -n1)" != "$1" ]]; }
    if _fzf_below "0.38"; then
        echo "Error: fzf 0.38+ required for mode switching (found $fzf_version)." >&2
        echo "Install latest: https://github.com/junegunn/fzf#installation" >&2
    elif _fzf_below "0.45"; then
        echo "Warning: fzf 0.45+ recommended (found $fzf_version). Dynamic labels require 0.45+." >&2
    fi
    unset -f _fzf_below
fi

# ─── Pre-compute shared fzf options ───────────────────────────────────────────
declare -a BASE_FZF_OPTS
mapfile -t BASE_FZF_OPTS < <(build_fzf_base_opts "$DISPATCH_THEME")

# ─── Context-sensitive help strings ───────────────────────────────────────────
# Shown when user presses ? in any mode. Uses preview:echo to temporarily
# replace the preview pane; cursor movement restores normal preview.

HELP_FILES="$(printf '%b' '
  \033[1mFILES\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     open in editor
  tab       select
  ^O        send to pane
  ^Y        copy path
  ^B        toggle bookmark
  ^H        toggle hidden files
  ^R        rename file
  ^X        delete file
  ^D/^U     scroll preview

  \033[1mMODE SWITCHING\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  >...      grep code
  @...      switch sessions
  !...      git status
  #...      directories
  $...      scrollback search
  &...      extract tokens
  :...      custom commands
  ~...      files from home
  /...      browse by path
')"

HELP_GREP="$(printf '%b' '
  \033[1mGREP\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     open at line
  ^O        send to pane
  ^Y        copy file:line
  ^F        toggle filter / search
  ^R        rename file
  ^X        delete file
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"

HELP_GIT="$(printf '%b' '
  \033[1mGIT\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  tab       stage / unstage
  enter     open in editor
  ^O        send to pane
  ^Y        copy path
  ^R        rename file
  ^X        delete file
  ^L        log view
  ^S        branch view
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"

HELP_GIT_LOG="$(printf '%b' '
  \033[1mGIT LOG\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     copy commit hash
  tab       select multiple
  ^O        cherry-pick
  ^Y        copy hash(es)
  ^L        back to status
  ^S        branches
  ⌫ empty   back to status

  ^D/^U     scroll preview
')"

HELP_GIT_BRANCH="$(printf '%b' '
  \033[1mGIT BRANCHES\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     switch branch
  ^Y        copy name
  ^S        back to status
  ^L        log
  ⌫ empty   back to status

  ^D/^U     scroll preview
')"

HELP_SESSIONS="$(printf '%b' '
  \033[1mSESSIONS\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     switch session
  ^Y        copy name
  ^K        kill session
  ^R        rename session
  ^N        new session
  ^W        window picker
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"

HELP_DIRS="$(printf '%b' '
  \033[1mDIRECTORIES\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     cd to directory
  ^Y        copy path
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"

HELP_WINDOWS="$(printf '%b' '
  \033[1mWINDOWS\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  ←→        move one
  ↑↓        skip two
  enter     switch window
  ^Y        copy window ref
  ⌫ empty   back to sessions

  ^D/^U     scroll preview
')"

HELP_SESSION_NEW="$(printf '%b' '
  \033[1mNEW SESSION\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     create / switch session
  ⌫ empty   back to sessions

  git repos show branch · \033[32m★\033[0m = session exists

  ^D/^U     scroll preview
')"

# Pre-escape help strings for safe embedding in fzf bind strings
SQ_HELP_FILES=$(_sq_escape "$HELP_FILES")
SQ_HELP_GREP=$(_sq_escape "$HELP_GREP")
SQ_HELP_GIT=$(_sq_escape "$HELP_GIT")
SQ_HELP_GIT_LOG=$(_sq_escape "$HELP_GIT_LOG")
SQ_HELP_GIT_BRANCH=$(_sq_escape "$HELP_GIT_BRANCH")
SQ_HELP_SESSIONS=$(_sq_escape "$HELP_SESSIONS")
SQ_HELP_DIRS=$(_sq_escape "$HELP_DIRS")
SQ_HELP_WINDOWS=$(_sq_escape "$HELP_WINDOWS")
SQ_HELP_SESSION_NEW=$(_sq_escape "$HELP_SESSION_NEW")

HELP_SCROLLBACK="$(printf '%b' '
  \033[1mSCROLLBACK (lines)\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     copy to clipboard
  ^O        paste to pane
  ^T        switch to extract
  tab       select
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"

HELP_COMMANDS="$(printf '%b' '
  \033[1mCOMMANDS\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     run command
  ^E        edit commands.conf
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"

HELP_MARKS="$(printf '%b' '
  \033[1mMARKS\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     open in editor
  ^O        send to pane
  ^Y        copy path
  ^B        unbookmark
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"

HELP_PATH="$(printf '%b' '
  \033[1mPATH\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     open in editor
  ^O        send to pane
  ^Y        copy path
  ⌫ empty   back to files

  Type absolute path to find files.

  ^D/^U     scroll preview
')"

SQ_HELP_SCROLLBACK=$(_sq_escape "$HELP_SCROLLBACK")
SQ_HELP_COMMANDS=$(_sq_escape "$HELP_COMMANDS")
SQ_HELP_MARKS=$(_sq_escape "$HELP_MARKS")
SQ_HELP_PATH=$(_sq_escape "$HELP_PATH")
# SQ_HELP_EXTRACT is built lazily in run_scrollback_mode() to include custom types

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
        # Escape ERE metacharacters in extensions (e.g., c++ → c\+\+)
        local ext_re
        # shellcheck disable=SC2001  # ERE char class needs sed, not ${//}
        ext_re=$(IFS='|'; exts_arr=(); for e in "${exts[@]}"; do e="${e## }"; e="${e%% }"; [[ -n "$e" ]] && exts_arr+=("$(sed 's/[][\\.^$*+?{}()|]/\\&/g' <<< "$e")"); done; echo "${exts_arr[*]}")
        # ext_filter_str MUST start with "| " (pipe) or be empty — it's
        # spliced into fzf reload strings as a pipeline stage after bash -c.
        ext_filter_str="| grep -E '\\.($ext_re)$'"
        _ext_filter() { grep -E "\\.(${ext_re})$" || true; }
    fi

    # Two variants: with and without hidden files (toggled by Ctrl+H at runtime)
    local file_cmd file_cmd_nohidden
    if [[ -n "$FD_CMD" ]]; then
        local strip_prefix=""
        "$FD_CMD" --help 2>&1 | grep -q -- '--strip-cwd-prefix' && strip_prefix="--strip-cwd-prefix"
        file_cmd="$FD_CMD --type f --hidden --follow --exclude .git $strip_prefix$type_flags_str $FD_EXTRA_ARGS"
        file_cmd_nohidden="$FD_CMD --type f --follow --exclude .git $strip_prefix$type_flags_str $FD_EXTRA_ARGS"
    else
        file_cmd="find . -type f -not -path '*/.git/*'${find_name_filter:+ $find_name_filter}"
        file_cmd_nohidden="find . -type f -not -name '.*' -not -path '*/.git/*' -not -path '*/.*/*'${find_name_filter:+ $find_name_filter}"
    fi

    # Hidden-toggle flag: when file exists, hidden files are shown (the default)
    local hidden_flag
    hidden_flag=$(mktemp "${TMPDIR:-/tmp}/dispatch-hidden-XXXXXX")

    _run_file_cmd() {
        if [[ -n "$FD_CMD" ]]; then
            "$FD_CMD" --type f --hidden --follow --exclude .git \
                ${strip_prefix:+"$strip_prefix"} "${type_flags[@]}" "${fd_extra_args_arr[@]}"
        else
            find . -type f -not -path '*/.git/*' "${find_name_args[@]}"
        fi
    }

    # ─── File indicators (bookmarks + git status + icons) ───────────────────────
    # Build the awk annotation script and define _annotate_files().
    # Sets: fzf_file, fzf_files, nth_field, cut_field, annotate_awk, bf, do_git, git_prefix
    # Defines: _annotate_files()
    local fzf_file fzf_files nth_field cut_field bf do_git git_prefix annotate_awk
    local icon_func icon_begin icon_line icon_git_line

    _build_annotate_awk() {
        # Tab-delimited: indicators\t[icon\t]filename.
        # Indicator column: ★ for bookmarked, git icon for dirty files.
        # Icon column: Nerd Font file-type icon (when icons=on).
        _icon_awk_fragments
        if [[ "$ICONS_ENABLED" == "on" ]]; then
            fzf_file="{3..}" fzf_files="{+3..}"
            nth_field="3.." cut_field="3-"
        else
            fzf_file="{2..}" fzf_files="{+2..}"
            nth_field="2.." cut_field="2-"
        fi

        bf=$(_dispatch_bookmark_file)
        local git_active=false
        git_prefix=""
        if [[ "$GIT_INDICATORS" == "on" ]] && git rev-parse --is-inside-work-tree &>/dev/null; then
            git_active=true
            git_prefix=$(git rev-parse --show-prefix 2>/dev/null)
        fi
        do_git=0
        $git_active && do_git=1

        # shellcheck disable=SC2016  # $0 etc. are awk variables, not bash
        annotate_awk="${icon_func}"'BEGIN {
    '"${icon_begin}"'
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
    '"${icon_line}"'
}'

        _annotate_files() {
            awk -v bfile="$bf" -v pwd="$PWD" -v do_git="$do_git" -v prefix="$git_prefix" "$annotate_awk"
        }
    }
    _build_annotate_awk

    # File preview command (bat or head fallback)
    local file_preview
    if [[ -n "$BAT_CMD" ]]; then
        file_preview="$BAT_CMD --color=always --style=numbers --line-range=:500 $fzf_file"
    else
        file_preview="head -500 $fzf_file"
    fi

    trap 'command rm -f "$hidden_flag"' EXIT

    # change:transform: prefix detection → become mode switch
    local change_transform
    change_transform="if [[ {q} == '>'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=grep --pane='$SQ_PANE_ID' --query={q})\"
elif [[ {q} == '@'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=sessions --pane='$SQ_PANE_ID' --query={q})\"
elif [[ {q} == '!'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=git --pane='$SQ_PANE_ID' --query={q})\"
elif [[ {q} == '#'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=dirs --pane='$SQ_PANE_ID' --query={q})\"
elif [[ {q} == '\$'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=scrollback --pane='$SQ_PANE_ID' --query={q})\"
elif [[ {q} == '&'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=scrollback --view=tokens --pane='$SQ_PANE_ID' --query={q})\"
elif [[ {q} == ':'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=commands --pane='$SQ_PANE_ID' --query={q})\"
elif [[ {q} == '/'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=pathfind --pane='$SQ_PANE_ID' --query={q})\"
elif [[ {q} == '~'* ]]; then
  echo \"become(cd ~ && '$SQ_SCRIPT_DIR/dispatch.sh' --mode=files --pane='$SQ_PANE_ID')\"
fi"

    # ─── Reload command construction ────────────────────────────────────────────
    # Build the file list command used by fzf reload bindings.
    # Sets: file_list_cmd, sq_hidden_flag (also used by ctrl-h binding)
    local file_list_cmd sq_hidden_flag

    _build_file_list_cmd() {
        # Reloadable file list command (bookmarks + frecency + files, deduped).
        # Used by fzf reload bindings (ctrl-x, ctrl-b).
        # Quoting: outer "..." expands $SCRIPT_DIR/$PWD/$file_cmd at definition time;
        # inner '...' passed to bash -c protects awk's $0 and function calls from sh.
        local sq_bf
        sq_bf=$(_sq_escape "$bf")
        local sq_git_prefix
        sq_git_prefix=$(_sq_escape "$git_prefix")
        local annotate_cmd="awk -v bfile='$sq_bf' -v pwd='$SQ_PWD' -v do_git=$do_git -v prefix='$sq_git_prefix' '${annotate_awk}'"
        sq_hidden_flag=$(_sq_escape "$hidden_flag")
        # file_list_cmd: conditional on hidden_flag — if flag exists, show hidden; otherwise hide them
        local file_list_cmd_hidden file_list_cmd_nohidden
        if [[ "$HISTORY_ENABLED" == "on" ]]; then
            file_list_cmd_hidden="bash -c 'source \"$SQ_SCRIPT_DIR/helpers.sh\"; { bookmarks_for_pwd \"$SQ_PWD\"; recent_files_for_pwd \"$SQ_PWD\"; $file_cmd; } | dedup_lines' $ext_filter_str | $annotate_cmd"
            file_list_cmd_nohidden="bash -c 'source \"$SQ_SCRIPT_DIR/helpers.sh\"; { bookmarks_for_pwd \"$SQ_PWD\"; recent_files_for_pwd \"$SQ_PWD\"; $file_cmd_nohidden; } | dedup_lines' $ext_filter_str | $annotate_cmd"
        else
            file_list_cmd_hidden="bash -c 'source \"$SQ_SCRIPT_DIR/helpers.sh\"; { bookmarks_for_pwd \"$SQ_PWD\"; $file_cmd; } | dedup_lines' $ext_filter_str | $annotate_cmd"
            file_list_cmd_nohidden="bash -c 'source \"$SQ_SCRIPT_DIR/helpers.sh\"; { bookmarks_for_pwd \"$SQ_PWD\"; $file_cmd_nohidden; } | dedup_lines' $ext_filter_str | $annotate_cmd"
        fi
        file_list_cmd="if [ -f '$sq_hidden_flag' ]; then $file_list_cmd_hidden; else $file_list_cmd_nohidden; fi"
    }
    _build_file_list_cmd

    # Tool-missing hints: show tips when optional tools are absent
    local header=""
    [[ -z "$FD_CMD" ]] && header="tip: install fd for faster search with .gitignore support"
    [[ -z "$BAT_CMD" ]] && header="${header:+$header  ·  }tip: install bat for syntax-highlighted preview"
    local -a header_args=()
    [[ -n "$header" ]] && header_args=(--header "$header")

    local files_prompt='  '
    local files_border_label=' files · ? help · enter open · tab select · ^o pane · ^y copy · ^b mark · ^g marks · ^h hidden · ^r rename · ^x delete '
    if [[ "$PWD" == "$HOME" ]]; then
        # shellcheck disable=SC2088  # Literal ~/ for display, not expansion
        files_prompt='~/ '
        # shellcheck disable=SC2088
        files_border_label=' files ~/ · ? help · enter open · tab select · ^o pane · ^y copy · ^b mark · ^g marks · ^h hidden · ^r rename · ^x delete '
    fi

    local result
    result=$(
        if [[ "$HISTORY_ENABLED" == "on" ]]; then
            { bookmarks_for_pwd "$PWD"; recent_files_for_pwd "$PWD"; _run_file_cmd; } | awk '!seen[$0]++' | _ext_filter
        else
            { bookmarks_for_pwd "$PWD"; _run_file_cmd; } | awk '!seen[$0]++' | _ext_filter
        fi | _annotate_files | fzf \
        "${BASE_FZF_OPTS[@]}" \
        "${header_args[@]}" \
        --ansi --delimiter=$'\t' --nth="$nth_field" --tabstop=3 \
        --expect=ctrl-o,ctrl-y \
        --multi \
        --query "$QUERY" \
        --prompt "$files_prompt" \
        --preview "$file_preview" \
        --preview-label=" preview " \
        --border-label "$files_border_label" \
        --border-label-pos 'center:bottom' \
        --bind "change:transform:$change_transform" \
        --bind "focus:change-preview-label( preview )" \
        --bind "ctrl-r:become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=rename --pane='$SQ_PANE_ID' --file=$fzf_file)" \
        --bind "ctrl-g:become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=marks --pane='$SQ_PANE_ID')" \
        --bind "ctrl-x:execute('$SQ_SCRIPT_DIR/actions.sh' delete-files $fzf_files)+reload:$file_list_cmd" \
        --bind "ctrl-b:execute-silent('$SQ_SCRIPT_DIR/actions.sh' bookmark-toggle '$SQ_PWD' $fzf_file)+reload:$file_list_cmd" \
        --bind "ctrl-h:execute-silent(if [ -f '$sq_hidden_flag' ]; then command rm -f '$sq_hidden_flag'; else touch '$sq_hidden_flag'; fi)+reload:$file_list_cmd" \
        --bind "enter:execute('$SQ_SCRIPT_DIR/actions.sh' edit-file '$SQ_POPUP_EDITOR' '$SQ_PWD' '$SQ_HISTORY' $fzf_files)" \
        --bind "?:preview:printf '%b' '$SQ_HELP_FILES'" \
    ) || exit 0

    # Strip indicator (+ icon) prefix from fzf output.
    # cut passes through lines without tabs (the --expect key line).
    if [[ -n "$result" ]]; then
        result=$(cut -f"$cut_field" <<< "$result")
    fi

    handle_file_result "$result"
}

# ─── Mode: grep ──────────────────────────────────────────────────────────────

run_grep_mode() {
    if [[ -z "$RG_CMD" ]]; then
        _show_empty_state \
            "grep requires ripgrep (rg) — install: brew/apt install ripgrep" \
            "grep > " \
            " grep > · ⌫ files "
    fi

    # Preview command: preview.sh handles bat-or-head fallback internally
    local preview_cmd="'$SQ_SCRIPT_DIR/preview.sh' {1} {2}"

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

    # Ctrl+F toggle: switch between live rg search (--disabled) and fuzzy filter on results
    local grep_toggle="if [[ \$FZF_PROMPT == 'grep > ' ]]; then echo 'unbind(change)+enable-search+change-prompt(filter > )'; else echo 'change-prompt(grep > )+disable-search+rebind(change)+reload:$rg_reload'; fi"

    local result
    result=$(_run_initial_rg | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --expect=ctrl-o,ctrl-y \
        --disabled \
        --query "$QUERY" \
        --prompt 'grep > ' \
        --ansi \
        --delimiter ':' \
        --bind "change:reload:$rg_reload" \
        --preview "$preview_cmd" \
        --preview-window 'right:60%:border-left:+{2}/2' \
        --border-label ' grep > · ? help · enter open · ^o pane · ^y copy · ^f filter · ^r rename · ^x delete · ⌫ files ' \
        --border-label-pos 'center:bottom' \
        --bind "ctrl-f:transform:$grep_toggle" \
        --bind "ctrl-r:become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=rename --pane='$SQ_PANE_ID' --file={1})" \
        --bind "ctrl-x:execute('$SQ_SCRIPT_DIR/actions.sh' delete-files {1})+reload:$rg_reload" \
        --bind "backward-eof:$become_files_empty" \
        --bind "enter:execute('$SQ_SCRIPT_DIR/actions.sh' edit-grep '$SQ_POPUP_EDITOR' '$SQ_PWD' '$SQ_HISTORY' {1} {2})" \
        --bind "?:preview:printf '%b' '$SQ_HELP_GREP'" \
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
                if tmux send-keys -t "$PANE_ID" "$PANE_EDITOR $quoted_files" Enter; then
                    tmux display-message "Sent ${#files[@]} file(s) to pane"
                else
                    _dispatch_error "Failed to send to pane $PANE_ID — is it still open?"
                fi
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
                if tmux send-keys -t "$PANE_ID" "$PANE_EDITOR +$line_num $(printf '%q' "$file")" Enter; then
                    tmux display-message "Sent to pane: $file:$line_num"
                else
                    _dispatch_error "Failed to send to pane $PANE_ID — is it still open?"
                fi
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
    # Build session list via shared helper (also used by reload)
    local session_list
    session_list=$("$SCRIPT_DIR/actions.sh" list-sessions)

    [ -z "$session_list" ] && { _dispatch_error "no sessions found"; exit 0; }

    local become_files="$BECOME_FILES"
    local become_new="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=session-new --pane='$SQ_PANE_ID')"

    # Session list reload command (also used by ctrl-k kill binding)
    local session_list_cmd="'$SQ_SCRIPT_DIR/actions.sh' list-sessions"

    local result
    result=$(
        echo "$session_list" |
        fzf --print-query \
            "${BASE_FZF_OPTS[@]}" \
            --expect=ctrl-y \
            --query "$QUERY" \
            --prompt 'sessions @ ' \
            --delimiter=$'\t' \
            --nth=1 \
            --accept-nth=1 \
            --ansi \
            --no-sort \
            --border-label ' sessions @ · ? help · enter switch · ^k kill · ^r rename · ^n new · ^w win · ⌫ files ' \
            --border-label-pos 'center:bottom' \
            --preview "'$SQ_SCRIPT_DIR/session-preview.sh' {1}" \
            --bind "ctrl-r:become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=rename-session --pane='$SQ_PANE_ID' --session={1})" \
            --bind "backward-eof:$become_files" \
            --bind "ctrl-n:$become_new" \
            --bind "ctrl-w:become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=windows --pane='$SQ_PANE_ID' --session={1})" \
            --bind "ctrl-k:execute('$SQ_SCRIPT_DIR/actions.sh' kill-session {1})+reload:$session_list_cmd" \
            --bind "?:preview:printf '%b' '$SQ_HELP_SESSIONS'" \
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
            # Switch to existing session, or create with sanitized name
            if ! tmux switch-client -t "=$selected" 2>/dev/null; then
                # Sanitize: replace characters invalid in tmux session names
                local sanitized
                sanitized=$(printf '%s' "$selected" | sed 's/[^a-zA-Z0-9_-]/-/g')
                sanitized="${sanitized#-}"
                sanitized="${sanitized%-}"
                [[ -z "$sanitized" ]] && exit 0
                tmux new-session -d -s "$sanitized" && tmux switch-client -t "=$sanitized"
                if [[ "$sanitized" != "$selected" ]]; then
                    tmux display-message "Created session: $sanitized (sanitized from: $selected)"
                fi
            fi
            ;;
    esac
}

# ─── Session-new helpers ───────────────────────────────────────────────────

# Discover git repos (deep) + non-git dirs (depth 1) from session dirs.
# Output: full-path\tshort-name\tbranch [★]  (3 tab-delimited fields)
# Field 1 (hidden): absolute path for preview/selection
# Field 2 (displayed): tilde-collapsed path + ★ indicator (branch shown in preview only)
_discover_session_targets() {
    local -a valid_dirs=("$@")
    local -A seen_paths=()

    # Phase 1: Git repos (deep scan up to SESSION_DEPTH)
    local dir repo_path indicator line short_name
    for dir in "${valid_dirs[@]}"; do
        local git_dirs=""
        if [[ -n "$FD_CMD" ]]; then
            git_dirs=$("$FD_CMD" --hidden --no-ignore --glob '.git' --type d \
                --max-depth "$SESSION_DEPTH" "$dir" 2>/dev/null) || true
        else
            git_dirs=$(find "$dir" -maxdepth "$SESSION_DEPTH" -name .git -type d 2>/dev/null) || true
        fi

        [[ -z "$git_dirs" ]] && continue

        while IFS= read -r line; do
            # Strip trailing slash (fd outputs dir/) then /.git suffix
            line="${line%/}"
            repo_path="${line%/.git}"
            [[ -d "$repo_path" ]] || continue
            [[ -v "seen_paths[$repo_path]" ]] && continue
            seen_paths["$repo_path"]=1

            # Check if session already exists
            local session_name
            session_name=$(basename "$repo_path")
            session_name=$(printf '%s' "$session_name" | sed 's/[^a-zA-Z0-9_-]/-/g')
            session_name="${session_name#-}"
            session_name="${session_name%-}"
            indicator=""
            if tmux has-session -t "=$session_name" 2>/dev/null; then
                indicator=$' \033[32m★\033[0m'
            fi

            # Short display: tilde-collapse HOME prefix
            # shellcheck disable=SC2088
            short_name="${repo_path/#"$HOME"/"~"}"

            printf '%s\t%s%s\n' "$repo_path" "$short_name" "$indicator"
        done <<< "$git_dirs"
    done

    # Phase 2: Non-git depth-1 dirs (backward compat fallback)
    for dir in "${valid_dirs[@]}"; do
        local subdirs=""
        if [[ -n "$FD_CMD" ]]; then
            subdirs=$("$FD_CMD" --type d --max-depth 1 --min-depth 1 . "$dir" 2>/dev/null) || true
        else
            subdirs=$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null) || true
        fi

        [[ -z "$subdirs" ]] && continue

        while IFS= read -r line; do
            line="${line%/}"  # strip trailing slash from fd output
            [[ -d "$line" ]] || continue
            [[ -v "seen_paths[$line]" ]] && continue
            seen_paths["$line"]=1

            # Check if session already exists
            local session_name
            session_name=$(basename "$line")
            session_name=$(printf '%s' "$session_name" | sed 's/[^a-zA-Z0-9_-]/-/g')
            session_name="${session_name#-}"
            session_name="${session_name%-}"
            indicator=""
            if tmux has-session -t "=$session_name" 2>/dev/null; then
                indicator=$' \033[32m★\033[0m'
            fi

            # shellcheck disable=SC2088
            short_name="${line/#"$HOME"/"~"}"

            printf '%s\t%s  \033[38;5;244m(directory)\033[0m%s\n' "$line" "$short_name" "$indicator"
        done <<< "$subdirs"
    done
}

# Sanitize basename → check has-session → create with -c or switch.
_create_or_switch_session() {
    local selected="$1"
    local session_name
    session_name=$(basename "$selected")

    # Sanitize: replace any character not in [a-zA-Z0-9_-] with a dash
    session_name=$(printf '%s' "$session_name" | sed 's/[^a-zA-Z0-9_-]/-/g')
    # Trim leading/trailing dashes
    session_name="${session_name#-}"
    session_name="${session_name%-}"

    [[ -z "$session_name" ]] && return

    if tmux has-session -t "=$session_name" 2>/dev/null; then
        tmux switch-client -t "=$session_name"
    else
        tmux new-session -d -s "$session_name" -c "$selected" && \
            tmux switch-client -t "=$session_name"
    fi
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

    if [[ ${#valid_dirs[@]} -eq 0 ]]; then
        _show_empty_state \
            "no session dirs found — set @dispatch-session-dirs '/path/one:/path/two'" \
            "new session " \
            " new session · ⌫ sessions "
    fi

    local targets
    targets=$(_discover_session_targets "${valid_dirs[@]}")

    if [[ -z "$targets" ]]; then
        _show_empty_state \
            "no projects found in session dirs" \
            "new session " \
            " new session · ⌫ sessions "
    fi

    local become_sessions="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=sessions --pane='$SQ_PANE_ID')"

    local selected
    selected=$(printf '%s\n' "$targets" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --ansi \
        --delimiter=$'\t' \
        --with-nth=2.. \
        --border-label=' new session · ? help · enter create · ⌫ sessions ' \
        --border-label-pos 'center:bottom' \
        --preview "'$SQ_SCRIPT_DIR/session-new-preview.sh' {1}" \
        --query "$QUERY" \
        --bind "backward-eof:$become_sessions" \
        --bind "?:preview:printf '%b' '$SQ_HELP_SESSION_NEW'" \
    ) || exit 0

    [[ -z "$selected" ]] && exit 0

    # Extract path (first field before tab)
    local path="${selected%%$'\t'*}"
    _create_or_switch_session "$path"
}

# ─── Mode: rename ─────────────────────────────────────────────────────────

run_rename_mode() {
    [[ -z "$FILE" ]] && { _dispatch_error "no file selected for rename"; exit 1; }
    if [[ ! -f "$FILE" ]]; then
        tmux display-message "File not found: $FILE"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    local result
    result=$(
        echo "$FILE" | fzf \
            "${BASE_FZF_OPTS[@]}" \
            --disabled \
            --print-query \
            --query "$FILE" \
            --prompt 'rename → ' \
            --preview "'$SQ_SCRIPT_DIR/actions.sh' rename-preview $(printf '%q' "$FILE") {q}" \
            --border-label ' rename · enter confirm · esc cancel ' \
            --border-label-pos 'center:bottom' \
    ) || exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"

    local new_name
    new_name=$(head -1 <<< "$result")

    # Empty or unchanged → cancel
    if [[ -z "$new_name" || "$new_name" == "$FILE" ]]; then
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    # Path traversal guard — reject targets outside working directory
    # _resolve_path normalizes . and .. (cross-platform, no GNU realpath -m needed).
    # Resolve both sides so symlinked project dirs don't cause false rejections.
    local resolved resolved_pwd
    resolved=$(_resolve_path "$new_name")
    resolved_pwd=$(_resolve_path "$PWD")
    if [[ "$resolved" != "$resolved_pwd"/* ]]; then
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
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || { _dispatch_error "Cannot create directory: $dir"; exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"; }
    fi
    command mv "$FILE" "$new_name" || { _dispatch_error "Rename failed: $FILE → $new_name"; exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"; }

    exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
}

# ─── Mode: rename-session ────────────────────────────────────────────────────

run_rename_session_mode() {
    [[ -z "$SESSION" ]] && { _dispatch_error "no session selected for rename"; exit 1; }
    if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
        tmux display-message "Session not found: $SESSION"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
    fi

    local result
    result=$(
        echo "$SESSION" | fzf \
            "${BASE_FZF_OPTS[@]}" \
            --disabled \
            --print-query \
            --query "$SESSION" \
            --prompt 'rename-session → ' \
            --preview "'$SQ_SCRIPT_DIR/actions.sh' rename-session-preview '$(_sq_escape "$SESSION")' {q}" \
            --border-label ' rename session · enter confirm · esc cancel ' \
            --border-label-pos 'center:bottom' \
    ) || exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"

    local new_name
    new_name=$(head -1 <<< "$result")

    # Empty or unchanged → cancel
    if [[ -z "$new_name" || "$new_name" == "$SESSION" ]]; then
        exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
    fi

    # Conflict check
    if tmux has-session -t "=$new_name" 2>/dev/null; then
        tmux display-message "Session already exists: $new_name"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
    fi

    tmux rename-session -t "=$SESSION" "$new_name"

    exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
}

# ─── Mode: dirs ───────────────────────────────────────────────────────────────

run_directory_mode() {
    local ZOXIDE_CMD
    ZOXIDE_CMD=$(_dispatch_read_cached "@_dispatch-zoxide" detect_zoxide)

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
    # Uses bash parameter expansion instead of sed (avoids regex escaping issues with $HOME)
    local sq_home
    sq_home=$(_sq_escape "$HOME")
    local tilde_expand="d={}; d=\${d/#\\~/'$sq_home'}"
    local dir_preview
    if command -v tree &>/dev/null; then
        dir_preview="$tilde_expand; tree -C -L 2 \"\$d\""
    elif ls --color=always /dev/null 2>/dev/null; then
        dir_preview="$tilde_expand; ls -la --color=always \"\$d\""
    else
        dir_preview="$tilde_expand; ls -laG \"\$d\""
    fi

    local dir_output
    dir_output=$(_run_dir_cmd)

    if [[ -z "$dir_output" ]]; then
        local dir_msg
        if [[ -z "$ZOXIDE_CMD" ]]; then
            dir_msg="no directories found — install zoxide for frecency: brew install zoxide"
        else
            dir_msg="no directories in zoxide — cd around first to build history"
        fi
        _show_empty_state "$dir_msg" "dirs # " " dirs # · ⌫ files "
    fi

    local become_files="$BECOME_FILES"

    local result
    result=$(echo "$dir_output" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --expect=ctrl-y \
        --query "$QUERY" \
        --prompt 'dirs # ' \
        --header "${PWD/#"$HOME"/~}" \
        --preview "$dir_preview" \
        --border-label ' dirs # · ? help · enter cd · ^y copy · ⌫ files ' \
        --border-label-pos 'center:bottom' \
        --bind "backward-eof:$become_files" \
        --bind "?:preview:printf '%b' '$SQ_HELP_DIRS'" \
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
        _dispatch_error "no session specified for window picker"
        exit 1
    fi

    if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
        tmux display-message "Session not found: $SESSION"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=sessions --pane="$PANE_ID"
    fi

    local win_list
    win_list=$(tmux list-windows -t "=$SESSION" \
        -F '#{window_index}: #{window_name}  #{?window_active,*,}  (#{window_panes} panes)' 2>/dev/null)

    [[ -z "$win_list" ]] && { _dispatch_error "no windows found"; exit 0; }

    local become_sessions="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=sessions --pane='$SQ_PANE_ID')"

    local result
    result=$(
        echo "$win_list" |
        fzf \
            "${BASE_FZF_OPTS[@]}" \
            --no-cycle \
            --expect=ctrl-y \
            --prompt "$SESSION windows  " \
            --border-label ' windows · ? help · ←→ move · ↑↓ skip · enter switch · ^y copy · ⌫ sessions ' \
            --border-label-pos 'center:bottom' \
            --preview "'$SQ_SCRIPT_DIR/session-preview.sh' $(printf '%q' "$SESSION") {1}" \
            --bind "right:down" \
            --bind "left:up" \
            --bind "down:down+down" \
            --bind "up:up+up" \
            --bind "backward-eof:$become_sessions" \
            --bind "?:preview:printf '%b' '$SQ_HELP_WINDOWS'" \
    ) || exit 0

    [[ -z "$result" ]] && exit 0

    local key selected
    key=$(head -1 <<< "$result")
    selected=$(tail -1 <<< "$result")
    [[ -z "$selected" ]] && exit 0

    # Extract window index (first field before colon)
    local win_idx
    win_idx=$(awk -F: '{print $1}' <<< "$selected")
    [[ "$win_idx" =~ ^[0-9]+$ ]] || exit 0

    case "$key" in
        ctrl-y)
            local win_name
            win_name=$(awk -F: '{print $2}' <<< "$selected" | sed 's/^ *//;s/ *$//')
            echo -n "$SESSION:$win_idx" | tmux load-buffer -w -
            tmux display-message "Copied: $SESSION:$win_idx ($win_name)"
            ;;
        *)
            tmux select-window -t "=$SESSION:$win_idx"
            tmux switch-client -t "=$SESSION"
            ;;
    esac
}

# ─── Mode: git ────────────────────────────────────────────────────────────────

run_git_mode() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        _show_empty_state \
            "git mode requires a repository — switch to a project with git init" \
            "git ! " \
            " git ! · ⌫ files "
    fi

    case "${GIT_VIEW:-status}" in
        log)    _run_git_log_view ;;
        branch) _run_git_branch_view ;;
        *)      _run_git_status_view ;;
    esac
}

_run_git_status_view() {
    # Icon support: conditional field references and awk fragments
    local icon_func icon_begin icon_line icon_git_line
    _icon_awk_fragments
    local fzf_git_file fzf_git_files git_nth
    if [[ "$ICONS_ENABLED" == "on" ]]; then
        fzf_git_file="{3..}" fzf_git_files="{+3..}"
        git_nth="3.."
    else
        fzf_git_file="{2..}" fzf_git_files="{+2..}"
        git_nth="2.."
    fi

    # Git status: porcelain v1 → colored icons (ICON<tab>[file-icon<tab>]filepath)
    # Shared awk body used by both the initial load function and fzf reload string.
    local git_awk_prefix=""
    if [[ "$ICONS_ENABLED" == "on" ]]; then
        git_awk_prefix="${icon_func}BEGIN {
    ${icon_begin}
}
"
    fi
    # shellcheck disable=SC2016  # $0 etc. are awk variables, not bash
    local git_awk="${git_awk_prefix}"'{
        xy = substr($0, 1, 2)
        file = substr($0, 4)
        x = substr(xy, 1, 1)
        y = substr(xy, 2, 1)
        if (x == "?" && y == "?")       icon = "\033[33m?\033[0m"
        else if (x != " " && y != " ")  icon = "\033[35m✹\033[0m"
        else if (x != " ")              icon = "\033[32m✚\033[0m"
        else                            icon = "\033[31m●\033[0m"
        '"${icon_git_line}"'
    }'

    _run_git_status() { git status --porcelain 2>/dev/null | awk "$git_awk"; }

    # fzf reload string — single quotes around $git_awk protect awk's $0 from sh
    local git_status_cmd="git status --porcelain 2>/dev/null | awk '${git_awk}'"

    local become_files="$BECOME_FILES"
    local become_log="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=git --git-view=log --pane='$SQ_PANE_ID' --query={q})"
    local become_branch="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=git --git-view=branch --pane='$SQ_PANE_ID' --query={q})"

    local git_output
    git_output=$(_run_git_status)

    if [[ -z "$git_output" ]]; then
        # Custom empty state: keeps Ctrl+L/Ctrl+S so log/branch are reachable
        printf '' | fzf \
            "${BASE_FZF_OPTS[@]}" \
            --header "working tree clean — nothing to stage" \
            --prompt 'git ! ' \
            --border-label ' git ! · ^l log · ^s branch · ⌫ files ' \
            --border-label-pos 'center:bottom' \
            --bind "ctrl-l:$become_log" \
            --bind "ctrl-s:$become_branch" \
            --bind "backward-eof:$become_files" \
            --bind "?:preview:printf '%b' '$SQ_HELP_GIT'"
        exit 0
    fi

    local result
    result=$(echo "$git_output" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --multi \
        --expect=ctrl-o,ctrl-y \
        --query "$QUERY" \
        --prompt 'git ! ' \
        --ansi \
        --delimiter=$'\t' \
        --nth="$git_nth" \
        --tabstop=3 \
        --preview "'$SQ_SCRIPT_DIR/git-preview.sh' $fzf_git_file {1}" \
        --preview-window 'right:60%:border-left' \
        --border-label ' git ! · ? help · tab stage · ^l log · ^s branch · enter open · ⌫ files ' \
        --border-label-pos 'center:bottom' \
        --bind "tab:execute-silent('$SQ_SCRIPT_DIR/actions.sh' git-toggle $fzf_git_file)+reload:$git_status_cmd" \
        --bind "enter:execute('$SQ_SCRIPT_DIR/actions.sh' edit-file '$SQ_POPUP_EDITOR' '$SQ_PWD' '$SQ_HISTORY' $fzf_git_files)" \
        --bind "ctrl-r:become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=rename --pane='$SQ_PANE_ID' --file=$fzf_git_file)" \
        --bind "ctrl-x:execute('$SQ_SCRIPT_DIR/actions.sh' delete-files $fzf_git_file)+reload:$git_status_cmd" \
        --bind "ctrl-l:$become_log" \
        --bind "ctrl-s:$become_branch" \
        --bind "backward-eof:$become_files" \
        --bind "?:preview:printf '%b' '$SQ_HELP_GIT'" \
    ) || exit 0

    _handle_git_status_result "$result"
}

_handle_git_status_result() {
    local result="$1"
    local key
    local -a files

    key=$(head -1 <<< "$result")
    # Extract file paths from tab-delimited lines (icon\t[file-icon\t]file)
    local git_cut_field=2
    [[ "$ICONS_ENABLED" == "on" ]] && git_cut_field=3
    mapfile -t files < <(tail -n +2 <<< "$result" | cut -f"$git_cut_field")
    [[ ${#files[@]} -eq 0 ]] && exit 0

    case "$key" in
        ctrl-y)
            printf '%s\n' "${files[@]}" | tmux load-buffer -w -
            tmux display-message "Copied ${#files[@]} path(s)"
            ;;
        ctrl-o)
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
            # Enter is handled by fzf execute() binding
            ;;
    esac
}

_run_git_log_view() {
    local log_output
    log_output=$(git log --oneline --graph --decorate --color=always --all -100 2>/dev/null)

    if [[ -z "$log_output" ]]; then
        _show_empty_state \
            "no commits yet — make your first commit" \
            "log ! " \
            " log ! · ⌫ status "
    fi

    local become_status="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=git --git-view=status --pane='$SQ_PANE_ID' --query={q})"
    local become_branch="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=git --git-view=branch --pane='$SQ_PANE_ID' --query={q})"

    # Preview: extract hash from selected line, show commit details
    local preview_cmd="hash=\$(echo {} | grep -oE '[0-9a-f]{7,}' | head -1); \
if [ -n \"\$hash\" ]; then \
git show --stat --color=always --format='%C(yellow)%H%C(reset)%n%C(bold)%s%C(reset)%n%C(dim)%an  %ci%C(reset)%n' \"\$hash\" 2>/dev/null | head -80; \
else echo 'no commit hash on this line'; fi"

    local result
    result=$(echo "$log_output" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --multi \
        --expect=ctrl-o,ctrl-y \
        --query "$QUERY" \
        --prompt 'log ! ' \
        --ansi --no-sort \
        --preview "$preview_cmd" \
        --preview-window 'right:60%:border-left' \
        --border-label ' log ! · ? help · enter hash · ^o pick · ^y copy · ^l status · ^s branch · ⌫ status ' \
        --border-label-pos 'center:bottom' \
        --bind "ctrl-l:$become_status" \
        --bind "ctrl-s:$become_branch" \
        --bind "backward-eof:$become_status" \
        --bind "?:preview:printf '%b' '$SQ_HELP_GIT_LOG'" \
    ) || exit 0

    _handle_git_log_result "$result"
}

_handle_git_log_result() {
    local result="$1"
    local key
    key=$(head -1 <<< "$result")

    # Extract hashes from selected lines
    local -a hashes=()
    local line hash
    while IFS= read -r line; do
        hash=$(echo "$line" | grep -oE '[0-9a-f]{7,}' | head -1)
        [[ -n "$hash" ]] && hashes+=("$hash")
    done < <(tail -n +2 <<< "$result")
    [[ ${#hashes[@]} -eq 0 ]] && exit 0

    case "$key" in
        ctrl-y)
            printf '%s\n' "${hashes[@]}" | tmux load-buffer -w -
            tmux display-message "Copied ${#hashes[@]} hash(es)"
            ;;
        ctrl-o)
            local h
            for h in "${hashes[@]}"; do
                if ! git cherry-pick "$h" 2>/dev/null; then
                    tmux display-message "Cherry-pick conflict on $h — resolve manually"
                    return
                fi
            done
            tmux display-message "Cherry-picked ${#hashes[@]} commit(s)"
            ;;
        *)
            # Enter: copy first hash
            printf '%s' "${hashes[0]}" | tmux load-buffer -w -
            tmux display-message "Copied: ${hashes[0]}"
            ;;
    esac
}

_run_git_branch_view() {
    # Local branches sorted by most recently committed, with tracking info and date
    local branch_output
    branch_output=$(git branch --sort=-committerdate \
        --format='%(if)%(HEAD)%(then)%(color:green)* %(else)  %(end)%(color:reset)%(refname:short)%(if)%(upstream:short)%(then) %(color:dim)-> %(upstream:short)%(color:reset)%(end)  %(color:dim)%(committerdate:relative)%(color:reset)' 2>/dev/null)

    if [[ -z "$branch_output" ]]; then
        _show_empty_state \
            "no branches — create your first commit" \
            "branch ! " \
            " branch ! · ⌫ status "
    fi

    local become_status="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=git --git-view=status --pane='$SQ_PANE_ID' --query={q})"
    local become_log="become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=git --git-view=log --pane='$SQ_PANE_ID' --query={q})"

    # Preview: extract branch name, show recent log
    # Strip ANSI, leading "* " or "  ", take first word (branch name)
    local preview_cmd="branch=\$(echo {} | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[* ] *//' | awk '{print \$1}'); \
if [ -n \"\$branch\" ]; then \
printf '\\033[1m%s\\033[0m\\n\\n' \"\$branch\"; \
git log --oneline --graph --decorate --color=always -15 \"\$branch\" 2>/dev/null; \
else echo 'no branch'; fi"

    local result
    result=$(echo "$branch_output" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --expect=ctrl-y \
        --query "$QUERY" \
        --prompt 'branch ! ' \
        --ansi --no-sort \
        --preview "$preview_cmd" \
        --preview-window 'right:60%:border-left' \
        --border-label ' branch ! · ? help · enter switch · ^y copy · ^l log · ^s status · ⌫ status ' \
        --border-label-pos 'center:bottom' \
        --bind "ctrl-l:$become_log" \
        --bind "ctrl-s:$become_status" \
        --bind "backward-eof:$become_status" \
        --bind "?:preview:printf '%b' '$SQ_HELP_GIT_BRANCH'" \
    ) || exit 0

    _handle_git_branch_result "$result"
}

_handle_git_branch_result() {
    local result="$1"
    local key
    key=$(head -1 <<< "$result")

    local selected
    selected=$(tail -n +2 <<< "$result" | head -1)
    [[ -z "$selected" ]] && exit 0

    # Extract branch name: strip ANSI codes, strip leading "* " or "  ", take first word
    local branch
    branch=$(echo "$selected" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[* ] *//' | awk '{print $1}')
    [[ -z "$branch" ]] && exit 0

    case "$key" in
        ctrl-y)
            printf '%s' "$branch" | tmux load-buffer -w -
            tmux display-message "Copied: $branch"
            ;;
        *)
            # Enter: switch branch
            if git switch "$branch" 2>/dev/null; then
                tmux display-message "Switched to: $branch"
            elif git checkout "$branch" 2>/dev/null; then
                tmux display-message "Switched to: $branch"
            else
                tmux display-message "Failed to switch to: $branch"
            fi
            ;;
    esac
}

run_scrollback_mode() {
    if [[ -z "$PANE_ID" ]]; then
        _dispatch_error "scrollback requires a pane — use keybinding, not direct invocation"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    local become_files_empty="$BECOME_FILES"

    # Capture raw scrollback from originating pane
    local raw_file lines_file tokens_file view_flag filter_file
    raw_file=$(mktemp "${TMPDIR:-/tmp}/dispatch-raw-XXXXXX")
    lines_file=$(mktemp "${TMPDIR:-/tmp}/dispatch-lines-XXXXXX")
    tokens_file=$(mktemp "${TMPDIR:-/tmp}/dispatch-tokens-XXXXXX")
    view_flag=$(mktemp "${TMPDIR:-/tmp}/dispatch-view-XXXXXX")
    filter_file=$(mktemp "${TMPDIR:-/tmp}/dispatch-filter-XXXXXX")
    printf 'all' > "$filter_file"
    trap 'command rm -f "$raw_file" "$lines_file" "$tokens_file" "$view_flag" "$filter_file"' EXIT

    tmux capture-pane -t "$PANE_ID" -p -S "-${SCROLLBACK_LINES}" 2>/dev/null > "$raw_file"

    # Build lines file: dedup + reverse (most recent first)
    awk 'NF && !seen[$0]++' "$raw_file" \
        | awk '{lines[NR]=$0} END {for(i=NR;i>=1;i--) print lines[i]}' > "$lines_file"

    if [[ ! -s "$lines_file" ]]; then
        command rm -f "$raw_file" "$lines_file" "$tokens_file" "$view_flag" "$filter_file"
        _show_empty_state \
            "scrollback is empty — pane has no output yet" \
            "scrollback $ " \
            " scrollback $ · ⌫ files "
    fi

    # Build disabled types set (accessed by _extract_tokens via dynamic scoping)
    local -A disabled_types=()
    if [[ -f "${PATTERNS_FILE:-}" ]]; then
        local dtype
        while IFS= read -r dtype; do
            disabled_types["$dtype"]=1
        done < <(_parse_disabled_types "$PATTERNS_FILE")
    fi

    # Build tokens file via _extract_tokens
    _extract_tokens "$raw_file" > "$tokens_file"

    # If tokens view requested but no tokens found, fall back to lines
    if [[ "$SCROLLBACK_VIEW" == "tokens" && ! -s "$tokens_file" ]]; then
        _dispatch_error "no tokens found in scrollback — showing lines"
        SCROLLBACK_VIEW="lines"
    fi

    # View flag file: present = tokens view, absent = lines view
    if [[ "$SCROLLBACK_VIEW" == "tokens" ]]; then
        touch "$view_flag"
    else
        command rm -f "$view_flag"
    fi

    local sq_lines_file sq_tokens_file sq_view_flag sq_raw_file sq_filter_file
    sq_lines_file=$(_sq_escape "$lines_file")
    sq_tokens_file=$(_sq_escape "$tokens_file")
    sq_view_flag=$(_sq_escape "$view_flag")
    sq_raw_file=$(_sq_escape "$raw_file")
    sq_filter_file=$(_sq_escape "$filter_file")

    # Preview command: branches on view flag
    # Lines view: show surrounding context (5 lines) around selected line
    # Tokens view: type-aware preview (git show for hashes, bat for files, grep context for rest)
    local sq_bat=""
    [[ -n "$BAT_CMD" ]] && sq_bat=$(_sq_escape "$BAT_CMD")

    # Use fzf field placeholders {1} and {2} instead of {} + cut.
    # With --delimiter=\t and --ansi, {1} gives ANSI-stripped type, {2} gives token.
    # IMPORTANT: Do NOT wrap {1}/{2} in extra quotes — fzf already single-quotes
    # placeholder values. Adding quotes creates collisions: token='{2}' becomes
    # token=''value'' which breaks on backticks and single quotes in values.
    local preview_cmd="if [ -f '$sq_view_flag' ]; then \
token={2}; \
ttype={1}; \
printf '\\033[1;36m%s\\033[0m  \\033[38;5;244m(%s)\\033[0m\\n\\033[38;5;244m─────────────────────────────────────────\\033[0m\\n' \"\$token\" \"\$ttype\"; \
if [ \"\$ttype\" = hash ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git cat-file -t \"\$token\" >/dev/null 2>&1; then \
git show --stat --format='%h %s%n%an  %ci' \"\$token\" 2>/dev/null | head -40; \
elif [ \"\$ttype\" = diff ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
diff_out=\$(git diff HEAD --color=always -- \"\$token\" 2>/dev/null); \
if [ -z \"\$diff_out\" ]; then diff_out=\$(git log -1 -p --color=always --format='%C(yellow)%h%C(reset) %s%n%C(dim)%an  %ci%C(reset)%n' -- \"\$token\" 2>/dev/null); fi; \
if [ -n \"\$diff_out\" ]; then printf '%s\\n' \"\$diff_out\" | head -80; \
elif [ -f \"\$token\" ]; then ${sq_bat:+"'$sq_bat' --color=always --style=numbers --line-range=:50 \"\$token\" 2>/dev/null ||"} head -50 \"\$token\"; \
else printf 'no changes (clean)\\n'; fi; \
elif [ \"\$ttype\" = path ] || [ \"\$ttype\" = file ]; then \
file=\"\${token%%:*}\"; line=\"\${token#*:}\"; line=\"\${line%%:*}\"; \
case \"\$line\" in *[!0-9]*) line=1;; esac; \
[ -z \"\$line\" ] && line=1; \
if [ -f \"\$file\" ]; then \
${sq_bat:+"'$sq_bat' --color=always --highlight-line \"\$line\" --style=numbers --line-range=:\$((\$line+50)) \"\$file\" 2>/dev/null ||"} head -50 \"\$file\"; \
else \
grep --color=always -F -B2 -A2 -- \"\$token\" '$sq_raw_file' 2>/dev/null | head -30; \
fi; \
else \
grep --color=always -F -B2 -A2 -- \"\$token\" '$sq_raw_file' 2>/dev/null | head -30; \
fi; \
else \
awk -v n=\$(({n}+1)) 'NR>=n-5 && NR<=n+5 { if (NR==n) printf \"\\033[1;33m> %s\\033[0m\\n\", \$0; else print \"  \" \$0 }' '$sq_lines_file'; \
fi"

    # Build HELP_EXTRACT dynamically — include new types, exclude disabled ones
    local -A builtin_colors=(
        [url]="36" [path]="33" [hash]="35" [ip]="32"
        [uuid]="34" [diff]="31" [file]="33"
        [email]="38;5;208" [semver]="38;5;147" [color]="38;5;219"
    )
    local -a builtin_order=(url path hash ip uuid diff file email semver color)
    local type_list="" t
    for t in "${builtin_order[@]}"; do
        [[ -v "disabled_types[$t]" ]] && continue
        [[ -n "$type_list" ]] && type_list+=" "
        type_list+="\033[${builtin_colors[$t]}m${t}\033[0m"
    done
    if [[ -f "${PATTERNS_FILE:-}" ]]; then
        while IFS=$'\t' read -r ptype pcolor _rest; do
            [[ -v "disabled_types[$ptype]" ]] && continue
            type_list+=" \033[${pcolor}m${ptype}\033[0m"
        done < <(_parse_custom_patterns "$PATTERNS_FILE")
    fi
    # Build disabled types line (dim) — only shown when types are disabled
    local disabled_list=""
    for t in "${builtin_order[@]}"; do
        [[ -v "disabled_types[$t]" ]] || continue
        [[ -n "$disabled_list" ]] && disabled_list+=" "
        disabled_list+="$t"
    done
    if [[ -f "${PATTERNS_FILE:-}" ]]; then
        while IFS=$'\t' read -r ptype _rest; do
            [[ -v "disabled_types[$ptype]" ]] || continue
            [[ -n "$disabled_list" ]] && disabled_list+=" "
            disabled_list+="$ptype"
        done < <(_parse_custom_patterns "$PATTERNS_FILE")
    fi
    local disabled_line=""
    [[ -n "$disabled_list" ]] && disabled_line="\n  \033[38;5;244mdisabled: ${disabled_list}\033[0m"
    local HELP_EXTRACT
    HELP_EXTRACT="$(printf '%b' "
  \033[1mEXTRACT (tokens)\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     copy to clipboard
  ^O        smart open
            (editor / browser)
  ^T        switch to lines
  tab       select
  ⌫ empty   back to files

  ${type_list}${disabled_line}
  ^/        filter by type
  ^D/^U     scroll preview
")"
    local SQ_HELP_EXTRACT
    SQ_HELP_EXTRACT=$(_sq_escape "$HELP_EXTRACT")

    # Help binding: branches on view flag
    local help_cmd="if [ -f '$sq_view_flag' ]; then printf '%b' '$SQ_HELP_EXTRACT'; else printf '%b' '$SQ_HELP_SCROLLBACK'; fi"

    # Ctrl+T toggle: flip view flag, reload data, update prompt and border label
    # NOTE: The echo must use a single unbroken single-quoted string. Breaking out
    # of single quotes for variable embedding (e.g., 'text'$var'text') confuses
    # fzf's --bind parser, which interprets single quotes during transform: parsing.
    # Since the outer definition is double-quoted, variables are expanded inline.
    local lines_label_inner=" scrollback \$ · ? help · ^t extract · enter copy · ^o paste · tab select · ⌫ files "
    local tokens_label_inner=" extract \$ · ? help · ^t lines · ^/ filter · enter copy · ^o open · tab select · ⌫ files "
    local lines_label="'$lines_label_inner'"
    local tokens_label="'$tokens_label_inner'"
    local toggle_cmd="if [ -f '$sq_view_flag' ]; then \
command rm -f '$sq_view_flag'; \
printf all > '$sq_filter_file'; \
echo 'reload(cat $sq_lines_file)+change-prompt(scrollback \$ )+change-border-label($lines_label_inner)'; \
else \
touch '$sq_view_flag'; \
printf all > '$sq_filter_file'; \
echo 'reload(cat $sq_tokens_file)+change-prompt(extract \$ )+change-border-label($tokens_label_inner)'; \
fi"

    # Ctrl+/ filter: cycle through token types (only active in tokens view)
    # Uses grep with ESC-byte anchor to match type label in first field reliably.
    # Token lines are \033[XXmTYPE\033[0m\tVALUE — grepping for "mTYPE\033" is unique
    # because token values never contain ESC bytes (ANSI stripped during extraction).
    # Cycle is built dynamically — includes new types, excludes disabled ones.
    local esc=$'\033'
    local -a all_known_types=(url path hash ip uuid diff file email semver color)
    local -a filter_types=()
    for t in "${all_known_types[@]}"; do
        [[ -v "disabled_types[$t]" ]] || filter_types+=("$t")
    done
    if [[ -f "${PATTERNS_FILE:-}" ]]; then
        while IFS=$'\t' read -r ptype _rest; do
            [[ -v "disabled_types[$ptype]" ]] || filter_types+=("$ptype")
        done < <(_parse_custom_patterns "$PATTERNS_FILE")
    fi
    # Build case body: all→first, first→second, ..., last→all
    local cycle_cases="all) next=${filter_types[0]};; "
    local i nxt
    for ((i = 0; i < ${#filter_types[@]}; i++)); do
        if ((i + 1 < ${#filter_types[@]})); then
            nxt="${filter_types[$((i+1))]}"
        else
            nxt="all"
        fi
        cycle_cases+="${filter_types[$i]}) next=${nxt};; "
    done
    cycle_cases+="*) next=all;;"
    local filter_cmd="if [ ! -f '$sq_view_flag' ]; then exit 0; fi; \
cur=\$(cat '$sq_filter_file'); \
case \"\$cur\" in \
${cycle_cases} \
esac; \
printf '%s' \"\$next\" > '$sq_filter_file'; \
if [ \"\$next\" = all ]; then \
echo 'reload(cat $sq_tokens_file)+change-prompt(extract \$ )+change-border-label($tokens_label_inner)'; \
else \
echo \"reload(grep m\$next${esc} $sq_tokens_file; true)+change-prompt(extract \\\$ \$next >)+change-border-label($tokens_label_inner)\"; \
fi"

    # Determine initial state
    local initial_prompt initial_label initial_file
    if [[ "$SCROLLBACK_VIEW" == "tokens" ]]; then
        initial_prompt='extract $ '
        initial_label="$tokens_label"
        initial_file="$tokens_file"
    else
        initial_prompt='scrollback $ '
        initial_label="$lines_label"
        initial_file="$lines_file"
    fi

    local result
    result=$(fzf < "$initial_file" \
        "${BASE_FZF_OPTS[@]}" \
        --expect=ctrl-o \
        --multi \
        --query "$QUERY" \
        --prompt "$initial_prompt" \
        --ansi \
        --no-sort \
        --delimiter=$'\t' \
        --border-label "$initial_label" \
        --border-label-pos 'center:bottom' \
        --preview "$preview_cmd" \
        --bind "ctrl-t:transform:$toggle_cmd" \
        --bind "ctrl-/:transform:$filter_cmd" \
        --bind "backward-eof:$become_files_empty" \
        --bind "?:preview:$help_cmd" \
    ) || exit 0

    handle_scrollback_result "$result" "$view_flag"
}

handle_scrollback_result() {
    local result="$1"
    local view_flag="$2"
    local key
    local -a items

    key=$(head -1 <<< "$result")
    mapfile -t items < <(tail -n +2 <<< "$result")
    [[ ${#items[@]} -eq 0 ]] && exit 0

    if [[ -f "$view_flag" ]]; then
        # ─── Tokens view ──────────────────────────────────────────────────
        case "$key" in
            ctrl-o)
                # Smart open each selected token
                local item
                for item in "${items[@]}"; do
                    local ttype="${item%%	*}"
                    # Strip ANSI color codes from type field
                    ttype=$(printf '%s' "$ttype" | sed 's/\x1b\[[0-9;]*m//g')
                    local token="${item#*	}"
                    "$SCRIPT_DIR/actions.sh" smart-open "$ttype" "$token" "$PANE_ID" "$PANE_EDITOR" "$PATTERNS_FILE"
                done
                ;;
            *)
                # Copy token values (strip type prefix) to clipboard
                local tokens=""
                local item
                for item in "${items[@]}"; do
                    local token="${item#*	}"
                    tokens="${tokens:+${tokens}
}${token}"
                done
                printf '%s' "$tokens" | tmux load-buffer -w -
                tmux display-message "Copied ${#items[@]} token(s)"
                ;;
        esac
    else
        # ─── Lines view ───────────────────────────────────────────────────
        case "$key" in
            ctrl-o)
                # Paste to originating pane
                if [[ -n "$PANE_ID" ]]; then
                    local text
                    text=$(printf '%s\n' "${items[@]}")
                    tmux send-keys -t "$PANE_ID" -- "$text"
                    tmux display-message "Sent ${#items[@]} line(s) to pane"
                fi
                ;;
            *)
                # Default: copy to clipboard
                printf '%s\n' "${items[@]}" | tmux load-buffer -w -
                tmux display-message "Copied ${#items[@]} line(s)"
                ;;
        esac
    fi
}

# Create default commands.conf with starter recipes
_create_default_commands() {
    local conf="$1"
    mkdir -p "$(dirname "$conf")"
    cat > "$conf" << 'CONF'
# tmux-dispatch commands — edit with ^E or directly
# Format: Description | command
# Prefix shell commands with nothing, tmux commands with "tmux: "
# Lines starting with # are comments

# Tmux
Reload tmux config | tmux: source-file ~/.tmux.conf; display-message "Config reloaded"
Toggle mouse mode | tmux: if -F "#{mouse}" "set mouse off; display \"Mouse: OFF\"" "set mouse on; display \"Mouse: ON\""
Toggle status bar | tmux: if -F "#{status}" "set status off" "set status on"

# Clipboard
Copy pane contents | tmux: capture-pane -J -p | tmux load-buffer -w -; display-message "Pane copied"
Copy current path | tmux: run-shell "tmux display -p '#{pane_current_path}' | tmux load-buffer -w -"; display-message "Path copied"

# Layout
Split right | tmux: split-window -h -c "#{pane_current_path}"
Split down | tmux: split-window -v -c "#{pane_current_path}"
Even horizontal layout | tmux: select-layout even-horizontal
Even vertical layout | tmux: select-layout even-vertical
CONF
}

run_commands_mode() {
    local become_files_empty="$BECOME_FILES"
    local conf="$COMMANDS_FILE"

    local sq_conf
    sq_conf=$(_sq_escape "$conf")

    # If config doesn't exist, create with defaults
    if [[ ! -f "$conf" ]]; then
        _create_default_commands "$conf"
    fi

    # Parse config: extract non-comment, non-empty lines
    local entries
    entries=$(grep -v '^#' "$conf" | grep -v '^[[:space:]]*$') || true

    if [[ -z "$entries" ]]; then
        _show_empty_state \
            "commands.conf is empty — press : then ^E to add commands" \
            "commands : " \
            " commands : · ⌫ files "
    fi

    # Preview: show the command part (fields after first |)
    # Use {2..} (everything right of delimiter) to avoid grep + quoting issues
    local preview_cmd="echo {2..} | sed 's/^ //'"
    if [[ -n "$BAT_CMD" ]]; then
        local sq_bat
        sq_bat=$(_sq_escape "$BAT_CMD")
        preview_cmd="echo {2..} | sed 's/^ //' | '$sq_bat' --color=always -l sh --style=plain"
    fi

    local result
    result=$(echo "$entries" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --delimiter '\|' \
        --with-nth 1 \
        --query "$QUERY" \
        --prompt 'commands : ' \
        --no-sort \
        --border-label ' commands : · ? help · enter run · ^e edit · ⌫ files ' \
        --border-label-pos 'center:bottom' \
        --preview "$preview_cmd" \
        --bind "ctrl-e:execute('$SQ_POPUP_EDITOR' '$sq_conf')+abort" \
        --bind "backward-eof:$become_files_empty" \
        --bind "?:preview:printf '%b' '$SQ_HELP_COMMANDS'" \
    ) || exit 0

    [[ -z "$result" ]] && exit 0

    # Extract command: everything after first |, trimmed
    local selected_cmd="${result#*|}"
    selected_cmd="${selected_cmd# }"
    [[ -z "$selected_cmd" ]] && exit 0

    # Execute: tmux command (via bash -c for proper quote parsing) or shell command (send to pane)
    if [[ "$selected_cmd" == "tmux: "* ]]; then
        bash -c "tmux ${selected_cmd#tmux: }"
    elif [[ -n "$PANE_ID" ]]; then
        tmux send-keys -t "$PANE_ID" -- "$selected_cmd" Enter
    else
        bash -c "$selected_cmd"
    fi
}

# ─── Mode: marks (global bookmarks) ──────────────────────────────────────

run_marks_mode() {
    local become_files_empty="$BECOME_FILES"

    # Get all bookmarks as absolute tilde-collapsed paths
    local marks
    marks=$(all_bookmarks)

    if [[ -z "$marks" ]]; then
        _show_empty_state \
            "no bookmarks yet — press ^B in files mode to bookmark" \
            "marks ★ " \
            " marks · ⌫ files "
    fi

    # Preview: expand tilde for bat/head, use absolute path
    local preview_cmd
    if [[ -n "$BAT_CMD" ]]; then
        local sq_bat
        sq_bat=$(_sq_escape "$BAT_CMD")
        preview_cmd="f='{}'; f=\"\${f/#\\~/\$HOME}\"; '$sq_bat' --color=always --style=numbers --line-range=:500 \"\$f\""
    else
        preview_cmd="f='{}'; f=\"\${f/#\\~/\$HOME}\"; head -500 \"\$f\""
    fi

    # Reload command for after unbookmark
    local reload_cmd="bash -c 'source \"$SQ_SCRIPT_DIR/helpers.sh\"; all_bookmarks'"

    local result
    result=$(echo "$marks" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --expect=ctrl-o,ctrl-y \
        --query "$QUERY" \
        --prompt 'marks ★ ' \
        --ansi \
        --border-label ' marks · ? help · enter open · ^o pane · ^y copy · ^b unbookmark · ⌫ files ' \
        --border-label-pos 'center:bottom' \
        --preview "$preview_cmd" \
        --bind "ctrl-b:execute-silent('$SQ_SCRIPT_DIR/actions.sh' bookmark-remove '{}')+reload:$reload_cmd" \
        --bind "backward-eof:$become_files_empty" \
        --bind "?:preview:printf '%b' '$SQ_HELP_MARKS'" \
    ) || exit 0

    [[ -z "$result" ]] && exit 0

    local key selected
    key=$(head -1 <<< "$result")
    selected=$(tail -n +2 <<< "$result" | head -1)
    [[ -z "$selected" ]] && exit 0

    # Expand tilde for operations
    selected="${selected/#\~/$HOME}"

    case "$key" in
        ctrl-o)
            if [[ -n "$PANE_ID" ]]; then
                local qfile
                qfile=$(printf '%q' "$selected")
                tmux send-keys -t "$PANE_ID" "$PANE_EDITOR $qfile" Enter
                tmux display-message "Sent to pane: ${selected/#$HOME/\~}"
            fi
            ;;
        ctrl-y)
            printf '%s' "$selected" | tmux load-buffer -w -
            tmux display-message "Copied: ${selected/#$HOME/\~}"
            ;;
        *)
            # Open in editor — cd to file's directory first
            local dir
            dir=$(dirname "$selected")
            if [[ "$HISTORY_ENABLED" == "on" ]]; then
                local relfile
                relfile=$(basename "$selected")
                record_file_open "$dir" "$relfile"
            fi
            (cd "$dir" && "$POPUP_EDITOR" "$(basename "$selected")")
            ;;
    esac
}

# ─── Mode: pathfind (absolute path browsing) ─────────────────────────────────

# Produces file listings for pathfind mode's change:reload binding.
# Also invoked as _path-reload mode from fzf's reload command.
# Takes path from QUERY, walks up with dirname to find deepest valid dir,
# uses remaining text as filter pattern for fd/find.
_path_reload_output() {
    local query="$QUERY"
    [[ -z "$query" ]] && return

    # Walk up to find deepest valid directory
    local search_dir="$query"
    local filter=""
    while [[ ! -d "$search_dir" ]] && [[ "$search_dir" != "/" ]]; do
        filter="$(basename "$search_dir")${filter:+/$filter}"
        search_dir="$(dirname "$search_dir")"
    done
    [[ ! -d "$search_dir" ]] && return

    # Only keep the first segment as the filter pattern (for fd regex matching)
    # e.g., /etc/ngx → dir=/etc, filter=ngx
    # e.g., /etc/nginx/ → dir=/etc/nginx, filter=""
    local fd_filter=""
    if [[ -n "$filter" ]]; then
        # Use only the first path component as fd filter
        fd_filter="${filter%%/*}"
    fi

    # Depth limit: restrict when browsing root or no filter (avoid scanning entire FS)
    local use_depth_limit=false
    if [[ "$search_dir" == "/" ]] || [[ -z "$fd_filter" ]]; then
        use_depth_limit=true
    fi

    if [[ -n "$FD_CMD" ]]; then
        local -a fd_args=(--type f --follow)
        [[ "$use_depth_limit" == true ]] && fd_args+=(--max-depth 3)
        if [[ -n "$fd_filter" ]]; then
            "$FD_CMD" "${fd_args[@]}" -- "$fd_filter" "$search_dir" 2>/dev/null | head -500
        else
            "$FD_CMD" "${fd_args[@]}" . "$search_dir" 2>/dev/null | head -500
        fi
    else
        local -a find_args=("$search_dir")
        [[ "$use_depth_limit" == true ]] && find_args+=(-maxdepth 3)
        if [[ -n "$fd_filter" ]]; then
            find "${find_args[@]}" -type f -name "*${fd_filter}*" 2>/dev/null | head -500
        else
            find "${find_args[@]}" -type f 2>/dev/null | head -500
        fi
    fi
}

run_pathfind_mode() {
    local become_files_empty="$BECOME_FILES"

    # Preview command: bat or head fallback
    local preview_cmd
    if [[ -n "$BAT_CMD" ]]; then
        local sq_bat
        sq_bat=$(_sq_escape "$BAT_CMD")
        preview_cmd="'$sq_bat' --color=always --style=numbers --line-range=:500 {}"
    else
        preview_cmd="head -500 {}"
    fi

    # Reload command: re-invoke dispatch.sh in _path-reload mode
    local path_reload="'$SQ_SCRIPT_DIR/dispatch.sh' --mode=_path-reload --query={q} || true"

    local result
    result=$(_path_reload_output | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --expect=ctrl-o,ctrl-y \
        --disabled \
        --query "$QUERY" \
        --prompt '/ ' \
        --ansi \
        --bind "change:reload:$path_reload" \
        --preview "$preview_cmd" \
        --preview-label=" preview " \
        --border-label ' path · ? help · enter open · ^o pane · ^y copy · ⌫ files ' \
        --border-label-pos 'center:bottom' \
        --bind "backward-eof:$become_files_empty" \
        --bind "enter:execute('$SQ_SCRIPT_DIR/actions.sh' edit-file '$SQ_POPUP_EDITOR' '' '$SQ_HISTORY' {})" \
        --bind "?:preview:printf '%b' '$SQ_HELP_PATH'" \
    ) || exit 0

    handle_pathfind_result "$result"
}

handle_pathfind_result() {
    local result="$1"
    local key selected

    key=$(head -1 <<< "$result")
    selected=$(tail -1 <<< "$result")
    [[ -z "$selected" ]] && exit 0

    case "$key" in
        ctrl-y)
            printf '%s' "$selected" | tmux load-buffer -w -
            tmux display-message "Copied: $selected"
            ;;
        ctrl-o)
            if [[ -n "$PANE_ID" ]]; then
                local qfile
                qfile=$(printf '%q' "$selected")
                tmux send-keys -t "$PANE_ID" "$PANE_EDITOR $qfile" Enter
                tmux display-message "Sent to pane: $selected"
            else
                tmux display-message "No target pane — use Ctrl+Y to copy instead"
            fi
            ;;
        *)
            # Enter is handled by fzf execute() binding
            ;;
    esac
}

# ─── Token extraction ──────────────────────────────────────────────────────
# Extracts structured tokens (URLs, file:line, git hashes, IPs) from scrollback.
# Input: path to raw scrollback file. Output: type\ttoken lines, deduped.

_extract_tokens() {
    local file="$1"
    # disabled_types may be set by caller (run_scrollback_mode) via dynamic scoping.
    # If not set, default to empty — all types enabled.
    if ! declare -p disabled_types &>/dev/null; then
        local -A disabled_types=()
    fi
    local reversed
    reversed=$(mktemp "${TMPDIR:-/tmp}/dispatch-reversed-XXXXXX")
    # Strip ANSI escapes, then reverse (most recent first)
    sed 's/\x1b\[[0-9;]*m//g' "$file" \
        | awk '{lines[NR]=$0} END {for(i=NR;i>=1;i--) print lines[i]}' > "$reversed"
    {
        # URLs — balanced-paren logic for Wikipedia-style URLs like Bash_(Unix_shell)
        [[ -v "disabled_types[url]" ]] || \
        grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+' "$reversed" \
            | while IFS= read -r url; do
                # Balance parentheses: strip trailing ) only if unmatched
                opens="${url//[^(]/}"; closes="${url//[^)]/}"
                while [[ ${#closes} -gt ${#opens} && "$url" == *')' ]]; do
                    url="${url%)}"; closes="${closes%)}"
                done
                # Strip remaining trailing punctuation
                while [[ "$url" =~ [.,\;:!\?\"\'~\`]$ ]]; do
                    url="${url%?}"
                done
                printf '%s\n' "$url"
            done \
            | awk '{print "\033[36murl\033[0m\t" $0}' || true
        # File paths with line numbers — validate file exists on disk
        [[ -v "disabled_types[path]" ]] || \
        grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]{1,10}:[0-9]+(:[0-9]+)?' "$reversed" \
            | grep -v '^//' \
            | while IFS= read -r match; do
                [[ -f "${match%%:*}" ]] && printf '\033[33mpath\033[0m\t%s\n' "$match"
            done || true
        # Bare file paths — only if file actually exists (eliminates false positives)
        [[ -v "disabled_types[file]" ]] || \
        grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]{1,10}' "$reversed" \
            | grep -v '^//' | awk '!seen[$0]++' \
            | while IFS= read -r match; do
                [[ -f "$match" ]] && printf '\033[33mfile\033[0m\t%s\n' "$match"
            done || true
        # Git commit hashes (7-40 hex chars, word-bounded, exclude all-digit)
        [[ -v "disabled_types[hash]" ]] || \
        grep -oEw '[0-9a-f]{7,40}' "$reversed" \
            | grep -v '^[0-9]*$' \
            | awk '{print "\033[35mhash\033[0m\t" $0}' || true
        # IPv4 addresses with optional port
        [[ -v "disabled_types[ip]" ]] || \
        grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]{1,5})?' "$reversed" \
            | awk '{print "\033[32mip\033[0m\t" $0}' || true
        # UUIDs (8-4-4-4-12 hex format — common in AWS, Docker, K8s, DB keys)
        [[ -v "disabled_types[uuid]" ]] || \
        grep -oEi '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$reversed" \
            | awk '{print "\033[34muuid\033[0m\t" $0}' || true
        # Diff paths (--- a/file and +++ b/file from git diff output)
        # Strip prefix, remove quotes/backticks, validate file exists on disk
        [[ -v "disabled_types[diff]" ]] || \
        grep -oE '[-+]{3} [ab]/[^ ]+' "$reversed" \
            | sed 's/^[-+]* [ab]\///' \
            | tr -d "\"'\`" \
            | awk '!seen[$0]++' \
            | while IFS= read -r match; do
                [[ -f "$match" ]] && printf '\033[31mdiff\033[0m\t%s\n' "$match"
            done || true
        # Email addresses
        [[ -v "disabled_types[email]" ]] || \
        grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$reversed" \
            | awk '{print "\033[38;5;208memail\033[0m\t" $0}' || true
        # Semantic versions (v1.2.3, 1.2.3-beta.1)
        [[ -v "disabled_types[semver]" ]] || \
        grep -oEw 'v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?' "$reversed" \
            | awk '{print "\033[38;5;147msemver\033[0m\t" $0}' || true
        # Hex color codes (#aabbcc, #aabbccdd)
        [[ -v "disabled_types[color]" ]] || \
        grep -oE '#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?' "$reversed" \
            | awk '{print "\033[38;5;219mcolor\033[0m\t" $0}' || true
        # Custom patterns from patterns.conf
        if [[ -f "${PATTERNS_FILE:-}" ]]; then
            while IFS=$'\t' read -r ptype pcolor pregex _paction; do
                [[ -v "disabled_types[$ptype]" ]] && continue
                grep -oE -- "$pregex" "$reversed" \
                    | awk -v t="$ptype" -v c="$pcolor" \
                        '{print "\033[" c "m" t "\033[0m\t" $0}' || true
            done < <(_parse_custom_patterns "$PATTERNS_FILE")
        fi
    } | awk '!seen[$0]++'
    command rm -f "$reversed"
}

# Strip mode prefix character from query (used when switching via prefix typing)
_strip_mode_prefix() {
    case "$MODE" in
        grep)       QUERY="${QUERY#>}" ;;
        sessions)   QUERY="${QUERY#@}" ;;
        dirs)       QUERY="${QUERY#\#}" ;;
        git)        QUERY="${QUERY#!}" ;;
        scrollback) QUERY="${QUERY#\$}"; QUERY="${QUERY#&}" ;;
        commands)   QUERY="${QUERY#:}" ;;
    esac
}
_strip_mode_prefix

# ─── Save state for resume ────────────────────────────────────────────────
tmux set -s @_dispatch-last-mode "$MODE" 2>/dev/null || true
tmux set -s @_dispatch-last-query "$QUERY" 2>/dev/null || true

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
    scrollback)     run_scrollback_mode ;;
    commands)       run_commands_mode ;;
    marks)          run_marks_mode ;;
    pathfind)       run_pathfind_mode ;;
    _path-reload)   _path_reload_output; exit 0 ;;
esac
