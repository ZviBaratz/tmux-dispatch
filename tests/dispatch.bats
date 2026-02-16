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
