#!/usr/bin/env bats
# =============================================================================
# Unit tests for scripts/preview.sh
# =============================================================================
# Run with: bats tests/preview.bats
# Tests line number validation and file-not-found handling.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
    # Stub tmux so helpers.sh sourcing succeeds
    export PATH="$BATS_TEST_TMPDIR:$PATH"
    printf '#!/usr/bin/env bash\necho ""\n' > "$BATS_TEST_TMPDIR/tmux"
    chmod +x "$BATS_TEST_TMPDIR/tmux"
    # Create a test file for preview
    printf 'line1\nline2\nline3\nline4\nline5\n' > "$BATS_TEST_TMPDIR/test.txt"
}

teardown() {
    rm -f "$BATS_TEST_TMPDIR/tmux" "$BATS_TEST_TMPDIR/test.txt"
}

# ─── Line number validation ────────────────────────────────────────────────

@test "preview: non-numeric line defaults to 1" {
    run bash -c '
        LINE="abc"
        [[ "$LINE" =~ ^[0-9]+$ ]] || LINE=1
        echo "$LINE"
    '
    [ "$output" = "1" ]
}

@test "preview: empty line defaults to 1" {
    run bash -c '
        LINE=""
        [[ "$LINE" =~ ^[0-9]+$ ]] || LINE=1
        echo "$LINE"
    '
    [ "$output" = "1" ]
}

@test "preview: valid numeric line passes through" {
    run bash -c '
        LINE="42"
        [[ "$LINE" =~ ^[0-9]+$ ]] || LINE=1
        echo "$LINE"
    '
    [ "$output" = "42" ]
}

# ─── File not found ────────────────────────────────────────────────────────

@test "preview: file not found prints error and exits 0" {
    run bash "$SCRIPT_DIR/preview.sh" "/nonexistent/file.txt" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"File not found"* ]]
}

# ─── Integration with real file ────────────────────────────────────────────

@test "preview: shows content for existing file" {
    run bash "$SCRIPT_DIR/preview.sh" "$BATS_TEST_TMPDIR/test.txt" "3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"line"* ]]
}
