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

@test "session sanitization: no tr -c in dispatch.sh (UTF-8 safe)" {
    # tr -c corrupts multi-byte UTF-8; sed handles it correctly
    local tr_usage
    tr_usage=$(grep -n 'tr -c' "$SCRIPT_DIR/dispatch.sh" || true)
    [ -z "$tr_usage" ]
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

# ─── File annotation awk (bookmarks + git) ──────────────────────────────

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

# Combined annotation awk (mirrors dispatch.sh annotate_awk).
# Variables: bfile (bookmark file), pwd (working dir), do_git (0|1), prefix (git prefix).
# Output: indicator\tfilename — indicator is bookmark star + git icon.
_annotate_awk='BEGIN {
    if (bfile != "") {
        while ((getline line < bfile) > 0) {
            n = split(line, a, "\t")
            if (n >= 2 && a[1] == pwd) bm[a[2]] = 1
        }
        close(bfile)
    }
    if (do_git) {
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
            if (x == "?" && y == "?")       gs[file] = "\033[33m?\033[0m"
            else if (x != " " && y != " ")  gs[file] = "\033[35m\342\234\271\033[0m"
            else if (x != " ")              gs[file] = "\033[32m\342\234\232\033[0m"
            else                            gs[file] = "\033[31m\342\227\217\033[0m"
        }
        close(cmd)
    }
}
{
    f = $0; sub(/^\.\//, "", f)
    if (f in bm) ind = "\033[33m\342\230\205\033[0m"
    else ind = " "
    if (do_git) {
        if (f in gs) ind = ind gs[f]
        else ind = ind " "
    }
    printf "%s\t%s\n", ind, $0
}'

# Helper: run annotate awk with git enabled and no bookmarks
_run_annotate_git() {
    awk -v bfile="" -v pwd="" -v do_git=1 -v prefix="${1:-}" "$_annotate_awk"
}

@test "annotate: modified file gets git icon, clean file gets space prefix" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    local result
    result=$(printf '%s\n' "clean.txt" "modified.txt" | _run_annotate_git)
    # Clean file: space + space (git placeholder) + tab + filename
    local clean_line
    clean_line=$(grep "clean.txt" <<< "$result")
    local clean_ind
    clean_ind=$(cut -f1 <<< "$clean_line" | sed 's/\x1b\[[0-9;]*m//g')
    [ "$clean_ind" = "  " ]
    # Modified file: indicator column has non-space content (space + icon)
    local mod_line
    mod_line=$(grep "modified.txt" <<< "$result")
    local mod_ind
    mod_ind=$(cut -f1 <<< "$mod_line" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$mod_ind" =~ [^\ ] ]]
}

@test "annotate: untracked file gets yellow ? icon" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    local result
    result=$(printf '%s\n' "untracked.txt" | _run_annotate_git)
    # Strip ANSI to check the git icon (second char in indicator)
    local ind
    ind=$(cut -f1 <<< "$result" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$ind" == *"?"* ]]
}

@test "annotate: staged file gets green icon" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    git -C "$repo" add modified.txt
    local result
    result=$(printf '%s\n' "modified.txt" | _run_annotate_git)
    local ind
    ind=$(cut -f1 <<< "$result" | sed 's/\x1b\[[0-9;]*m//g')
    # ✚ is the staged icon
    [[ "$ind" == *"✚"* ]]
}

@test "annotate: prefix strips repo-relative path for subdirectory" {
    local repo
    repo=$(_setup_git_repo)
    mkdir -p "$repo/src"
    echo "code" > "$repo/src/main.rs"
    git -C "$repo" add src/main.rs
    git -C "$repo" commit -q -m "add src"
    echo "changed" > "$repo/src/main.rs"
    cd "$repo"
    local result
    result=$(printf '%s\n' "main.rs" | _run_annotate_git "src/")
    local ind
    ind=$(cut -f1 <<< "$result" | sed 's/\x1b\[[0-9;]*m//g')
    # ● is the modified icon
    [[ "$ind" == *"●"* ]]
}

@test "annotate: non-git directory uses space placeholders" {
    cd "$BATS_TEST_TMPDIR"
    local result
    result=$(printf '%s\n' "a.txt" "b.txt" | _run_annotate_git)
    # No git status → space + space + tab + filename
    local ind_a ind_b
    ind_a=$(sed -n '1p' <<< "$result" | cut -f1 | sed 's/\x1b\[[0-9;]*m//g')
    ind_b=$(sed -n '2p' <<< "$result" | cut -f1 | sed 's/\x1b\[[0-9;]*m//g')
    [ "$ind_a" = "  " ]
    [ "$ind_b" = "  " ]
}

@test "annotate: ./prefix files match git status" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    local result
    result=$(printf '%s\n' "./modified.txt" | _run_annotate_git)
    local ind
    ind=$(cut -f1 <<< "$result" | sed 's/\x1b\[[0-9;]*m//g')
    # Should have a git icon (not just spaces)
    [[ "$ind" =~ [^\ ] ]]
}

@test "annotate: bookmarked file gets ★ indicator" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    local bf="$BATS_TEST_TMPDIR/test-bookmarks"
    printf '%s\t%s\n' "$BATS_TEST_TMPDIR/proj" "marked.txt" > "$bf"
    local result
    result=$(printf '%s\n' "marked.txt" "plain.txt" | \
        awk -v bfile="$bf" -v pwd="$BATS_TEST_TMPDIR/proj" -v do_git=0 -v prefix="" "$_annotate_awk")
    local marked_ind plain_ind
    marked_ind=$(grep "marked.txt" <<< "$result" | cut -f1 | sed 's/\x1b\[[0-9;]*m//g')
    plain_ind=$(grep "plain.txt" <<< "$result" | cut -f1 | sed 's/\x1b\[[0-9;]*m//g')
    [ "$marked_ind" = "★" ]
    [ "$plain_ind" = " " ]
}

@test "annotate: bookmark + git combines both indicators" {
    local repo
    repo=$(_setup_git_repo)
    cd "$repo"
    local bf="$BATS_TEST_TMPDIR/test-bookmarks"
    printf '%s\t%s\n' "$repo" "modified.txt" > "$bf"
    local result
    result=$(printf '%s\n' "modified.txt" "clean.txt" | \
        awk -v bfile="$bf" -v pwd="$repo" -v do_git=1 -v prefix="" "$_annotate_awk")
    local mod_ind clean_ind
    mod_ind=$(grep "modified.txt" <<< "$result" | cut -f1 | sed 's/\x1b\[[0-9;]*m//g')
    clean_ind=$(grep "clean.txt" <<< "$result" | cut -f1 | sed 's/\x1b\[[0-9;]*m//g')
    # modified.txt: ★ + git icon (●)
    [[ "$mod_ind" == *"★"* ]]
    [[ "$mod_ind" == *"●"* ]]
    # clean.txt: space + space (no bookmark, no git status)
    [ "$clean_ind" = "  " ]
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

# ─── Rename path validation ─────────────────────────────────────────────────

@test "rename: rejects path traversal outside working directory" {
    local workdir="$BATS_TEST_TMPDIR/project"
    mkdir -p "$workdir"

    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        cd "'"$workdir"'"
        new_name="../../etc/evil.txt"
        resolved=$(_resolve_path "$new_name")
        resolved_pwd=$(_resolve_path "$PWD")
        if [[ "$resolved" != "$resolved_pwd"/* ]]; then
            echo "BLOCKED"; exit 1
        fi
        echo "ALLOWED"
    '
    [[ "$output" == "BLOCKED" ]]
}

@test "rename: allows subdirectory rename within working directory" {
    local workdir="$BATS_TEST_TMPDIR/project"
    mkdir -p "$workdir"

    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        cd "'"$workdir"'"
        new_name="subdir/renamed.txt"
        resolved=$(_resolve_path "$new_name")
        resolved_pwd=$(_resolve_path "$PWD")
        if [[ "$resolved" != "$resolved_pwd"/* ]]; then
            echo "BLOCKED"; exit 1
        fi
        echo "ALLOWED"
    '
    [[ "$output" == "ALLOWED" ]]
}

@test "rename: realpath failure does not fall back to raw path" {
    # dispatch.sh should use _resolve_path, not raw realpath -m with fallback
    local fallback
    fallback=$(grep -n 'resolved="\$new_name"' "$SCRIPT_DIR/dispatch.sh" || true)
    [ -z "$fallback" ]
}

@test "rename: rejects absolute path outside working directory" {
    local workdir="$BATS_TEST_TMPDIR/project"
    mkdir -p "$workdir"

    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        cd "'"$workdir"'"
        new_name="/tmp/elsewhere.txt"
        resolved=$(_resolve_path "$new_name")
        resolved_pwd=$(_resolve_path "$PWD")
        if [[ "$resolved" != "$resolved_pwd"/* ]]; then
            echo "BLOCKED"; exit 1
        fi
        echo "ALLOWED"
    '
    [[ "$output" == "BLOCKED" ]]
}

# ─── Window index validation ─────────────────────────────────────────────────

@test "windows: numeric index passes validation" {
    run bash -c '[[ "3" =~ ^[0-9]+$ ]] && echo "VALID" || echo "INVALID"'
    [[ "$output" == "VALID" ]]
}

@test "windows: non-numeric index fails validation" {
    run bash -c '[[ "abc" =~ ^[0-9]+$ ]] && echo "VALID" || echo "INVALID"'
    [[ "$output" == "INVALID" ]]
}

@test "windows: empty index fails validation" {
    run bash -c '[[ "" =~ ^[0-9]+$ ]] && echo "VALID" || echo "INVALID"'
    [[ "$output" == "INVALID" ]]
}

# ─── Security validation ────────────────────────────────────────────────────

@test "pane ID: valid format %N passes validation" {
    run bash -c '[[ "%42" =~ ^%[0-9]+$ ]] && echo VALID || echo INVALID'
    [[ "$output" == "VALID" ]]
}

@test "pane ID: empty string clears to fallback" {
    run bash -c '[[ "" =~ ^%[0-9]+$ ]] && echo VALID || echo INVALID'
    [[ "$output" == "INVALID" ]]
}

@test "pane ID: injection attempt rejected" {
    run bash -c '[[ "%42;rm -rf /" =~ ^%[0-9]+$ ]] && echo VALID || echo INVALID'
    [[ "$output" == "INVALID" ]]
}

@test "session name: special characters replaced with dashes" {
    run bash -c '
        name="my.project:v2 (test)"
        name=$(printf "%s" "$name" | tr -c "a-zA-Z0-9_-" "-")
        name="${name#-}"; name="${name%-}"
        echo "$name"
    '
    [[ "$output" =~ ^[a-zA-Z0-9_-]+$ ]]
}

# ─── Transform uses {q} not $FZF_QUERY ───────────────────────────────────

@test "change_transform: mode switch uses {q} not \$FZF_QUERY" {
    # Verify the source uses {q} for safe query passing in become(),
    # not the raw $FZF_QUERY which breaks on special characters like quotes.
    # Check that --query={q} appears in become() calls
    run bash -c '
        count=$(grep -c "query={q}" "'"$SCRIPT_DIR"'/dispatch.sh")
        if [[ "$count" -ge 4 ]]; then
            echo "PASS"
        else
            echo "FAIL: expected >=4 occurrences of query={q}, found $count"
        fi
    '
    [[ "$output" == "PASS" ]]
}

@test "change_transform: actual dispatch.sh source uses {q} in become" {
    # Grep the actual source file for the transform pattern
    run bash -c '
        grep -c "query={q}" "'"$SCRIPT_DIR"'/dispatch.sh"
    '
    [ "$status" -eq 0 ]
    # Should find at least 4 occurrences (grep, sessions, git, dirs)
    [[ "${lines[0]}" -ge 4 ]]
}

@test "change_transform: actual dispatch.sh source has no \$FZF_QUERY in become" {
    run bash -c '
        grep -c "FZF_QUERY" "'"$SCRIPT_DIR"'/dispatch.sh" || echo "0"
    '
    # Should find 0 occurrences of FZF_QUERY
    [[ "${lines[0]}" == "0" ]]
}

# ─── Session result parsing (mapfile) ────────────────────────────────────

@test "handle_session_result: mapfile parses query/key/selected correctly" {
    # Verify the mapfile-based parsing pattern extracts all 3 fields
    # from fzf --print-query --expect output (query, key, selected\ttab-data)
    run bash -c '
        result="myquery
ctrl-k
session-name	extra-info"
        mapfile -t result_lines <<< "$result"
        query="${result_lines[0]}"
        key="${result_lines[1]:-}"
        selected="${result_lines[2]:-}"
        selected="${selected%%	*}"
        echo "query=$query"
        echo "key=$key"
        echo "selected=$selected"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "query=myquery" ]
    [ "${lines[1]}" = "key=ctrl-k" ]
    [ "${lines[2]}" = "selected=session-name" ]
}

@test "handle_session_result: mapfile handles missing selected line" {
    # Verify graceful handling when fzf returns only query + key (no selection)
    run bash -c '
        result="myquery
"
        mapfile -t result_lines <<< "$result"
        query="${result_lines[0]}"
        key="${result_lines[1]:-}"
        selected="${result_lines[2]:-}"
        selected="${selected%%	*}"
        echo "query=$query"
        echo "key=$key"
        echo "selected=$selected"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "query=myquery" ]
    [ "${lines[1]}" = "key=" ]
    [ "${lines[2]}" = "selected=" ]
}

# ─── Keybinding hint UX ────────────────────────────────────────────────────

@test "hints: sub-modes use bottom border-label for keybinding hints" {
    # grep, sessions, git, dirs, windows, rename, rename-session all use
    # --border-label-pos with bottom positioning
    run bash -c '
        count=$(grep -c "border-label-pos.*bottom" "'"$SCRIPT_DIR"'/dispatch.sh")
        echo "$count"
    '
    [ "$status" -eq 0 ]
    # 7 modes: grep, sessions, git, dirs, windows, rename, rename-session
    [[ "${lines[0]}" -ge 7 ]]
}

@test "hints: no ctrl- notation in any border-label hint" {
    # All hints should use ^ notation, not ctrl-
    run bash -c '
        grep -- "--border-label " "'"$SCRIPT_DIR"'/dispatch.sh" | grep -c "ctrl-" || echo "0"
    '
    [[ "${lines[0]}" == "0" ]]
}

@test "hints: sub-mode prompts include mode name" {
    # Each sub-mode prompt should contain its mode name for identification
    run bash -c '
        src="'"$SCRIPT_DIR"'/dispatch.sh"
        ok=0
        grep -q "prompt .grep" "$src" && ok=$((ok+1))
        grep -q "prompt .sessions" "$src" && ok=$((ok+1))
        grep -q "prompt .git" "$src" && ok=$((ok+1))
        grep -q "prompt .dirs" "$src" && ok=$((ok+1))
        grep -q "prompt .rename" "$src" && ok=$((ok+1))
        echo "$ok"
    '
    # At least 5 sub-modes have named prompts
    [[ "${lines[0]}" -ge 5 ]]
}

# ─── fzf placeholder quoting ─────────────────────────────────────────────

@test "fzf bind strings: all modes quote fzf placeholders" {
    source "$SCRIPT_DIR/helpers.sh"
    # Scan all --bind and --preview lines in dispatch.sh for unquoted fzf field refs
    # fzf fields: {1}, {2..}, {+2..}, {+1} etc. Should always be inside single quotes in bind/preview strings.
    # Exclude: --preview-window (no substitution), change:transform (uses {q} not field refs),
    # and lines that only use {q} (query, not field reference)
    local unquoted
    unquoted=$(grep -nE '\-\-(bind|preview) ' "$SCRIPT_DIR/dispatch.sh" \
        | grep -v 'preview-window' \
        | grep -v 'preview-label' \
        | grep -v 'change:transform' \
        | grep -v 'backward-eof' \
        | grep -v 'ctrl-f:transform' \
        | grep -v 'ctrl-h:' \
        | grep -v 'start:' \
        | grep -v 'focus:' \
        | grep -v 'down:' \
        | grep -v 'up:' \
        | grep -P '(?<!['"'"'])\{[+]?[0-9]' \
        || true)
    [ -z "$unquoted" ]
}

@test "fzf bind strings: files mode quotes fzf placeholders" {
    source "$SCRIPT_DIR/helpers.sh"
    # Extract bind lines from run_files_mode
    local body
    body=$(sed -n '/^run_files_mode/,/^}/p' "$SCRIPT_DIR/dispatch.sh")
    # Check --bind lines for unquoted $fzf_file / $fzf_files (not wrapped in 'quotes')
    # These variables expand to {2..} and {+2..} — fzf placeholders that need quoting
    # for filenames with spaces. We check the source uses '$fzf_file' not bare $fzf_file.
    local unquoted_in_bind
    unquoted_in_bind=$(echo "$body" | grep '\-\-bind' | grep -v 'preview' | grep -v "hidden" | grep -P "[^']\\\$fzf_file" | grep -Pv "'\\\$fzf_file'" || true)
    [ -z "$unquoted_in_bind" ]
}
