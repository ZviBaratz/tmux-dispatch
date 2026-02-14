#!/usr/bin/env bats
# =============================================================================
# Unit tests for file history functions in scripts/helpers.sh
# =============================================================================
# Run with: bats tests/history.bats
# Uses $BATS_TEST_TMPDIR for isolation — no real history files touched.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
    source "$SCRIPT_DIR/helpers.sh"
    # Redirect all history to temp dir
    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/xdg"
}

teardown() {
    unset -f command tac tail 2>/dev/null || true
}

# ─── _dispatch_tac ─────────────────────────────────────────────────────────

@test "_dispatch_tac: reverses file lines" {
    printf 'a\nb\nc\n' > "$BATS_TEST_TMPDIR/input"
    run _dispatch_tac "$BATS_TEST_TMPDIR/input"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "c" ]
    [ "${lines[1]}" = "b" ]
    [ "${lines[2]}" = "a" ]
}

# ─── _dispatch_history_file ────────────────────────────────────────────────

@test "_dispatch_history_file: respects XDG_DATA_HOME" {
    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/custom-xdg"
    run _dispatch_history_file
    [ "$status" -eq 0 ]
    [ "$output" = "$BATS_TEST_TMPDIR/custom-xdg/tmux-dispatch/history" ]
    [ -d "$BATS_TEST_TMPDIR/custom-xdg/tmux-dispatch" ]
}

@test "_dispatch_history_file: defaults to ~/.local/share" {
    unset XDG_DATA_HOME
    # Override HOME to keep test isolated
    HOME="$BATS_TEST_TMPDIR/fakehome"
    run _dispatch_history_file
    [ "$status" -eq 0 ]
    [ "$output" = "$BATS_TEST_TMPDIR/fakehome/.local/share/tmux-dispatch/history" ]
}

@test "_dispatch_history_file: creates directory if missing" {
    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/fresh-xdg"
    [ ! -d "$BATS_TEST_TMPDIR/fresh-xdg/tmux-dispatch" ]
    run _dispatch_history_file
    [ -d "$BATS_TEST_TMPDIR/fresh-xdg/tmux-dispatch" ]
}

# ─── record_file_open ─────────────────────────────────────────────────────

@test "record_file_open: appends tab-delimited entries" {
    record_file_open "/home/user/project" "src/main.rs"
    wait  # wait for background trim
    local hf
    hf=$(_dispatch_history_file)
    run cat "$hf"
    [ "${lines[0]}" = "/home/user/project	src/main.rs" ]
}

@test "record_file_open: normalizes ./ prefix" {
    record_file_open "/home/user/project" "./src/lib.rs"
    wait
    local hf
    hf=$(_dispatch_history_file)
    run cat "$hf"
    [ "${lines[0]}" = "/home/user/project	src/lib.rs" ]
}

@test "record_file_open: appends multiple entries" {
    record_file_open "/proj" "a.txt"
    record_file_open "/proj" "b.txt"
    wait
    local hf
    hf=$(_dispatch_history_file)
    local count
    count=$(wc -l < "$hf")
    [ "$count" -eq 2 ]
}

# ─── _dispatch_history_trim ────────────────────────────────────────────────

@test "_dispatch_history_trim: trims when over threshold" {
    local hf="$BATS_TEST_TMPDIR/trim-test"
    # Create 2001 lines
    seq 1 2001 > "$hf"
    run _dispatch_history_trim "$hf"
    [ "$status" -eq 0 ]
    local count
    count=$(wc -l < "$hf")
    [ "$count" -eq 1000 ]
}

@test "_dispatch_history_trim: no-op when under threshold" {
    local hf="$BATS_TEST_TMPDIR/trim-noop"
    seq 1 500 > "$hf"
    run _dispatch_history_trim "$hf"
    [ "$status" -eq 0 ]
    local count
    count=$(wc -l < "$hf")
    [ "$count" -eq 500 ]
}

@test "_dispatch_history_trim: keeps newest entries" {
    local hf="$BATS_TEST_TMPDIR/trim-newest"
    seq 1 2001 > "$hf"
    _dispatch_history_trim "$hf"
    # After trim, last line should be 2001 (newest)
    local last
    last=$(tail -1 "$hf")
    [ "$last" = "2001" ]
    # First line should be 1002 (2001 - 1000 + 1)
    local first
    first=$(head -1 "$hf")
    [ "$first" = "1002" ]
}

# ─── recent_files_for_pwd ─────────────────────────────────────────────────

@test "recent_files_for_pwd: filters by PWD" {
    local hf
    hf=$(_dispatch_history_file)
    # Create real files
    mkdir -p "$BATS_TEST_TMPDIR/projA" "$BATS_TEST_TMPDIR/projB"
    touch "$BATS_TEST_TMPDIR/projA/a.txt"
    touch "$BATS_TEST_TMPDIR/projB/b.txt"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/projA" "a.txt" >> "$hf"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/projB" "b.txt" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/projA"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.txt" ]
    [ "${#lines[@]}" -eq 1 ]
}

@test "recent_files_for_pwd: newest first" {
    local hf
    hf=$(_dispatch_history_file)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/old.txt" "$BATS_TEST_TMPDIR/proj/new.txt"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "old.txt" >> "$hf"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "new.txt" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${lines[0]}" = "new.txt" ]
    [ "${lines[1]}" = "old.txt" ]
}

@test "recent_files_for_pwd: deduplicates" {
    local hf
    hf=$(_dispatch_history_file)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/dup.txt"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "dup.txt" >> "$hf"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "dup.txt" >> "$hf"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "dup.txt" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "dup.txt" ]
}

@test "recent_files_for_pwd: skips deleted files" {
    local hf
    hf=$(_dispatch_history_file)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/exists.txt"
    # Don't create "gone.txt" — it doesn't exist
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "gone.txt" >> "$hf"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "exists.txt" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "exists.txt" ]
}

@test "recent_files_for_pwd: caps at max" {
    local hf
    hf=$(_dispatch_history_file)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    for i in $(seq 1 10); do
        touch "$BATS_TEST_TMPDIR/proj/file${i}.txt"
        printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "file${i}.txt" >> "$hf"
    done
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj" 3
    [ "${#lines[@]}" -eq 3 ]
}

@test "recent_files_for_pwd: empty when no history" {
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/nonexistent"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
