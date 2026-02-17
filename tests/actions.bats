#!/usr/bin/env bats
# =============================================================================
# Unit tests for scripts/actions.sh
# =============================================================================
# Run with: bats tests/actions.bats
# Tests action handlers using temp files and mocked tmux.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
    ACTIONS="$SCRIPT_DIR/actions.sh"

    # Stub tmux so helpers.sh sourcing succeeds
    export PATH="$BATS_TEST_TMPDIR:$PATH"
    printf '#!/usr/bin/env bash\necho ""\n' > "$BATS_TEST_TMPDIR/tmux"
    chmod +x "$BATS_TEST_TMPDIR/tmux"
}

teardown() {
    rm -f "$BATS_TEST_TMPDIR/tmux"
}

# ─── delete-files ─────────────────────────────────────────────────────────────

@test "delete-files: confirmed delete removes files" {
    local f1="$BATS_TEST_TMPDIR/del1.txt"
    local f2="$BATS_TEST_TMPDIR/del2.txt"
    echo "a" > "$f1"
    echo "b" > "$f2"

    run bash -c "echo 'y' | '$ACTIONS' delete-files '$f1' '$f2'"
    [ "$status" -eq 0 ]
    [ ! -f "$f1" ]
    [ ! -f "$f2" ]
    [[ "$output" == *"Deleted"* ]]
}

@test "delete-files: cancelled delete preserves files" {
    local f1="$BATS_TEST_TMPDIR/keep1.txt"
    echo "a" > "$f1"

    run bash -c "echo 'n' | '$ACTIONS' delete-files '$f1'"
    [ "$status" -eq 0 ]
    [ -f "$f1" ]
}

@test "delete-files: empty input cancels" {
    local f1="$BATS_TEST_TMPDIR/keep2.txt"
    echo "a" > "$f1"

    run bash -c "echo '' | '$ACTIONS' delete-files '$f1'"
    [ "$status" -eq 0 ]
    [ -f "$f1" ]
}

@test "delete-files: no args is a no-op" {
    run "$ACTIONS" delete-files
    [ "$status" -eq 0 ]
}

# ─── rename-session ───────────────────────────────────────────────────────────

@test "rename-session: successful rename calls tmux rename-session" {
    # Mock tmux: has-session succeeds for old-sess, fails for new-sess
    cat > "$BATS_TEST_TMPDIR/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    has-session)
        if [ "$3" = "old-sess" ]; then exit 0; else exit 1; fi ;;
    rename-session) exit 0 ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run bash -c "echo 'new-sess' | '$ACTIONS' rename-session 'old-sess'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Renamed"* ]]
}

@test "rename-session: same name is a no-op" {
    cat > "$BATS_TEST_TMPDIR/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    has-session) exit 0 ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run bash -c "echo 'same-sess' | '$ACTIONS' rename-session 'same-sess'"
    [ "$status" -eq 0 ]
}

@test "rename-session: session not found fails" {
    cat > "$BATS_TEST_TMPDIR/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    has-session) exit 1 ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run bash -c "echo '' | '$ACTIONS' rename-session 'ghost'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Session not found"* ]]
}

@test "rename-session: target session exists fails" {
    # has-session succeeds for both old and new names
    cat > "$BATS_TEST_TMPDIR/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    has-session) exit 0 ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run bash -c "echo 'existing' | '$ACTIONS' rename-session 'old-sess'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Session already exists"* ]]
}

# ─── list-sessions ────────────────────────────────────────────────────────────

@test "list-sessions: formats output correctly" {
    local now
    now=$(date +%s)
    local activity=$((now - 120))  # 2 minutes ago

    cat > "$BATS_TEST_TMPDIR/tmux" <<MOCK
#!/usr/bin/env bash
case "\$1" in
    list-sessions) echo "main|3|1|${activity}" ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run "$ACTIONS" list-sessions
    [ "$status" -eq 0 ]
    # Output should contain session name, window count, and relative time
    [[ "$output" == *"main"* ]]
    [[ "$output" == *"3w"* ]]
    [[ "$output" == *"2m"* ]]
    [[ "$output" == *"attached"* ]]
}

@test "list-sessions: unattached session omits attached label" {
    local now
    now=$(date +%s)
    local activity=$((now - 60))

    cat > "$BATS_TEST_TMPDIR/tmux" <<MOCK
#!/usr/bin/env bash
case "\$1" in
    list-sessions) echo "dev|2|0|${activity}" ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run "$ACTIONS" list-sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"2w"* ]]
    [[ "$output" != *"attached"* ]]
}

@test "list-sessions: tab-delimited format for fzf" {
    local now
    now=$(date +%s)

    cat > "$BATS_TEST_TMPDIR/tmux" <<MOCK
#!/usr/bin/env bash
case "\$1" in
    list-sessions) echo "work|1|0|${now}" ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run "$ACTIONS" list-sessions
    [ "$status" -eq 0 ]
    # First tab-delimited field should be the session name
    local first_field
    first_field=$(echo "$output" | cut -f1)
    [ "$first_field" = "work" ]
}

# ─── rename-preview ───────────────────────────────────────────────────────────

@test "rename-preview: available name shows checkmark" {
    local src="$BATS_TEST_TMPDIR/orig.txt"
    echo "content" > "$src"

    run "$ACTIONS" rename-preview "$src" "$BATS_TEST_TMPDIR/new.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"available"* ]]
}

@test "rename-preview: conflicting name shows error" {
    local src="$BATS_TEST_TMPDIR/orig.txt"
    local dst="$BATS_TEST_TMPDIR/existing.txt"
    echo "a" > "$src"
    echo "b" > "$dst"

    run "$ACTIONS" rename-preview "$src" "$dst"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "rename-preview: unchanged name shows unchanged" {
    local src="$BATS_TEST_TMPDIR/same.txt"
    echo "content" > "$src"

    run "$ACTIONS" rename-preview "$src" "$src"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unchanged"* ]]
}

@test "rename-preview: empty name shows empty message" {
    local src="$BATS_TEST_TMPDIR/file.txt"
    echo "content" > "$src"

    run "$ACTIONS" rename-preview "$src" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty"* ]]
}

@test "rename-preview: new parent dir shows will create" {
    local src="$BATS_TEST_TMPDIR/file.txt"
    echo "content" > "$src"

    run "$ACTIONS" rename-preview "$src" "$BATS_TEST_TMPDIR/newdir/file.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"available"* ]]
    [[ "$output" == *"will create"* ]]
}

# ─── rename-session-preview ──────────────────────────────────────────────────

@test "rename-session-preview: available name shows checkmark" {
    cat > "$BATS_TEST_TMPDIR/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    has-session) exit 1 ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run "$ACTIONS" rename-session-preview "old-sess" "new-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"available"* ]]
}

@test "rename-session-preview: conflicting session shows error" {
    cat > "$BATS_TEST_TMPDIR/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    has-session) exit 0 ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run "$ACTIONS" rename-session-preview "old-sess" "existing-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "rename-session-preview: unchanged name shows unchanged" {
    cat > "$BATS_TEST_TMPDIR/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    has-session) exit 0 ;;
    show-option) echo "" ;;
    *) echo "" ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run "$ACTIONS" rename-session-preview "same-sess" "same-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unchanged"* ]]
}

@test "rename-session-preview: empty name shows empty message" {
    run "$ACTIONS" rename-session-preview "some-sess" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty"* ]]
}

# ─── edit-file ────────────────────────────────────────────────────────────────

@test "edit-file: calls editor with all files" {
    local log="$BATS_TEST_TMPDIR/editor.log"
    cat > "$BATS_TEST_TMPDIR/mock-editor" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$log"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock-editor"

    run "$ACTIONS" edit-file "$BATS_TEST_TMPDIR/mock-editor" "/some/dir" "off" "a.txt" "b.txt"
    [ "$status" -eq 0 ]
    [ "$(cat "$log")" = "$(printf 'a.txt\nb.txt')" ]
}

@test "edit-file: no-op when no files given" {
    run "$ACTIONS" edit-file "/bin/false" "/some/dir" "off"
    [ "$status" -eq 0 ]
}

@test "edit-file: records history when enabled" {
    local log="$BATS_TEST_TMPDIR/editor.log"
    cat > "$BATS_TEST_TMPDIR/mock-editor" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$log"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock-editor"

    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/xdg"
    local history_file="$BATS_TEST_TMPDIR/xdg/tmux-dispatch/history"

    run "$ACTIONS" edit-file "$BATS_TEST_TMPDIR/mock-editor" "/wd" "on" "foo.txt" "bar.txt"
    [ "$status" -eq 0 ]
    [ -f "$log" ]
    [ -f "$history_file" ]
    local count
    count=$(wc -l < "$history_file")
    [ "$count" -eq 2 ]
}

@test "edit-file: skips history when disabled" {
    local log="$BATS_TEST_TMPDIR/editor.log"
    cat > "$BATS_TEST_TMPDIR/mock-editor" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$log"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock-editor"

    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/xdg"
    local history_file="$BATS_TEST_TMPDIR/xdg/tmux-dispatch/history"

    run "$ACTIONS" edit-file "$BATS_TEST_TMPDIR/mock-editor" "/wd" "off" "foo.txt"
    [ "$status" -eq 0 ]
    [ -f "$log" ]
    [ ! -f "$history_file" ]
}

# ─── edit-grep ────────────────────────────────────────────────────────────────

@test "edit-grep: calls editor with +line and file" {
    local log="$BATS_TEST_TMPDIR/editor.log"
    cat > "$BATS_TEST_TMPDIR/mock-editor" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$log"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock-editor"

    run "$ACTIONS" edit-grep "$BATS_TEST_TMPDIR/mock-editor" "/some/dir" "off" "main.rs" "42"
    [ "$status" -eq 0 ]
    [ "$(cat "$log")" = "$(printf '+42\nmain.rs')" ]
}

@test "edit-grep: defaults invalid line number to 1" {
    local log="$BATS_TEST_TMPDIR/editor.log"
    cat > "$BATS_TEST_TMPDIR/mock-editor" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$log"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock-editor"

    run "$ACTIONS" edit-grep "$BATS_TEST_TMPDIR/mock-editor" "/dir" "off" "file.rs" "notanum"
    [ "$status" -eq 0 ]
    [ "$(cat "$log")" = "$(printf '+1\nfile.rs')" ]
}

@test "edit-grep: no-op when file is empty" {
    run "$ACTIONS" edit-grep "/bin/false" "/dir" "off" "" "10"
    [ "$status" -eq 0 ]
}

@test "edit-grep: records history when enabled" {
    local log="$BATS_TEST_TMPDIR/editor.log"
    cat > "$BATS_TEST_TMPDIR/mock-editor" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$log"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock-editor"

    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/xdg"
    local history_file="$BATS_TEST_TMPDIR/xdg/tmux-dispatch/history"

    run "$ACTIONS" edit-grep "$BATS_TEST_TMPDIR/mock-editor" "/wd" "on" "file.rs" "10"
    [ "$status" -eq 0 ]
    [ -f "$history_file" ]
    local count
    count=$(wc -l < "$history_file")
    [ "$count" -eq 1 ]
}

# ─── git-toggle ──────────────────────────────────────────────────────────────

@test "git-toggle: stages an unstaged file" {
    # Mock git: diff --cached returns empty (not staged), add succeeds
    local log="$BATS_TEST_TMPDIR/git.log"
    cat > "$BATS_TEST_TMPDIR/git" <<MOCK
#!/usr/bin/env bash
if [[ "\$1" == "diff" && "\$2" == "--cached" ]]; then
    echo ""  # not staged
elif [[ "\$1" == "add" ]]; then
    echo "add \$@" > "$log"
elif [[ "\$1" == "restore" ]]; then
    echo "restore \$@" > "$log"
fi
MOCK
    chmod +x "$BATS_TEST_TMPDIR/git"

    run "$ACTIONS" git-toggle "src/main.rs"
    [ "$status" -eq 0 ]
    [[ "$(cat "$log")" == *"add"*"src/main.rs"* ]]
}

@test "git-toggle: unstages a staged file" {
    local log="$BATS_TEST_TMPDIR/git.log"
    cat > "$BATS_TEST_TMPDIR/git" <<MOCK
#!/usr/bin/env bash
if [[ "\$1" == "diff" && "\$2" == "--cached" ]]; then
    echo "src/main.rs"  # is staged
elif [[ "\$1" == "restore" ]]; then
    echo "restore \$@" > "$log"
fi
MOCK
    chmod +x "$BATS_TEST_TMPDIR/git"

    run "$ACTIONS" git-toggle "src/main.rs"
    [ "$status" -eq 0 ]
    [[ "$(cat "$log")" == *"restore"*"src/main.rs"* ]]
}

@test "git-toggle: empty file is a no-op" {
    run "$ACTIONS" git-toggle ""
    [ "$status" -eq 0 ]
}

# ─── unknown action ──────────────────────────────────────────────────────────

# ─── unknown action ──────────────────────────────────────────────────────────

@test "unknown action exits with error" {
    run "$ACTIONS" bogus-action
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown action"* ]]
}
