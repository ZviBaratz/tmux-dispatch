#!/usr/bin/env bash
# Shared test fixtures for bats tests

setup_tmux_stub() {
    export PATH="$BATS_TEST_TMPDIR:$PATH"
    printf '#!/usr/bin/env bash\necho ""\n' > "$BATS_TEST_TMPDIR/tmux"
    chmod +x "$BATS_TEST_TMPDIR/tmux"
}

teardown_tmux_stub() {
    \rm -f "$BATS_TEST_TMPDIR/tmux"
}

setup_git_repo() {
    repo="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    echo "initial" > "$repo/committed.txt"
    git -C "$repo" add committed.txt
    git -C "$repo" commit -q -m "initial"
}
