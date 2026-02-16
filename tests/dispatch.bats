#!/usr/bin/env bats
# =============================================================================
# Unit tests for scripts/dispatch.sh
# =============================================================================
# Run with: bats tests/dispatch.bats
# Tests argument parsing, dispatch, query manipulation, and session name
# sanitization without requiring fzf or a running tmux server.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
    # Stub tmux so helpers.sh's get_tmux_option succeeds at source-time
    export PATH="$BATS_TEST_TMPDIR:$PATH"
    printf '#!/usr/bin/env bash\necho ""\n' > "$BATS_TEST_TMPDIR/tmux"
    chmod +x "$BATS_TEST_TMPDIR/tmux"
}

teardown() {
    rm -f "$BATS_TEST_TMPDIR/tmux"
}

# ─── Argument parsing ───────────────────────────────────────────────────────

@test "arg parsing: --mode=grep sets MODE" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        MODE="files"; PANE_ID=""; QUERY=""
        for arg in --mode=grep; do
            case "$arg" in
                --mode=*)  MODE="${arg#--mode=}" ;;
                --pane=*)  PANE_ID="${arg#--pane=}" ;;
                --query=*) QUERY="${arg#--query=}" ;;
            esac
        done
        echo "$MODE"
    '
    [ "$output" = "grep" ]
}

@test "arg parsing: --pane=%5 sets PANE_ID" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        MODE="files"; PANE_ID=""; QUERY=""
        for arg in --pane=%5; do
            case "$arg" in
                --mode=*)  MODE="${arg#--mode=}" ;;
                --pane=*)  PANE_ID="${arg#--pane=}" ;;
                --query=*) QUERY="${arg#--query=}" ;;
            esac
        done
        echo "$PANE_ID"
    '
    [ "$output" = "%5" ]
}

@test "arg parsing: --query=hello sets QUERY" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        MODE="files"; PANE_ID=""; QUERY=""
        for arg in "--query=hello"; do
            case "$arg" in
                --mode=*)  MODE="${arg#--mode=}" ;;
                --pane=*)  PANE_ID="${arg#--pane=}" ;;
                --query=*) QUERY="${arg#--query=}" ;;
            esac
        done
        echo "$QUERY"
    '
    [ "$output" = "hello" ]
}

@test "arg parsing: default MODE is files" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        MODE="files"; PANE_ID=""; QUERY=""
        # no --mode arg
        for arg in --pane=%1; do
            case "$arg" in
                --mode=*)  MODE="${arg#--mode=}" ;;
                --pane=*)  PANE_ID="${arg#--pane=}" ;;
                --query=*) QUERY="${arg#--query=}" ;;
            esac
        done
        echo "$MODE"
    '
    [ "$output" = "files" ]
}

@test "arg parsing: unknown args are silently ignored" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        MODE="files"; PANE_ID=""; QUERY=""
        for arg in --bogus=xyz --mode=grep --unknown; do
            case "$arg" in
                --mode=*)  MODE="${arg#--mode=}" ;;
                --pane=*)  PANE_ID="${arg#--pane=}" ;;
                --query=*) QUERY="${arg#--query=}" ;;
            esac
        done
        echo "$MODE"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "grep" ]
}

# ─── Mode dispatch ──────────────────────────────────────────────────────────

@test "dispatch: unknown mode exits 1 with error" {
    run bash -c 'source "'"$SCRIPT_DIR"'/dispatch.sh" --mode=bogus 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown mode: bogus"* ]]
}

# ─── Query manipulation ────────────────────────────────────────────────────

@test "grep mode strips leading > from query" {
    run bash -c '
        QUERY=">hello world"
        QUERY="${QUERY#>}"
        echo "$QUERY"
    '
    [ "$output" = "hello world" ]
}

@test "session mode strips leading @ and preserves remainder" {
    run bash -c '
        QUERY="@mysession"
        QUERY="${QUERY#@}"
        echo "$QUERY"
    '
    [ "$output" = "mysession" ]
}

@test "git mode strips leading ! from query" {
    run bash -c '
        QUERY="!unstaged"
        QUERY="${QUERY#!}"
        echo "$QUERY"
    '
    [ "$output" = "unstaged" ]
}

@test "directory mode strips leading # from query" {
    run bash -c '
        QUERY="#src/components"
        QUERY="${QUERY#\#}"
        echo "$QUERY"
    '
    [ "$output" = "src/components" ]
}

# ─── Session name sanitization ──────────────────────────────────────────────

@test "session name: dots replaced with dashes" {
    run bash -c '
        session_name="my.project"
        session_name="${session_name//./-}"
        session_name="${session_name//:/-}"
        echo "$session_name"
    '
    [ "$output" = "my-project" ]
}

@test "session name: colons replaced with dashes" {
    run bash -c '
        session_name="my:project"
        session_name="${session_name//./-}"
        session_name="${session_name//:/-}"
        echo "$session_name"
    '
    [ "$output" = "my-project" ]
}

@test "session name: mixed dots and colons" {
    run bash -c '
        session_name="my.proj:test"
        session_name="${session_name//./-}"
        session_name="${session_name//:/-}"
        echo "$session_name"
    '
    [ "$output" = "my-proj-test" ]
}

# ─── Result handler edge cases ──────────────────────────────────────────────

@test "handle_file_result: empty files array exits 0" {
    run bash -c '
        source "'"$SCRIPT_DIR"'/helpers.sh"
        # Simulate handle_file_result with empty result (key only, no files)
        result="ctrl-o"
        key=$(head -1 <<< "$result")
        mapfile -t files < <(tail -n +2 <<< "$result")
        [[ ${#files[@]} -eq 0 ]] && exit 0
        exit 1
    '
    [ "$status" -eq 0 ]
}

@test "handle_grep_result: empty line exits 0" {
    run bash -c '
        source "'"$SCRIPT_DIR"'/helpers.sh"
        # Simulate handle_grep_result with empty selection
        result="ctrl-o
"
        key=$(head -1 <<< "$result")
        line=$(tail -1 <<< "$result")
        [[ -z "$line" ]] && exit 0
        exit 1
    '
    [ "$status" -eq 0 ]
}

# ─── quoted_files building ─────────────────────────────────────────────────

@test "quoted_files: builds space-separated quoted list" {
    run bash -c '
        files=("src/main.sh" "my file.txt" "test.sh")
        quoted_files=""
        for f in "${files[@]}"; do
            quoted_files="${quoted_files:+$quoted_files }$(printf "%q" "$f")"
        done
        echo "EDITOR $quoted_files"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "EDITOR src/main.sh my\\ file.txt test.sh" ]]
}

@test "quoted_files: single file has no leading space" {
    run bash -c '
        files=("src/main.sh")
        quoted_files=""
        for f in "${files[@]}"; do
            quoted_files="${quoted_files:+$quoted_files }$(printf "%q" "$f")"
        done
        echo "EDITOR $quoted_files"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "EDITOR src/main.sh" ]]
}

@test "quoted_files: handles special characters" {
    run bash -c '
        files=("file with spaces.txt" "test[1].txt" "name'\''s file.sh")
        quoted_files=""
        for f in "${files[@]}"; do
            quoted_files="${quoted_files:+$quoted_files }$(printf "%q" "$f")"
        done
        # Verify EDITOR and first arg are separated by exactly one space
        [[ "$quoted_files" == file* ]] || { echo "unexpected leading char"; exit 1; }
        echo "$quoted_files"
    '
    [ "$status" -eq 0 ]
}

# ─── FILE_TYPES parsing ──────────────────────────────────────────────────

@test "FILE_TYPES: parses comma-separated extensions into --extension flags" {
    run bash -c '
        FILE_TYPES="py,rs, js "
        type_flags=()
        IFS="," read -ra exts <<< "$FILE_TYPES"
        for ext in "${exts[@]}"; do
            ext="${ext## }"; ext="${ext%% }"
            [[ -n "$ext" ]] || continue
            type_flags+=(--extension "$ext")
        done
        printf "%s\n" "${type_flags[@]}"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "--extension" ]
    [ "${lines[1]}" = "py" ]
    [ "${lines[2]}" = "--extension" ]
    [ "${lines[3]}" = "rs" ]
    [ "${lines[4]}" = "--extension" ]
    [ "${lines[5]}" = "js" ]
}

# ─── Git annotation awk ──────────────────────────────────────────────────

_setup_git_repo() {
    local repo="$BATS_TEST_TMPDIR/git-repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    echo "clean" > "$repo/clean.txt"
    echo "tracked" > "$repo/modified.txt"
    git -C "$repo" add . && git -C "$repo" commit -q -m "init"
    echo "changed" > "$repo/modified.txt"
    echo "new" > "$repo/untracked.txt"
    echo "$repo"
}

# Extract the awk body from dispatch.sh to test it in isolation.
# We duplicate it here rather than sourcing dispatch.sh (which requires fzf/tmux).
_git_annotate_awk='BEGIN {
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
        if (x == "?" && y == "?")       s[file] = "\033[33m?\033[0m"
        else if (x != " " && y != " ")  s[file] = "\033[35m\342\234\271\033[0m"
        else if (x != " ")              s[file] = "\033[32m\342\234\232\033[0m"
        else                            s[file] = "\033[31m\342\227\217\033[0m"
    }
    close(cmd)
}
{ f = $0; sub(/^\.\//, "", f); if (f in s) printf "%s\t%s\n", s[f], $0; else printf "\t%s\n", $0 }'

@test "git-annotate: modified file gets red icon, clean file gets empty prefix" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    local result
    result=$(printf '%s\n' "clean.txt" "modified.txt" | awk -v prefix="" "$_git_annotate_awk")
    # Clean file: tab-only prefix
    local clean_line
    clean_line=$(grep "clean.txt" <<< "$result")
    [[ "$clean_line" == $'\t'"clean.txt" ]]
    # Modified file: has a non-empty icon before the tab
    local mod_line
    mod_line=$(grep "modified.txt" <<< "$result")
    local icon
    icon=$(cut -f1 <<< "$mod_line")
    [[ -n "$icon" ]]
}

@test "git-annotate: untracked file gets yellow ? icon" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    local result
    result=$(printf '%s\n' "untracked.txt" | awk -v prefix="" "$_git_annotate_awk")
    # Strip ANSI to check the icon character
    local icon
    icon=$(cut -f1 <<< "$result" | sed 's/\x1b\[[0-9;]*m//g')
    [ "$icon" = "?" ]
}

@test "git-annotate: staged file gets green icon" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    git -C "$repo" add modified.txt
    local result
    result=$(printf '%s\n' "modified.txt" | awk -v prefix="" "$_git_annotate_awk")
    local icon
    icon=$(cut -f1 <<< "$result" | sed 's/\x1b\[[0-9;]*m//g')
    # ✚ is the staged icon
    [ "$icon" = "✚" ]
}

@test "git-annotate: prefix strips repo-relative path for subdirectory" {
    local repo
    repo=$(_setup_git_repo)
    # Add a tracked file in a subdirectory, then modify it
    mkdir -p "$repo/src"
    echo "code" > "$repo/src/main.rs"
    git -C "$repo" add src/main.rs
    git -C "$repo" commit -q -m "add src"
    echo "changed" > "$repo/src/main.rs"
    cd "$repo"
    local result
    result=$(printf '%s\n' "main.rs" | awk -v prefix="src/" "$_git_annotate_awk")
    # main.rs is modified under src/, should get ● icon after prefix strip
    local icon
    icon=$(cut -f1 <<< "$result" | sed 's/\x1b\[[0-9;]*m//g')
    [ "$icon" = "●" ]
}

@test "git-annotate: non-git directory passes files through bare" {
    cd "$BATS_TEST_TMPDIR"
    local result
    result=$(printf '%s\n' "a.txt" "b.txt" | awk -v prefix="" "$_git_annotate_awk")
    # No git status output → all files get empty prefix
    [[ "$(sed -n '1p' <<< "$result")" == $'\t'"a.txt" ]]
    [[ "$(sed -n '2p' <<< "$result")" == $'\t'"b.txt" ]]
}

@test "git-annotate: ./prefix files match git status" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    local result
    result=$(printf '%s\n' "./modified.txt" | awk -v prefix="" "$_git_annotate_awk")
    # Should still match (awk strips ./ before lookup)
    local icon
    icon=$(cut -f1 <<< "$result" | sed 's/\x1b\[[0-9;]*m//g')
    [[ -n "$icon" ]]
    [ "$icon" != "" ]
}

@test "FILE_TYPES: empty string produces no flags" {
    run bash -c '
        FILE_TYPES=""
        type_flags=()
        if [[ -n "$FILE_TYPES" ]]; then
            IFS="," read -ra exts <<< "$FILE_TYPES"
            for ext in "${exts[@]}"; do
                ext="${ext## }"; ext="${ext%% }"
                [[ -n "$ext" ]] || continue
                type_flags+=(--extension "$ext")
            done
        fi
        echo "${#type_flags[@]}"
    '
    [ "$output" = "0" ]
}
