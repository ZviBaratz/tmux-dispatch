# v1.0.0 "Complete the Palette" Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add scrollback search mode (`$`), custom commands mode (`:`), startup performance caching, and launch polish to complete the command-palette metaphor before v1.0.0 release.

**Architecture:** Two new modes follow the existing `run_*_mode()` pattern in dispatch.sh with fzf `become()` for mode switching. Performance caching moves tool detection to dispatch.tmux (plugin load time) and stores results in tmux server variables. Both new modes integrate with the prefix-based change:transform in files mode.

**Tech Stack:** Bash 4.0+, fzf 0.38+, tmux 2.6+, bats-core for tests

---

## Task 1: Performance — Cache Tool Detection at Plugin Load

**Files:**
- Modify: `dispatch.tmux` (after line 16, add caching block)
- Modify: `scripts/dispatch.sh:85-100` (replace option reads + tool detection)
- Modify: `scripts/helpers.sh` (add `_dispatch_read_cached` helper)
- Test: `tests/dispatch.bats` (add cache-read tests)

### Step 1: Write the failing test

Add to `tests/dispatch.bats`:

```bash
# ─── Cached tool detection ────────────────────────────────────────────────

@test "cached tool: reads fd from tmux server var" {
    run bash -c '
        tmux() {
            if [[ "$1" == "show" && "$2" == "-sv" && "$3" == "@_dispatch-fd" ]]; then
                echo "fdfind"
            else
                echo ""
            fi
        }
        export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        result=$(_dispatch_read_cached "@_dispatch-fd" detect_fd)
        echo "$result"
    '
    [ "$output" = "fdfind" ]
}

@test "cached tool: falls back to detection when cache empty" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        detect_fd() { echo "fd"; }
        export -f detect_fd
        source "'"$SCRIPT_DIR"'/helpers.sh"
        result=$(_dispatch_read_cached "@_dispatch-fd" detect_fd)
        echo "$result"
    '
    [ "$output" = "fd" ]
}
```

### Step 2: Run test to verify it fails

Run: `bats tests/dispatch.bats --filter "cached tool"`
Expected: FAIL — `_dispatch_read_cached` not defined

### Step 3: Implement `_dispatch_read_cached` in helpers.sh

Add to `scripts/helpers.sh` after the `_dispatch_error` function (line 248):

```bash
# Read a cached value from a tmux server variable, with fallback to live detection.
# Used by dispatch.sh to avoid re-detecting tools on every popup open.
# Usage: _dispatch_read_cached "@_dispatch-fd" detect_fd
_dispatch_read_cached() {
    local var="$1" fallback_fn="$2"
    local val
    val=$(tmux show -sv "$var" 2>/dev/null) || val=""
    if [[ -n "$val" ]]; then
        echo "$val"
    else
        "$fallback_fn"
    fi
}
```

### Step 4: Run test to verify it passes

Run: `bats tests/dispatch.bats --filter "cached tool"`
Expected: PASS

### Step 5: Add caching block to dispatch.tmux

Add after `source "$CURRENT_DIR/scripts/helpers.sh"` (line 16) and before `DISPATCH=...` (line 18):

```bash
# ─── Cache tool paths in server variables ───────────────────────────────────
# Runs once at plugin load. dispatch.sh reads these instead of re-detecting
# on every popup open. Server variables persist for the tmux server lifetime.
# Underscore prefix (@_dispatch-*) distinguishes from user-facing options.
tmux set -s @_dispatch-fd "$(detect_fd)"
tmux set -s @_dispatch-bat "$(detect_bat)"
tmux set -s @_dispatch-rg "$(detect_rg)"
tmux set -s @_dispatch-zoxide "$(detect_zoxide)"
tmux set -s @_dispatch-fzf-version "$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
```

### Step 6: Batch tmux option reads in dispatch.sh

Replace lines 85-100 in `scripts/dispatch.sh` (the "Read tmux options" and "Detect tools" sections) with:

```bash
# ─── Read tmux options (batched) ─────────────────────────────────────────────
# One tmux subprocess instead of six separate show-option calls.
POPUP_EDITOR="" PANE_EDITOR="" FD_EXTRA_ARGS="" RG_EXTRA_ARGS=""
HISTORY_ENABLED="on" FILE_TYPES="" GIT_INDICATORS="on" DISPATCH_THEME="default"
while IFS= read -r line; do
    # tmux show-options -g outputs: @key "value" or @key value
    key="${line%% *}"
    val="${line#* }"
    val="${val#\"}" ; val="${val%\"}"  # strip optional quotes
    case "$key" in
        @dispatch-popup-editor)  POPUP_EDITOR="$val" ;;
        @dispatch-pane-editor)   PANE_EDITOR="$val" ;;
        @dispatch-fd-args)       FD_EXTRA_ARGS="$val" ;;
        @dispatch-rg-args)       RG_EXTRA_ARGS="$val" ;;
        @dispatch-history)       HISTORY_ENABLED="$val" ;;
        @dispatch-file-types)    FILE_TYPES="$val" ;;
        @dispatch-git-indicators) GIT_INDICATORS="$val" ;;
        @dispatch-theme)         DISPATCH_THEME="$val" ;;
        @dispatch-scrollback-lines) SCROLLBACK_LINES="$val" ;;
        @dispatch-commands-file) COMMANDS_FILE="$val" ;;
    esac
done < <(tmux show-options -g 2>/dev/null | grep '^@dispatch-')
POPUP_EDITOR=$(detect_popup_editor "$POPUP_EDITOR")
PANE_EDITOR=$(detect_pane_editor "$PANE_EDITOR")
SCROLLBACK_LINES="${SCROLLBACK_LINES:-10000}"
COMMANDS_FILE="${COMMANDS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux-dispatch/commands.conf}"

# ─── Read cached tool paths ──────────────────────────────────────────────────
FD_CMD=$(_dispatch_read_cached "@_dispatch-fd" detect_fd)
BAT_CMD=$(_dispatch_read_cached "@_dispatch-bat" detect_bat)
RG_CMD=$(_dispatch_read_cached "@_dispatch-rg" detect_rg)
```

### Step 7: Replace fzf version check with cached read

Replace the fzf version check block (lines 123-133 in dispatch.sh) with:

```bash
fzf_version=$(_dispatch_read_cached "@_dispatch-fzf-version" "fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1")
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
```

Note: `_dispatch_read_cached` second argument here is a command string, not a function name. Adjust the helper to handle both, or inline the fallback. Simplest: just read directly:

```bash
fzf_version=$(tmux show -sv @_dispatch-fzf-version 2>/dev/null) || fzf_version=""
if [[ -z "$fzf_version" ]]; then
    fzf_version=$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
fi
```

### Step 8: Run full test suite

Run: `bats tests/`
Expected: All tests pass (existing + new cache tests)

### Step 9: Run linting

Run: `shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh`
Expected: No new warnings

### Step 10: Commit

```bash
git add dispatch.tmux scripts/helpers.sh scripts/dispatch.sh tests/dispatch.bats
git commit -m "perf: cache tool detection and batch option reads at plugin load

Move tool detection to dispatch.tmux (runs once). Store results in
tmux server variables (@_dispatch-*). Batch tmux option reads into
a single show-options call. Reduces popup open overhead by ~40-50ms."
```

---

## Task 2: Scrollback Search Mode — Skeleton and Mode Switching

**Files:**
- Modify: `scripts/dispatch.sh:77-83` (add `scrollback` to mode validation)
- Modify: `scripts/dispatch.sh:429-441` (add `$` prefix to change_transform)
- Modify: `scripts/dispatch.sh:1138-1146` (_strip_mode_prefix — add `scrollback`)
- Modify: `scripts/dispatch.sh:1151-1161` (add `scrollback` to dispatch case)
- Modify: `scripts/dispatch.sh:143-162` (update welcome guide with `$` prefix)
- Test: `tests/dispatch.bats`

### Step 1: Write the failing test

Add to `tests/dispatch.bats`:

```bash
# ─── Scrollback mode ─────────────────────────────────────────────────────

@test "scrollback mode strips leading $ from query" {
    run bash -c '
        QUERY="\$ls -la output"
        QUERY="${QUERY#\$}"
        echo "$QUERY"
    '
    [ "$output" = "ls -la output" ]
}

@test "dispatch: scrollback is a valid mode" {
    run bash -c '
        MODE="scrollback"
        case "$MODE" in
            files|grep|git|dirs|sessions|session-new|windows|rename|rename-session|scrollback|commands) echo "valid" ;;
            *) echo "invalid" ;;
        esac
    '
    [ "$output" = "valid" ]
}
```

### Step 2: Run test to verify it fails

Run: `bats tests/dispatch.bats --filter "scrollback"`
Expected: First test PASS (pure bash), second test PASS (pure bash). These validate our logic before integrating.

### Step 3: Add scrollback to mode validation in dispatch.sh

In `scripts/dispatch.sh`, update the mode validation case (line 77-83):

```bash
case "$MODE" in
    files|grep|git|dirs|sessions|session-new|windows|rename|rename-session|scrollback|commands) ;;
    *)
```

### Step 4: Add `$` prefix to change_transform

In the `change_transform` variable (after the `#` dirs check, around line 436), add:

```bash
elif [[ {q} == '\$'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=scrollback --pane='$SQ_PANE_ID' --query={q})\"
```

Note: `$` needs escaping as `\$` inside the double-quoted string since it's embedded in an fzf transform.

### Step 5: Add scrollback to _strip_mode_prefix

In `_strip_mode_prefix()` (line 1139-1146), add:

```bash
        scrollback) QUERY="${QUERY#\$}" ;;
```

### Step 6: Add scrollback to dispatch case

In the dispatch case (line 1151-1161), add:

```bash
    scrollback)     run_scrollback_mode ;;
```

### Step 7: Update welcome guide

In the welcome guide string (line 402), add `$` to the mode switching section:

```
  \\033[38;5;103m\$\\033[0m  scrollback search
```

Add between the `#  directories` and closing `')"` lines.

### Step 8: Add help string for scrollback

Add after `HELP_SESSION_NEW` (around line 236):

```bash
HELP_SCROLLBACK="$(printf '%b' '
  \033[1mSCROLLBACK\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     copy to clipboard
  ^O        paste to pane
  ^X        delete from history
  S-tab     multi-select
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"
```

And add the sq-escaped version:

```bash
SQ_HELP_SCROLLBACK=$(_sq_escape "$HELP_SCROLLBACK")
```

### Step 9: Add stub run_scrollback_mode

Add before the `_strip_mode_prefix` function:

```bash
run_scrollback_mode() {
    _dispatch_error "scrollback mode: not yet implemented"
    exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
}
```

### Step 10: Run tests + lint

Run: `bats tests/ && shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh`
Expected: All pass

### Step 11: Commit

```bash
git add scripts/dispatch.sh tests/dispatch.bats
git commit -m "feat(dispatch): add scrollback mode skeleton with $ prefix switching

Registers scrollback as a valid mode, adds $ prefix detection to
files mode change:transform, adds help string and welcome guide entry.
Mode is a stub that falls back to files — implementation follows."
```

---

## Task 3: Scrollback Search Mode — Full Implementation

**Files:**
- Modify: `scripts/dispatch.sh` (replace stub `run_scrollback_mode`)
- Modify: `scripts/actions.sh` (add `delete-history` action)
- Test: `tests/dispatch.bats` (scrollback dedup tests)
- Test: `tests/actions.bats` (history deletion tests)

### Step 1: Write failing tests for dedup logic

Add to `tests/dispatch.bats`:

```bash
@test "scrollback dedup: removes duplicate lines preserving order" {
    run bash -c '
        input="line1
line2
line1
line3
line2
line3"
        echo "$input" | awk "!seen[\$0]++"
    '
    expected="line1
line2
line3"
    [ "$output" = "$expected" ]
}

@test "scrollback dedup: handles empty input" {
    run bash -c 'echo "" | awk "!seen[\$0]++"'
    [ "$status" -eq 0 ]
}
```

### Step 2: Run tests to verify they pass (these test awk, which works)

Run: `bats tests/dispatch.bats --filter "scrollback dedup"`
Expected: PASS — these validate the dedup primitive

### Step 3: Write failing test for history deletion action

Add to `tests/actions.bats`:

```bash
# ─── delete-history ──────────────────────────────────────────────────────

@test "delete-history: removes matching line from history file" {
    local histfile="$BATS_TEST_TMPDIR/test_history"
    printf 'ls -la\ncd /tmp\ngit status\nls -la\n' > "$histfile"
    HISTFILE="$histfile" run bash -c '
        source "'"$SCRIPT_DIR"'/actions.sh" delete-history "cd /tmp"
    '
    [ "$status" -eq 0 ]
    run cat "$histfile"
    [[ "$output" != *"cd /tmp"* ]]
    [[ "$output" == *"ls -la"* ]]
    [[ "$output" == *"git status"* ]]
}

@test "delete-history: no-op when line not in history" {
    local histfile="$BATS_TEST_TMPDIR/test_history"
    printf 'ls -la\ngit status\n' > "$histfile"
    HISTFILE="$histfile" run bash -c '
        source "'"$SCRIPT_DIR"'/actions.sh" delete-history "not here"
    '
    [ "$status" -eq 0 ]
    run wc -l < "$histfile"
    [ "$output" -eq 2 ]
}

@test "delete-history: handles empty HISTFILE gracefully" {
    HISTFILE="" run bash -c '
        source "'"$SCRIPT_DIR"'/actions.sh" delete-history "anything"
    '
    [ "$status" -eq 0 ]
}
```

### Step 4: Run tests to verify they fail

Run: `bats tests/actions.bats --filter "delete-history"`
Expected: FAIL — `delete-history` action not defined

### Step 5: Implement delete-history action in actions.sh

Add to `scripts/actions.sh` before the dispatch `case` at the bottom:

```bash
# ─── delete-history ──────────────────────────────────────────────────────────

action_delete_history() {
    local line="$1"
    local histfile="${HISTFILE:-}"
    [[ -z "$histfile" || ! -f "$histfile" ]] && return 0
    local tmp
    tmp=$(mktemp "${histfile}.XXXXXX") || return 0
    grep -vFx "$line" "$histfile" > "$tmp" && \mv "$tmp" "$histfile" || \rm -f "$tmp"
}
```

Add to the dispatch case in actions.sh:

```bash
    delete-history)
        shift; action_delete_history "$@" ;;
```

### Step 6: Run tests to verify they pass

Run: `bats tests/actions.bats --filter "delete-history"`
Expected: PASS

### Step 7: Implement run_scrollback_mode in dispatch.sh

Replace the stub with the full implementation:

```bash
run_scrollback_mode() {
    if [[ -z "$PANE_ID" ]]; then
        _dispatch_error "scrollback requires a pane — use keybinding, not direct invocation"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    local become_files_empty="$BECOME_FILES"

    # Capture scrollback from originating pane, dedup, reverse (most recent first)
    local scrollback
    scrollback=$(tmux capture-pane -t "$PANE_ID" -p -S "-${SCROLLBACK_LINES}" 2>/dev/null \
        | awk 'NF && !seen[$0]++' \
        | tac)

    if [[ -z "$scrollback" ]]; then
        _dispatch_error "scrollback is empty"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    # Build context preview: show surrounding lines from scrollback
    # We write scrollback to a temp file so preview can grep for context
    local scrollback_file
    scrollback_file=$(mktemp "${TMPDIR:-/tmp}/dispatch-scrollback-XXXXXX")
    trap 'command rm -f "$scrollback_file"' EXIT
    echo "$scrollback" > "$scrollback_file"
    local sq_scrollback_file
    sq_scrollback_file=$(_sq_escape "$scrollback_file")

    # Preview: show 5 lines of context around the selected line
    local preview_cmd="grep -nFx -- {} '$sq_scrollback_file' | head -1 | cut -d: -f1 | xargs -I{n} awk -v n={n} 'NR>=n-5 && NR<=n+5 { if (NR==n) printf \"\\033[1;33m> %s\\033[0m\\n\", \$0; else print \"  \" \$0 }' '$sq_scrollback_file'"

    # History file for Ctrl+X deletion
    local sq_histfile
    sq_histfile=$(_sq_escape "${HISTFILE:-}")

    local result
    result=$(echo "$scrollback" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --expect=ctrl-o,ctrl-y \
        --multi \
        --query "$QUERY" \
        --prompt 'scrollback $ ' \
        --ansi \
        --no-sort \
        --border-label ' scrollback $ · ? help · enter copy · ^o paste · ^x delete · S-tab select · ⌫ files ' \
        --border-label-pos 'center:bottom' \
        --preview "$preview_cmd" \
        --bind "ctrl-x:execute-silent(HISTFILE='$sq_histfile' '$SQ_SCRIPT_DIR/actions.sh' delete-history {})+reload(cat '$sq_scrollback_file')" \
        --bind "backward-eof:$become_files_empty" \
        --bind "?:preview:printf '%b' '$SQ_HELP_SCROLLBACK'" \
    ) || exit 0

    handle_scrollback_result "$result"
}

handle_scrollback_result() {
    local result="$1"
    local key
    local -a lines

    key=$(head -1 <<< "$result")
    mapfile -t lines < <(tail -n +2 <<< "$result")
    [[ ${#lines[@]} -eq 0 ]] && exit 0

    case "$key" in
        ctrl-o)
            # Paste to pane
            if [[ -n "$PANE_ID" ]]; then
                local text
                text=$(printf '%s\n' "${lines[@]}")
                tmux send-keys -t "$PANE_ID" "$text"
                tmux display-message "Sent ${#lines[@]} line(s) to pane"
            fi
            ;;
        ctrl-y|*)
            # Copy to clipboard (default action)
            printf '%s\n' "${lines[@]}" | tmux load-buffer -w -
            tmux display-message "Copied ${#lines[@]} line(s)"
            ;;
    esac
}
```

### Step 8: Run full test suite + lint

Run: `bats tests/ && shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh`
Expected: All pass

### Step 9: Commit

```bash
git add scripts/dispatch.sh scripts/actions.sh tests/dispatch.bats tests/actions.bats
git commit -m "feat(dispatch): implement scrollback search mode

Capture pane scrollback, deduplicate, reverse for recency. Fuzzy search
with context preview. Enter copies to clipboard, Ctrl+O pastes to pane,
Ctrl+X deletes from shell history. Configurable depth via
@dispatch-scrollback-lines (default: 10000)."
```

---

## Task 4: Custom Commands Mode — Skeleton and Mode Switching

**Files:**
- Modify: `scripts/dispatch.sh` (change_transform, welcome guide, help string, dispatch case)
- Test: `tests/dispatch.bats`

### Step 1: Write the failing test

Add to `tests/dispatch.bats`:

```bash
# ─── Commands mode ───────────────────────────────────────────────────────

@test "commands mode strips leading : from query" {
    run bash -c '
        QUERY=":deploy"
        QUERY="${QUERY#:}"
        echo "$QUERY"
    '
    [ "$output" = "deploy" ]
}
```

### Step 2: Run test

Run: `bats tests/dispatch.bats --filter "commands mode"`
Expected: PASS (pure bash)

### Step 3: Add `:` prefix to change_transform

After the `$` scrollback prefix check (added in Task 2), add:

```bash
elif [[ {q} == ':'* ]]; then
  echo \"become('$SQ_SCRIPT_DIR/dispatch.sh' --mode=commands --pane='$SQ_PANE_ID' --query={q})\"
```

### Step 4: Add commands to _strip_mode_prefix

```bash
        commands)   QUERY="${QUERY#:}" ;;
```

### Step 5: Add help string

```bash
HELP_COMMANDS="$(printf '%b' '
  \033[1mCOMMANDS\033[0m
  \033[38;5;244m─────────────────────────────\033[0m
  enter     run command
  ^E        edit commands.conf
  ⌫ empty   back to files

  ^D/^U     scroll preview
')"

SQ_HELP_COMMANDS=$(_sq_escape "$HELP_COMMANDS")
```

### Step 6: Update welcome guide

Add to the mode switching section:

```
  \\033[38;5;103m:\\033[0m  custom commands
```

### Step 7: Add stub and dispatch entry

```bash
run_commands_mode() {
    _dispatch_error "commands mode: not yet implemented"
    exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
}
```

Dispatch case:

```bash
    commands)       run_commands_mode ;;
```

### Step 8: Run tests + lint

Run: `bats tests/ && shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh`
Expected: All pass

### Step 9: Commit

```bash
git add scripts/dispatch.sh tests/dispatch.bats
git commit -m "feat(dispatch): add commands mode skeleton with : prefix switching

Registers commands as a valid mode, adds : prefix detection to
files mode change:transform, adds help string and welcome guide entry.
Mode is a stub — implementation follows."
```

---

## Task 5: Custom Commands Mode — Full Implementation

**Files:**
- Modify: `scripts/dispatch.sh` (replace stub `run_commands_mode`)
- Test: `tests/dispatch.bats` (config parsing tests)

### Step 1: Write failing tests for config parsing

Add to `tests/dispatch.bats`:

```bash
@test "commands config: parses label|command format" {
    local conf="$BATS_TEST_TMPDIR/commands.conf"
    printf '# comment\nDeploy | ssh deploy.sh\n\nRestart | systemctl restart\n' > "$conf"
    run bash -c '
        grep -v "^#" "'"$conf"'" | grep -v "^[[:space:]]*$" | while IFS="|" read -r label cmd; do
            label="${label## }"; label="${label%% }"
            cmd="${cmd## }"; cmd="${cmd%% }"
            echo "$label:$cmd"
        done
    '
    [ "${lines[0]}" = "Deploy:ssh deploy.sh" ]
    [ "${lines[1]}" = "Restart:systemctl restart" ]
}

@test "commands config: handles missing file gracefully" {
    run bash -c '
        conf="/nonexistent/commands.conf"
        if [[ ! -f "$conf" ]]; then
            echo "no-config"
        fi
    '
    [ "$output" = "no-config" ]
}

@test "commands config: identifies tmux commands by prefix" {
    run bash -c '
        cmd="tmux: split-window -h"
        if [[ "$cmd" == "tmux: "* ]]; then
            echo "tmux-cmd:${cmd#tmux: }"
        else
            echo "shell-cmd:$cmd"
        fi
    '
    [ "$output" = "tmux-cmd:split-window -h" ]
}
```

### Step 2: Run tests

Run: `bats tests/dispatch.bats --filter "commands config"`
Expected: PASS (pure bash logic tests)

### Step 3: Implement run_commands_mode

Replace the stub with:

```bash
run_commands_mode() {
    local become_files_empty="$BECOME_FILES"
    local conf="$COMMANDS_FILE"

    # If config doesn't exist, show empty state with hint
    if [[ ! -f "$conf" ]]; then
        local result
        result=$(echo "" | fzf \
            "${BASE_FZF_OPTS[@]}" \
            --query "$QUERY" \
            --prompt 'commands : ' \
            --header "No commands configured — press ^E to create $(basename "$conf")" \
            --border-label ' commands : · ? help · ^e edit · ⌫ files ' \
            --border-label-pos 'center:bottom' \
            --bind "ctrl-e:execute($POPUP_EDITOR '$(_sq_escape "$conf")')+abort" \
            --bind "backward-eof:$become_files_empty" \
            --bind "?:preview:printf '%b' '$SQ_HELP_COMMANDS'" \
        ) || exit 0
        exit 0
    fi

    # Parse config: extract labels for fzf, keep full lines for lookup
    local entries
    entries=$(grep -v '^#' "$conf" | grep -v '^[[:space:]]*$')

    if [[ -z "$entries" ]]; then
        _dispatch_error "commands.conf is empty — press ^E to add commands"
        exec "$SCRIPT_DIR/dispatch.sh" --mode=files --pane="$PANE_ID"
    fi

    # Display labels (left of |), preview shows command (right of |)
    local labels
    labels=$(echo "$entries" | while IFS='|' read -r label _; do
        label="${label## }"; label="${label%% }"
        echo "$label"
    done)

    local sq_conf
    sq_conf=$(_sq_escape "$conf")

    # Preview: show the command for the selected label
    local preview_cmd="grep -F {} '$sq_conf' | head -1 | sed 's/^[^|]*|[[:space:]]*//' "

    local result
    result=$(echo "$labels" | fzf \
        "${BASE_FZF_OPTS[@]}" \
        --query "$QUERY" \
        --prompt 'commands : ' \
        --no-sort \
        --border-label ' commands : · ? help · enter run · ^e edit · ⌫ files ' \
        --border-label-pos 'center:bottom' \
        --preview "$preview_cmd" \
        --bind "ctrl-e:execute($POPUP_EDITOR '$sq_conf')+abort" \
        --bind "backward-eof:$become_files_empty" \
        --bind "?:preview:printf '%b' '$SQ_HELP_COMMANDS'" \
    ) || exit 0

    [[ -z "$result" ]] && exit 0

    # Look up the command for the selected label
    local selected_cmd
    selected_cmd=$(grep -F "$result" "$conf" | head -1 | sed 's/^[^|]*|[[:space:]]*//')
    [[ -z "$selected_cmd" ]] && exit 0

    # Execute: tmux command or shell command
    if [[ "$selected_cmd" == "tmux: "* ]]; then
        tmux ${selected_cmd#tmux: }
    else
        bash -c "$selected_cmd"
    fi
}
```

### Step 4: Run full test suite + lint

Run: `bats tests/ && shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh`
Expected: All pass

### Step 5: Commit

```bash
git add scripts/dispatch.sh tests/dispatch.bats
git commit -m "feat(dispatch): implement custom commands mode

Parse ~/.config/tmux-dispatch/commands.conf (label | command format).
Fuzzy search labels, preview shows command, Enter executes. Supports
tmux: prefix for tmux commands. Ctrl+E opens config in editor.
Configurable path via @dispatch-commands-file."
```

---

## Task 6: Tests — Comprehensive Coverage for New Modes

**Files:**
- Modify: `tests/dispatch.bats` (additional edge case tests)
- Modify: `tests/actions.bats` (additional delete-history edge cases)

### Step 1: Add edge case tests

Add to `tests/dispatch.bats`:

```bash
@test "scrollback: $ prefix triggers mode switch in transform pattern" {
    run bash -c '
        query="\$search term"
        if [[ "$query" == "\$"* ]]; then
            echo "scrollback"
        else
            echo "other"
        fi
    '
    [ "$output" = "scrollback" ]
}

@test "commands: : prefix triggers mode switch in transform pattern" {
    run bash -c '
        query=":deploy"
        if [[ "$query" == ":"* ]]; then
            echo "commands"
        else
            echo "other"
        fi
    '
    [ "$output" = "commands" ]
}

@test "dispatch: scrollback mode is valid" {
    run bash -c '
        source "'"$SCRIPT_DIR"'/dispatch.sh" --mode=scrollback 2>&1 || true
    '
    # Should not say "Unknown mode" (will fail for other reasons without tmux)
    [[ "$output" != *"Unknown mode"* ]]
}

@test "dispatch: commands mode is valid" {
    run bash -c '
        source "'"$SCRIPT_DIR"'/dispatch.sh" --mode=commands 2>&1 || true
    '
    [[ "$output" != *"Unknown mode"* ]]
}
```

Add to `tests/actions.bats`:

```bash
@test "delete-history: removes all occurrences of duplicate line" {
    local histfile="$BATS_TEST_TMPDIR/test_history"
    printf 'ls\ncd /tmp\nls\ngit status\ncd /tmp\n' > "$histfile"
    HISTFILE="$histfile" run bash -c '
        source "'"$SCRIPT_DIR"'/actions.sh" delete-history "cd /tmp"
    '
    run grep -c "cd /tmp" "$histfile"
    [ "$output" = "0" ]
}

@test "delete-history: preserves file when line not found" {
    local histfile="$BATS_TEST_TMPDIR/test_history"
    printf 'ls\ngit status\n' > "$histfile"
    local before
    before=$(cat "$histfile")
    HISTFILE="$histfile" run bash -c '
        source "'"$SCRIPT_DIR"'/actions.sh" delete-history "nonexistent"
    '
    local after
    after=$(cat "$histfile")
    [ "$before" = "$after" ]
}
```

### Step 2: Run all tests

Run: `bats tests/`
Expected: All pass

### Step 3: Commit

```bash
git add tests/dispatch.bats tests/actions.bats
git commit -m "test: add comprehensive tests for scrollback and commands modes

Edge cases for prefix detection, mode validation, history deletion
with duplicates, and missing config files."
```

---

## Task 7: Launch Polish — CHANGELOG and Documentation

**Files:**
- Modify: `CHANGELOG.md`
- Create: `docs/modes/scrollback.md`
- Create: `docs/modes/commands.md`
- Modify: `docs/modes/index.md`
- Modify: `docs/reference/keybindings.md`
- Modify: `docs/reference/configuration.md`
- Modify: `docs/features/mode-switching.md`

### Step 1: Update CHANGELOG.md

Add to the `[1.0.0]` "Added" section under "Modes:":

```markdown
- Scrollback search mode (`$` prefix) with context preview, clipboard copy, pane paste, and shell history deletion
- Custom user commands mode (`:` prefix) with configurable `commands.conf` file, tmux/shell command support, and inline config editing
```

Add under "Configuration:":

```markdown
- `@dispatch-scrollback-lines` option — number of scrollback lines to capture (default: 10000)
- `@dispatch-commands-file` option — custom commands config file path
```

Add under a new "Performance:" subcategory:

```markdown
- Cached tool detection at plugin load — reduces popup open overhead by ~40-50ms
- Batched tmux option reads — single subprocess instead of six
```

### Step 2: Create docs/modes/scrollback.md

Write mode documentation following the pattern of existing mode docs (see `docs/modes/grep.md` for format).

### Step 3: Create docs/modes/commands.md

Write mode documentation with config file format reference.

### Step 4: Update index and reference docs

- `docs/modes/index.md` — add scrollback and commands to the mode tree
- `docs/reference/keybindings.md` — add new mode keybindings table rows
- `docs/reference/configuration.md` — add new option descriptions
- `docs/features/mode-switching.md` — add `$` and `:` to prefix table

### Step 5: Commit

```bash
git add CHANGELOG.md docs/
git commit -m "docs: add scrollback and commands mode documentation

New mode pages, updated keybindings reference, configuration options,
mode-switching guide, and CHANGELOG entries for v1.0.0."
```

---

## Task 8: Launch Polish — README Refresh

**Files:**
- Modify: `README.md`

### Step 1: Update README

- Add scrollback and commands to Features list
- Add `$` and `:` to Quick Start prefix table
- Update "How is this different?" with:
  - "Scrollback search" — search and copy from terminal output without extra plugins
  - "Custom commands" — define your own command palette entries
  - Position as "replaces 3-4 separate plugins with one unified popup"
- Update Similar Projects list: add extrakto, sesh, tmux-which-key
- Update mode switching section: add new prefixes

### Step 2: Commit

```bash
git add README.md
git commit -m "docs: update README with scrollback, commands, and competitive positioning

Add new modes to features list and quick start table. Sharpen
'How is this different?' section. Add extrakto, sesh, tmux-which-key
to similar projects."
```

---

## Task 9: Demo GIFs

**Files:**
- Create: `tapes/scrollback.tape`
- Create: `tapes/commands.tape`
- Modify: `tapes/demo.tape`
- Modify: `tapes/mode-switching.tape`

### Step 1: Create scrollback.tape

Follow the pattern of existing tapes (see `tapes/grep.tape`). Show:
1. Run some commands in the pane
2. Open dispatch, type `$`
3. Search scrollback, select a line
4. Copy to clipboard
5. Ctrl+X to delete from history

### Step 2: Create commands.tape

Show:
1. Open dispatch, type `:`
2. Search custom commands
3. Execute a command

### Step 3: Update demo.tape and mode-switching.tape

Add brief scrollback and commands flashes to the mode-switching sequence.

### Step 4: Record all tapes sequentially

Run: `for tape in tapes/*.tape; do vhs "$tape"; done`
(Must be sequential — shared tmux socket)

### Step 5: Commit

```bash
git add tapes/ assets/
git commit -m "docs: add scrollback and commands demo GIFs, update hero demo

New VHS tapes for scrollback and commands modes. Updated demo.tape
and mode-switching.tape to include new mode prefixes."
```

---

## Summary

| Task | Scope | Est. LOC |
|------|-------|----------|
| 1. Performance caching | dispatch.tmux, dispatch.sh, helpers.sh | ~50 |
| 2. Scrollback skeleton | dispatch.sh (mode switching) | ~30 |
| 3. Scrollback implementation | dispatch.sh, actions.sh | ~100 |
| 4. Commands skeleton | dispatch.sh (mode switching) | ~25 |
| 5. Commands implementation | dispatch.sh | ~80 |
| 6. Tests | dispatch.bats, actions.bats | ~60 |
| 7. Docs (CHANGELOG + mode docs) | docs/ | ~150 |
| 8. README refresh | README.md | ~30 |
| 9. Demo GIFs | tapes/ | ~80 |

**Total: ~605 lines across 9 commits**
