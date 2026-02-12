#!/usr/bin/env bats
# =============================================================================
# Unit tests for scripts/helpers.sh
# =============================================================================
# Run with: bats tests/helpers.bats
# Mocks external commands (tmux, command) to test pure logic.
# =============================================================================

setup() {
    # Source helpers.sh in each test
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
    source "$SCRIPT_DIR/helpers.sh"
}

# ─── tmux_version_at_least ──────────────────────────────────────────────────

@test "tmux_version_at_least: 3.2 >= 3.2 (exact match)" {
    tmux() { echo "tmux 3.2"; }
    export -f tmux
    run tmux_version_at_least "3.2"
    [ "$status" -eq 0 ]
}

@test "tmux_version_at_least: 3.3 >= 3.2 (newer)" {
    tmux() { echo "tmux 3.3"; }
    export -f tmux
    run tmux_version_at_least "3.2"
    [ "$status" -eq 0 ]
}

@test "tmux_version_at_least: 3.1 < 3.2 (older)" {
    tmux() { echo "tmux 3.1"; }
    export -f tmux
    run tmux_version_at_least "3.2"
    [ "$status" -ne 0 ]
}

@test "tmux_version_at_least: 3.2a >= 3.2 (patch version)" {
    tmux() { echo "tmux 3.2a"; }
    export -f tmux
    run tmux_version_at_least "3.2"
    [ "$status" -eq 0 ]
}

@test "tmux_version_at_least: master returns false (safe fallback)" {
    tmux() { echo "tmux master"; }
    export -f tmux
    run tmux_version_at_least "3.2"
    [ "$status" -ne 0 ]
}

@test "tmux_version_at_least: next-3.5 extracts 3.5 (dev build passes)" {
    tmux() { echo "tmux next-3.5"; }
    export -f tmux
    run tmux_version_at_least "3.2"
    [ "$status" -eq 0 ]
}

@test "tmux_version_at_least: empty version returns false" {
    tmux() { echo ""; }
    export -f tmux
    run tmux_version_at_least "3.2"
    [ "$status" -ne 0 ]
}

# ─── detect_popup_editor ────────────────────────────────────────────────────

@test "detect_popup_editor: returns configured value when set" {
    run detect_popup_editor "helix"
    [ "$output" = "helix" ]
}

@test "detect_popup_editor: falls back to nvim when available" {
    command() {
        if [[ "$1" == "-v" && "$2" == "nvim" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_popup_editor ""
    [ "$output" = "nvim" ]
}

@test "detect_popup_editor: falls back to vim when nvim unavailable" {
    command() {
        if [[ "$1" == "-v" && "$2" == "nvim" ]]; then return 1; fi
        if [[ "$1" == "-v" && "$2" == "vim" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_popup_editor ""
    [ "$output" = "vim" ]
}

@test "detect_popup_editor: falls back to vi when neither vim nor nvim available" {
    command() {
        if [[ "$1" == "-v" && ( "$2" == "nvim" || "$2" == "vim" ) ]]; then return 1; fi
        builtin command "$@"
    }
    export -f command
    run detect_popup_editor ""
    [ "$output" = "vi" ]
}

# ─── detect_pane_editor ─────────────────────────────────────────────────────

@test "detect_pane_editor: returns configured value when set" {
    run detect_pane_editor "code"
    [ "$output" = "code" ]
}

@test "detect_pane_editor: uses EDITOR env var" {
    EDITOR="emacs"
    run detect_pane_editor ""
    [ "$output" = "emacs" ]
}

@test "detect_pane_editor: falls back to nvim without EDITOR" {
    unset EDITOR
    command() {
        if [[ "$1" == "-v" && "$2" == "nvim" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_pane_editor ""
    [ "$output" = "nvim" ]
}

# ─── detect_fd ──────────────────────────────────────────────────────────────

@test "detect_fd: finds fd" {
    command() {
        if [[ "$1" == "-v" && "$2" == "fd" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_fd
    [ "$output" = "fd" ]
}

@test "detect_fd: finds fdfind (Debian rename)" {
    command() {
        if [[ "$1" == "-v" && "$2" == "fd" ]]; then return 1; fi
        if [[ "$1" == "-v" && "$2" == "fdfind" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_fd
    [ "$output" = "fdfind" ]
}

@test "detect_fd: returns empty when neither available" {
    command() {
        if [[ "$1" == "-v" && ( "$2" == "fd" || "$2" == "fdfind" ) ]]; then return 1; fi
        builtin command "$@"
    }
    export -f command
    run detect_fd
    [ "$output" = "" ]
}

# ─── detect_bat ─────────────────────────────────────────────────────────────

@test "detect_bat: finds bat" {
    command() {
        if [[ "$1" == "-v" && "$2" == "bat" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_bat
    [ "$output" = "bat" ]
}

@test "detect_bat: finds batcat (Debian rename)" {
    command() {
        if [[ "$1" == "-v" && "$2" == "bat" ]]; then return 1; fi
        if [[ "$1" == "-v" && "$2" == "batcat" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_bat
    [ "$output" = "batcat" ]
}

# ─── detect_rg ──────────────────────────────────────────────────────────────

@test "detect_rg: finds rg" {
    command() {
        if [[ "$1" == "-v" && "$2" == "rg" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_rg
    [ "$output" = "rg" ]
}

@test "detect_rg: returns empty when rg unavailable" {
    command() {
        if [[ "$1" == "-v" && "$2" == "rg" ]]; then return 1; fi
        builtin command "$@"
    }
    export -f command
    run detect_rg
    [ "$output" = "" ]
}
