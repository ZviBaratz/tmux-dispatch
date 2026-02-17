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

@test "record_file_open: appends tab-delimited entries with timestamp" {
    record_file_open "/home/user/project" "src/main.rs"
    wait  # wait for background trim
    local hf
    hf=$(_dispatch_history_file)
    local line
    line=$(cat "$hf")
    # Format: pwd\tfile\tepoch
    [[ "$line" == "/home/user/project	src/main.rs	"* ]]
    # Third field should be a valid epoch
    local ts
    ts=$(cut -f3 <<< "$line")
    [[ "$ts" =~ ^[0-9]+$ ]]
}

@test "record_file_open: normalizes ./ prefix" {
    record_file_open "/home/user/project" "./src/lib.rs"
    wait
    local hf
    hf=$(_dispatch_history_file)
    local line
    line=$(cat "$hf")
    [[ "$line" == "/home/user/project	src/lib.rs	"* ]]
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
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    # Create real files
    mkdir -p "$BATS_TEST_TMPDIR/projA" "$BATS_TEST_TMPDIR/projB"
    touch "$BATS_TEST_TMPDIR/projA/a.txt"
    touch "$BATS_TEST_TMPDIR/projB/b.txt"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/projA" "a.txt" "$now" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/projB" "b.txt" "$now" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/projA"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.txt" ]
    [ "${#lines[@]}" -eq 1 ]
}

@test "recent_files_for_pwd: recent file ranks above old file" {
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/old.txt" "$BATS_TEST_TMPDIR/proj/new.txt"
    # old.txt opened 1 week ago, new.txt opened just now
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "old.txt" "$((now - 604800))" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "new.txt" "$now" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${lines[0]}" = "new.txt" ]
    [ "${lines[1]}" = "old.txt" ]
}

@test "recent_files_for_pwd: deduplicates (frecency accumulates)" {
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/dup.txt"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "dup.txt" "$now" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "dup.txt" "$now" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "dup.txt" "$now" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "dup.txt" ]
}

@test "recent_files_for_pwd: skips deleted files" {
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/exists.txt"
    # Don't create "gone.txt" — it doesn't exist
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "gone.txt" "$now" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "exists.txt" "$now" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "exists.txt" ]
}

@test "recent_files_for_pwd: caps at max" {
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    for i in $(seq 1 10); do
        touch "$BATS_TEST_TMPDIR/proj/file${i}.txt"
        printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "file${i}.txt" "$now" >> "$hf"
    done
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj" 3
    [ "${#lines[@]}" -eq 3 ]
}

@test "recent_files_for_pwd: empty when no history" {
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/nonexistent"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "recent_files_for_pwd: handles glob metacharacters in filenames" {
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    # Files with glob metacharacters: [, *, ?
    touch "$BATS_TEST_TMPDIR/proj/test[1].txt"
    touch "$BATS_TEST_TMPDIR/proj/star*.log"
    touch "$BATS_TEST_TMPDIR/proj/what?.md"
    # Give each file a slightly different time so sort order is deterministic
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "test[1].txt" "$((now - 3600))" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "star*.log" "$((now - 1800))" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "what?.md" "$now" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    # Highest frecency first (most recent = highest score)
    [ "${lines[0]}" = "what?.md" ]
    [ "${lines[1]}" = "star*.log" ]
    [ "${lines[2]}" = "test[1].txt" ]
}

@test "recent_files_for_pwd: deduplicates files with glob metacharacters" {
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/test[1].txt"
    # Same file opened multiple times
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "test[1].txt" "$now" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "test[1].txt" "$now" >> "$hf"
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "test[1].txt" "$now" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "test[1].txt" ]
}

# ─── Frecency-specific tests ─────────────────────────────────────────────

@test "frecency: frequent file ranks above recent one-shot" {
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/frequent.txt" "$BATS_TEST_TMPDIR/proj/recent.txt"
    # frequent.txt: opened 20 times over the past 2 days
    for i in $(seq 1 20); do
        printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "frequent.txt" "$((now - 3600 * i))" >> "$hf"
    done
    # recent.txt: opened once just now
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "recent.txt" "$now" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${lines[0]}" = "frequent.txt" ]
    [ "${lines[1]}" = "recent.txt" ]
}

# ─── Bookmarks ────────────────────────────────────────────────────────────

@test "toggle_bookmark: adds a bookmark" {
    local bf
    bf=$(_dispatch_bookmark_file)
    run toggle_bookmark "$BATS_TEST_TMPDIR/proj" "src/main.rs"
    [ "$output" = "added" ]
    [ -f "$bf" ]
    run cat "$bf"
    [[ "${lines[0]}" == *"src/main.rs"* ]]
}

@test "toggle_bookmark: removes an existing bookmark" {
    local bf
    bf=$(_dispatch_bookmark_file)
    toggle_bookmark "$BATS_TEST_TMPDIR/proj" "src/main.rs"
    run toggle_bookmark "$BATS_TEST_TMPDIR/proj" "src/main.rs"
    [ "$output" = "removed" ]
    local count
    count=$(wc -l < "$bf" 2>/dev/null) || count=0
    [ "$count" -eq 0 ]
}

@test "toggle_bookmark: normalizes ./ prefix" {
    local bf
    bf=$(_dispatch_bookmark_file)
    toggle_bookmark "$BATS_TEST_TMPDIR/proj" "./src/lib.rs"
    run cat "$bf"
    # Should be stored without ./
    [[ "${lines[0]}" == *"src/lib.rs"* ]]
}

@test "bookmarks_for_pwd: returns bookmarks for matching directory" {
    local bf
    bf=$(_dispatch_bookmark_file)
    mkdir -p "$BATS_TEST_TMPDIR/projA" "$BATS_TEST_TMPDIR/projB"
    touch "$BATS_TEST_TMPDIR/projA/a.txt" "$BATS_TEST_TMPDIR/projB/b.txt"
    toggle_bookmark "$BATS_TEST_TMPDIR/projA" "a.txt"
    toggle_bookmark "$BATS_TEST_TMPDIR/projB" "b.txt"
    run bookmarks_for_pwd "$BATS_TEST_TMPDIR/projA"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "a.txt" ]
}

@test "bookmarks_for_pwd: skips deleted files" {
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/exists.txt"
    toggle_bookmark "$BATS_TEST_TMPDIR/proj" "exists.txt"
    toggle_bookmark "$BATS_TEST_TMPDIR/proj" "gone.txt"
    run bookmarks_for_pwd "$BATS_TEST_TMPDIR/proj"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "exists.txt" ]
}

@test "bookmarks_for_pwd: empty when no bookmarks file" {
    run bookmarks_for_pwd "/nonexistent/path"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ─── Edge cases ──────────────────────────────────────────────────────────────

@test "recent_files_for_pwd: handles malformed history lines gracefully" {
    local hfile="$XDG_DATA_HOME/tmux-dispatch/history"
    mkdir -p "$(dirname "$hfile")"
    # Write malformed lines (missing fields, empty lines)
    printf 'not-a-valid-line\n' > "$hfile"
    printf '\n' >> "$hfile"
    printf '%s\t%s\t%s\n' "$(date +%s)" "1" "$BATS_TEST_TMPDIR/valid.txt" >> "$hfile"

    cd "$BATS_TEST_TMPDIR"
    run recent_files_for_pwd 50
    # Should not crash
    [[ "$status" -eq 0 ]]
}

@test "frecency: old format lines (no timestamp) get low score" {
    local hf now
    hf=$(_dispatch_history_file)
    now=$(date +%s)
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    touch "$BATS_TEST_TMPDIR/proj/old-format.txt" "$BATS_TEST_TMPDIR/proj/new-format.txt"
    # old-format entry (no timestamp — legacy 2-column)
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "old-format.txt" >> "$hf"
    # new-format entry (with recent timestamp)
    printf '%s\t%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "new-format.txt" "$now" >> "$hf"
    run recent_files_for_pwd "$BATS_TEST_TMPDIR/proj"
    # New-format file should rank higher (recent timestamp beats legacy-assumed-old)
    [ "${lines[0]}" = "new-format.txt" ]
    [ "${lines[1]}" = "old-format.txt" ]
}
