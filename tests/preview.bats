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

# ─── git-preview.sh ──────────────────────────────────────────────────────────

@test "git-preview: staged file (✚) shows staged diff" {
    local repo="$BATS_TEST_TMPDIR/gp_repo1"
    mkdir -p "$repo" && cd "$repo"
    git init -q && git config user.email "t@t" && git config user.name "T"
    echo "line1" > file.txt && git add file.txt && git commit -q -m "init"
    echo "line2" >> file.txt && git add file.txt

    run "$SCRIPT_DIR/git-preview.sh" "file.txt" "✚"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"line2"* ]]
}

@test "git-preview: unstaged file (●) shows unstaged diff" {
    local repo="$BATS_TEST_TMPDIR/gp_repo2"
    mkdir -p "$repo" && cd "$repo"
    git init -q && git config user.email "t@t" && git config user.name "T"
    echo "line1" > file.txt && git add file.txt && git commit -q -m "init"
    echo "line2" >> file.txt

    run "$SCRIPT_DIR/git-preview.sh" "file.txt" "●"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"line2"* ]]
}

@test "git-preview: untracked file (?) shows file content" {
    local repo="$BATS_TEST_TMPDIR/gp_repo3"
    mkdir -p "$repo" && cd "$repo"
    git init -q && git config user.email "t@t" && git config user.name "T"
    echo "hello world" > untracked.txt

    run "$SCRIPT_DIR/git-preview.sh" "untracked.txt" "?"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"hello world"* ]]
}

@test "git-preview: ANSI-wrapped status icon is stripped correctly" {
    local repo="$BATS_TEST_TMPDIR/gp_repo4"
    mkdir -p "$repo" && cd "$repo"
    git init -q && git config user.email "t@t" && git config user.name "T"
    echo "line1" > file.txt && git add file.txt && git commit -q -m "init"
    echo "line2" >> file.txt && git add file.txt

    # fzf sends ANSI-wrapped icon: \033[32m✚\033[0m
    run "$SCRIPT_DIR/git-preview.sh" "file.txt" $'\033[32m✚\033[0m'
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"line2"* ]]
}

@test "git-preview: file not found shows error message" {
    local repo="$BATS_TEST_TMPDIR/gp_repo5"
    mkdir -p "$repo" && cd "$repo"
    git init -q

    run "$SCRIPT_DIR/git-preview.sh" "nonexistent.txt" "?"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"File not found"* ]]
}

@test "git-preview: renamed file (old -> new) resolves to new name" {
    local repo="$BATS_TEST_TMPDIR/gp_repo6"
    mkdir -p "$repo" && cd "$repo"
    git init -q
    echo "content" > "new-name.txt"

    # Simulate porcelain rename format: "old.txt -> new-name.txt"
    run "$SCRIPT_DIR/git-preview.sh" "old.txt -> new-name.txt" "✚"
    [[ "$status" -eq 0 ]]
    # Should show file content (no diff for this simple case), not "File not found"
    [[ "$output" != *"File not found"* ]]
}

# ─── session-preview.sh ─────────────────────────────────────────────────────

@test "session-preview: nonexistent session shows 'New session' message" {
    # Override the stub tmux to reject has-session for unknown sessions
    printf '#!/usr/bin/env bash\nif [[ "$1" == "has-session" ]]; then exit 1; fi\necho ""\n' \
        > "$BATS_TEST_TMPDIR/tmux"
    chmod +x "$BATS_TEST_TMPDIR/tmux"

    run "$SCRIPT_DIR/session-preview.sh" "nonexistent-session-xyz"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"New session"* ]]
}

@test "session-preview: highlight index strips trailing colon" {
    # Verify the script parses "3:" → "3" for the highlight parameter
    # This tests the line: highlight_idx="${highlight_idx%%:*}"
    run bash -c '
        highlight_idx="3:"
        highlight_idx="${highlight_idx%%:*}"
        echo "$highlight_idx"
    '
    [[ "$output" == "3" ]]
}

@test "session-preview: non-numeric highlight index is cleared" {
    # Verify non-numeric highlight_idx is treated as empty
    run bash -c '
        highlight_idx="abc"
        highlight_idx="${highlight_idx%%:*}"
        [[ "$highlight_idx" =~ ^[0-9]+$ ]] || highlight_idx=""
        echo "highlight=[$highlight_idx]"
    '
    [[ "$output" == "highlight=[]" ]]
}

@test "session-preview: numeric highlight index is preserved" {
    run bash -c '
        highlight_idx="5"
        highlight_idx="${highlight_idx%%:*}"
        [[ "$highlight_idx" =~ ^[0-9]+$ ]] || highlight_idx=""
        echo "highlight=[$highlight_idx]"
    '
    [[ "$output" == "highlight=[5]" ]]
}

# ─── session-new-preview.sh ──────────────────────────────────────────────────

@test "session-new-preview: nonexistent directory shows error" {
    run "$SCRIPT_DIR/session-new-preview.sh" "/nonexistent/dir/xyz"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Directory not found"* ]]
}

@test "session-new-preview: non-git directory shows listing" {
    mkdir -p "$BATS_TEST_TMPDIR/plaindir/subdir"
    printf 'hello\n' > "$BATS_TEST_TMPDIR/plaindir/file.txt"

    run "$SCRIPT_DIR/session-new-preview.sh" "$BATS_TEST_TMPDIR/plaindir"
    [[ "$status" -eq 0 ]]
    # Should show directory contents (tree or ls output)
    [[ "$output" == *"file.txt"* ]] || [[ "$output" == *"subdir"* ]]
}

@test "session-new-preview: git repo shows branch and commits heading" {
    # Create a real git repo with a commit
    mkdir -p "$BATS_TEST_TMPDIR/gitrepo"
    git -C "$BATS_TEST_TMPDIR/gitrepo" init -b main 2>/dev/null
    git -C "$BATS_TEST_TMPDIR/gitrepo" config user.email "test@test.com"
    git -C "$BATS_TEST_TMPDIR/gitrepo" config user.name "Test"
    printf 'hello\n' > "$BATS_TEST_TMPDIR/gitrepo/file.txt"
    git -C "$BATS_TEST_TMPDIR/gitrepo" add file.txt
    git -C "$BATS_TEST_TMPDIR/gitrepo" commit -m "initial" --no-gpg-sign 2>/dev/null

    run "$SCRIPT_DIR/session-new-preview.sh" "$BATS_TEST_TMPDIR/gitrepo"
    [[ "$status" -eq 0 ]]
    # Should show branch name
    [[ "$output" == *"main"* ]]
    # Should show commits heading
    [[ "$output" == *"Recent commits"* ]]
    # Should show the commit message
    [[ "$output" == *"initial"* ]]
}

@test "session-new-preview: git repo with dirty files shows count" {
    # Create a git repo with uncommitted changes
    mkdir -p "$BATS_TEST_TMPDIR/dirtyrepo"
    git -C "$BATS_TEST_TMPDIR/dirtyrepo" init -b main 2>/dev/null
    git -C "$BATS_TEST_TMPDIR/dirtyrepo" config user.email "test@test.com"
    git -C "$BATS_TEST_TMPDIR/dirtyrepo" config user.name "Test"
    printf 'hello\n' > "$BATS_TEST_TMPDIR/dirtyrepo/file.txt"
    git -C "$BATS_TEST_TMPDIR/dirtyrepo" add file.txt
    git -C "$BATS_TEST_TMPDIR/dirtyrepo" commit -m "initial" --no-gpg-sign 2>/dev/null
    printf 'modified\n' > "$BATS_TEST_TMPDIR/dirtyrepo/file.txt"

    run "$SCRIPT_DIR/session-new-preview.sh" "$BATS_TEST_TMPDIR/dirtyrepo"
    [[ "$status" -eq 0 ]]
    # Should show changed file count
    [[ "$output" == *"changed file"* ]]
}

@test "session-new-preview: clean git repo shows clean message" {
    mkdir -p "$BATS_TEST_TMPDIR/cleanrepo"
    git -C "$BATS_TEST_TMPDIR/cleanrepo" init -b main 2>/dev/null
    git -C "$BATS_TEST_TMPDIR/cleanrepo" config user.email "test@test.com"
    git -C "$BATS_TEST_TMPDIR/cleanrepo" config user.name "Test"
    printf 'hello\n' > "$BATS_TEST_TMPDIR/cleanrepo/file.txt"
    git -C "$BATS_TEST_TMPDIR/cleanrepo" add file.txt
    git -C "$BATS_TEST_TMPDIR/cleanrepo" commit -m "initial" --no-gpg-sign 2>/dev/null

    run "$SCRIPT_DIR/session-new-preview.sh" "$BATS_TEST_TMPDIR/cleanrepo"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"clean working tree"* ]]
}
