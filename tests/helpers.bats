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

teardown() {
    unset -f command tmux 2>/dev/null || true
}

# ─── get_tmux_option ────────────────────────────────────────────────────────

@test "get_tmux_option: returns value when option is set" {
    tmux() { echo "my-value"; }
    export -f tmux
    run get_tmux_option "@dispatch-editor" "default"
    [ "$output" = "my-value" ]
}

@test "get_tmux_option: returns default when option is empty" {
    tmux() { echo ""; }
    export -f tmux
    run get_tmux_option "@dispatch-editor" "fallback"
    [ "$output" = "fallback" ]
}

@test "get_tmux_option: returns default when tmux errors" {
    tmux() { return 1; }
    export -f tmux
    run get_tmux_option "@dispatch-editor" "fallback"
    [ "$output" = "fallback" ]
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

@test "tmux_version_at_least: 3.10 >= 3.2 (multi-digit minor)" {
    tmux() { echo "tmux 3.10"; }
    export -f tmux
    run tmux_version_at_least "3.2"
    [ "$status" -eq 0 ]
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

@test "detect_pane_editor: falls back to vim when nvim unavailable" {
    unset EDITOR
    command() {
        if [[ "$1" == "-v" && "$2" == "nvim" ]]; then return 1; fi
        if [[ "$1" == "-v" && "$2" == "vim" ]]; then return 0; fi
        builtin command "$@"
    }
    export -f command
    run detect_pane_editor ""
    [ "$output" = "vim" ]
}

@test "detect_pane_editor: falls back to vi when nothing available" {
    unset EDITOR
    command() {
        if [[ "$1" == "-v" && ( "$2" == "nvim" || "$2" == "vim" ) ]]; then return 1; fi
        builtin command "$@"
    }
    export -f command
    run detect_pane_editor ""
    [ "$output" = "vi" ]
}

# ─── format_relative_time ──────────────────────────────────────────────────

@test "format_relative_time: seconds (< 60)" {
    run format_relative_time 45
    [ "$output" = "45s" ]
}

@test "format_relative_time: zero seconds" {
    run format_relative_time 0
    [ "$output" = "0s" ]
}

@test "format_relative_time: minutes (60-3599)" {
    run format_relative_time 300
    [ "$output" = "5m" ]
}

@test "format_relative_time: exact minute boundary" {
    run format_relative_time 60
    [ "$output" = "1m" ]
}

@test "format_relative_time: hours (3600-86399)" {
    run format_relative_time 10800
    [ "$output" = "3h" ]
}

@test "format_relative_time: days (86400-604799)" {
    run format_relative_time 86400
    [ "$output" = "1d" ]
}

@test "format_relative_time: weeks (604800+)" {
    run format_relative_time 1209600
    [ "$output" = "2w" ]
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

@test "detect_bat: returns empty when neither available" {
    command() {
        if [[ "$1" == "-v" && ( "$2" == "bat" || "$2" == "batcat" ) ]]; then return 1; fi
        builtin command "$@"
    }
    export -f command
    run detect_bat
    [ "$output" = "" ]
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

# ─── detect_zoxide ─────────────────────────────────────────────────────────

@test "detect_zoxide: returns 'zoxide' when available" {
    command() { [[ "$1" == "-v" && "$2" == "zoxide" ]] && return 0; }
    export -f command
    run detect_zoxide
    [[ "$output" == "zoxide" ]]
}

@test "detect_zoxide: returns empty when not found" {
    command() { return 1; }
    export -f command
    run detect_zoxide
    [[ -z "$output" ]]
}

# ─── _sq_escape ───────────────────────────────────────────────────────────────

@test "_sq_escape: no-op for simple string" {
    run _sq_escape "/home/user/projects"
    [ "$output" = "/home/user/projects" ]
}

@test "_sq_escape: escapes single quote" {
    run _sq_escape "it's"
    [ "$output" = "it'\\''s" ]
}

@test "_sq_escape: escapes multiple single quotes" {
    run _sq_escape "it's a 'test'"
    [ "$output" = "it'\\''s a '\\''test'\\''" ]
}

@test "_sq_escape: preserves empty string" {
    run _sq_escape ""
    [ "$output" = "" ]
}

@test "_sq_escape: preserves double quotes and special chars" {
    run _sq_escape '/path/to/"file" $var `cmd`'
    [ "$output" = '/path/to/"file" $var `cmd`' ]
}

@test "_sq_escape: roundtrip through sh -c produces original value" {
    local original="/home/user/it's here/project"
    local escaped
    escaped=$(_sq_escape "$original")
    local result
    result=$(sh -c "printf '%s' '$escaped'")
    [ "$result" = "$original" ]
}

# ─── _resolve_path ─────────────────────────────────────────────────────────

@test "_resolve_path: resolves relative path to absolute" {
    local result
    result=$(_resolve_path "subdir/file.txt")
    [[ "$result" == "$PWD/subdir/file.txt" ]]
}

@test "_resolve_path: normalizes parent traversal" {
    local result
    result=$(_resolve_path "/home/user/project/../other/file.txt")
    [[ "$result" == "/home/user/other/file.txt" ]]
}

@test "_resolve_path: preserves absolute path without traversal" {
    local result
    result=$(_resolve_path "/tmp/some/path.txt")
    [[ "$result" == "/tmp/some/path.txt" ]]
}

@test "_resolve_path: normalizes dot components" {
    local result
    result=$(_resolve_path "/home/./user/./file.txt")
    [[ "$result" == "/home/user/file.txt" ]]
}

# ─── _parse_custom_patterns ──────────────────────────────────────────────────

@test "parse_custom_patterns: parses valid 2-field entry" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf 'jira | [A-Z][A-Z_]+-[0-9]+\n' > "$conf"
    local result
    result=$(_parse_custom_patterns "$conf")
    # type=jira, color=91 (first in palette), regex, action=copy
    [[ "$result" == *"jira"* ]]
    [[ "$result" == *"91"* ]]
    [[ "$result" == *"copy"* ]]
    [[ "$result" == *'[A-Z][A-Z_]+-[0-9]+'* ]]
}

@test "parse_custom_patterns: parses valid 3-field entry with action" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf 'k8s-pod | [a-z]+-[a-z0-9]+ | open-url https://k8s.example.com/pod/{}\n' > "$conf"
    local result
    result=$(_parse_custom_patterns "$conf")
    [[ "$result" == *"k8s-pod"* ]]
    [[ "$result" == *"open-url"* ]]
    [[ "$result" == *"https://k8s.example.com/pod/{}"* ]]
}

@test "parse_custom_patterns: skips comment lines" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf '# This is a comment\njira | [A-Z]+-[0-9]+\n' > "$conf"
    local result
    result=$(_parse_custom_patterns "$conf")
    local count
    count=$(echo "$result" | grep -c '^' || true)
    [[ "$count" -eq 1 ]]
    [[ "$result" == *"jira"* ]]
}

@test "parse_custom_patterns: skips blank lines" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf '\n\njira | [A-Z]+-[0-9]+\n\n' > "$conf"
    local result
    result=$(_parse_custom_patterns "$conf")
    local count
    count=$(echo "$result" | grep -c '^' || true)
    [[ "$count" -eq 1 ]]
}

@test "parse_custom_patterns: rejects built-in type names" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf 'url | http://[^ ]+\npath | /[^ ]+\nhash | [a-f0-9]+\nip | [0-9.]+\nuuid | [a-f0-9-]+\ndiff | [-+]+\nfile | [^ ]+\nemail | [^ ]+\nsemver | [0-9.]+\ncolor | #[0-9a-f]+\n' > "$conf"
    local result
    result=$(_parse_custom_patterns "$conf")
    [[ -z "$result" ]]
}

@test "parse_custom_patterns: rejects invalid type names" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    # Uppercase, spaces, too long
    printf 'JIRA | [A-Z]+-[0-9]+\nhas space | foo\nwaytoolongname | bar\n' > "$conf"
    local result
    result=$(_parse_custom_patterns "$conf")
    [[ -z "$result" ]]
}

@test "parse_custom_patterns: handles missing file gracefully" {
    local result
    result=$(_parse_custom_patterns "/nonexistent/patterns.conf")
    [[ -z "$result" ]]
}

@test "parse_custom_patterns: trims whitespace from fields" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf '  jira  |  [A-Z]+-[0-9]+  |  copy  \n' > "$conf"
    local result
    result=$(_parse_custom_patterns "$conf")
    # Should parse cleanly: type=jira, action=copy
    [[ "$result" == *"jira"* ]]
    [[ "$result" == *"copy"* ]]
    # Verify no leading/trailing whitespace in type field
    local ptype
    ptype=$(echo "$result" | cut -f1)
    [[ "$ptype" == "jira" ]]
}

# ─── _parse_disabled_types ───────────────────────────────────────────────────

@test "parse_disabled_types: extracts disabled type names" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf '!ip\n!uuid\n' > "$conf"
    local result
    result=$(_parse_disabled_types "$conf")
    [[ "$result" == *"ip"* ]]
    [[ "$result" == *"uuid"* ]]
    local count
    count=$(echo "$result" | wc -l)
    [[ "$count" -eq 2 ]]
}

@test "parse_disabled_types: ignores comment lines and blank lines" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf '# this is a comment\n\n!ip\n# another comment\n\n' > "$conf"
    local result
    result=$(_parse_disabled_types "$conf")
    [[ "$result" == "ip" ]]
}

@test "parse_disabled_types: handles leading whitespace before !" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf '  !ip\n\t!uuid\n' > "$conf"
    local result
    result=$(_parse_disabled_types "$conf")
    [[ "$result" == *"ip"* ]]
    [[ "$result" == *"uuid"* ]]
}

@test "parse_disabled_types: handles missing file gracefully" {
    local result
    result=$(_parse_disabled_types "/nonexistent/patterns.conf")
    [[ -z "$result" ]]
}

@test "parse_disabled_types: rejects invalid type names after !" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf '!UPPER\n!valid-name\n!123start\n!ok\n' > "$conf"
    local result
    result=$(_parse_disabled_types "$conf")
    # UPPER rejected (uppercase), 123start rejected (starts with digit)
    # valid-name and ok should pass
    [[ "$result" == *"valid-name"* ]]
    [[ "$result" == *"ok"* ]]
    [[ "$result" != *"UPPER"* ]]
    [[ "$result" != *"123start"* ]]
}

@test "parse_custom_patterns: assigns cycling colors" {
    local conf="$BATS_TEST_TMPDIR/patterns.conf"
    printf 'aaa | a+\nbbb | b+\nccc | c+\nddd | d+\neee | e+\nfff | f+\nggg | g+\n' > "$conf"
    local result
    result=$(_parse_custom_patterns "$conf")
    # First 6 should be 91-96, 7th wraps to 91
    local colors
    colors=$(echo "$result" | cut -f2)
    local -a color_arr
    mapfile -t color_arr <<< "$colors"
    [[ "${color_arr[0]}" == "91" ]]
    [[ "${color_arr[1]}" == "92" ]]
    [[ "${color_arr[2]}" == "93" ]]
    [[ "${color_arr[3]}" == "94" ]]
    [[ "${color_arr[4]}" == "95" ]]
    [[ "${color_arr[5]}" == "96" ]]
    [[ "${color_arr[6]}" == "91" ]]
}
