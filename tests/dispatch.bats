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

# ─── Rename error handling ────────────────────────────────────────────────

@test "rename: mkdir failure shows error and re-execs" {
    # Simulate: mkdir -p fails → _dispatch_error called, then exec back to files
    run bash -c '
        source "'"$SCRIPT_DIR"'/helpers.sh"
        mkdir() { return 1; }
        _dispatch_error() { echo "ERROR: $1"; }

        dir="/nonexistent/impossible/path"
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || { _dispatch_error "Cannot create directory: $dir"; exit 1; }
        fi
    '
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot create directory"* ]]
}

@test "rename: mv failure shows error and re-execs" {
    # Simulate: command mv fails → _dispatch_error called
    run bash -c '
        source "'"$SCRIPT_DIR"'/helpers.sh"
        _dispatch_error() { echo "ERROR: $1"; }

        FILE="old.txt"
        new_name="new.txt"
        # Override mv to fail
        mv() { return 1; }
        command mv "$FILE" "$new_name" || { _dispatch_error "Rename failed: $FILE → $new_name"; exit 1; }
    '
    [ "$status" -eq 1 ]
    [[ "$output" == *"Rename failed"* ]]
}

# ─── Session sanitization feedback ───────────────────────────────────────

@test "session: sanitized name differs from input shows feedback" {
    # Simulate handle_session_result when sanitized != selected
    run bash -c '
        messages=()
        tmux() {
            if [[ "$1" == "display-message" ]]; then
                messages+=("$2")
                echo "$2"
            elif [[ "$1" == "switch-client" ]]; then
                return 1
            elif [[ "$1" == "new-session" ]]; then
                return 0
            fi
        }
        export -f tmux

        selected="my.project:v2"
        sanitized=$(printf "%s" "$selected" | sed "s/[^a-zA-Z0-9_-]/-/g")
        sanitized="${sanitized#-}"
        sanitized="${sanitized%-}"
        [[ -z "$sanitized" ]] && exit 0
        tmux new-session -d -s "$sanitized" && tmux switch-client -t "=$sanitized"
        if [[ "$sanitized" != "$selected" ]]; then
            tmux display-message "Created session: $sanitized (sanitized from: $selected)"
        fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Created session:"* ]]
    [[ "$output" == *"sanitized from:"* ]]
}

@test "session: matching name does not show sanitization feedback" {
    run bash -c '
        output_msgs=""
        tmux() {
            if [[ "$1" == "display-message" ]]; then
                output_msgs+="$2"
            elif [[ "$1" == "switch-client" ]]; then
                return 1
            elif [[ "$1" == "new-session" ]]; then
                return 0
            fi
        }
        export -f tmux

        selected="my-project"
        sanitized=$(printf "%s" "$selected" | sed "s/[^a-zA-Z0-9_-]/-/g")
        sanitized="${sanitized#-}"
        sanitized="${sanitized%-}"
        tmux new-session -d -s "$sanitized" && tmux switch-client -t "=$sanitized"
        if [[ "$sanitized" != "$selected" ]]; then
            tmux display-message "Created session: $sanitized (sanitized from: $selected)"
        fi
        echo "$output_msgs"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"sanitized from:"* ]]
}

# ─── Cached tool detection ────────────────────────────────────────────────

@test "cached tool: reads fd from tmux server var" {
    run bash -c '
        tmux() {
            if [[ "$1" == "show" && "$2" == "-sv" && "$3" == "@_dispatch-fd" ]]; then
                echo "fdfind"
            else
                echo ""
            fi
        }
        export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        result=$(_dispatch_read_cached "@_dispatch-fd" detect_fd)
        echo "$result"
    '
    [ "$output" = "fdfind" ]
}

@test "cached tool: falls back to detection when cache miss" {
    run bash -c '
        tmux() { return 1; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        detect_fd() { echo "fd-fallback"; }
        result=$(_dispatch_read_cached "@_dispatch-fd" detect_fd)
        echo "$result"
    '
    [ "$output" = "fd-fallback" ]
}

@test "cached tool: falls back when tmux show returns empty" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        detect_bat() { echo "bat-detected"; }
        result=$(_dispatch_read_cached "@_dispatch-bat" detect_bat)
        echo "$result"
    '
    [ "$output" = "bat-detected" ]
}

@test "batched options: parses tmux show-options grep output" {
    run bash -c '
        POPUP_EDITOR="" PANE_EDITOR="" FD_EXTRA_ARGS="" RG_EXTRA_ARGS=""
        HISTORY_ENABLED="on" FILE_TYPES="" GIT_INDICATORS="on" DISPATCH_THEME="default"
        input="@dispatch-fd-args --hidden --no-ignore
@dispatch-history off
@dispatch-theme none"
        while IFS= read -r line; do
            key="${line%% *}"
            val="${line#* }"
            val="${val#\"}" ; val="${val%\"}"
            case "$key" in
                @dispatch-fd-args)         FD_EXTRA_ARGS="$val" ;;
                @dispatch-history)         HISTORY_ENABLED="$val" ;;
                @dispatch-theme)           DISPATCH_THEME="$val" ;;
            esac
        done <<< "$input"
        echo "fd=$FD_EXTRA_ARGS"
        echo "history=$HISTORY_ENABLED"
        echo "theme=$DISPATCH_THEME"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "fd=--hidden --no-ignore" ]
    [ "${lines[1]}" = "history=off" ]
    [ "${lines[2]}" = "theme=none" ]
}

@test "batched options: defaults preserved when no matching options" {
    run bash -c '
        POPUP_EDITOR="" PANE_EDITOR="" FD_EXTRA_ARGS="" RG_EXTRA_ARGS=""
        HISTORY_ENABLED="on" FILE_TYPES="" GIT_INDICATORS="on" DISPATCH_THEME="default"
        input=""
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            key="${line%% *}"
            val="${line#* }"
            val="${val#\"}" ; val="${val%\"}"
            case "$key" in
                @dispatch-history)         HISTORY_ENABLED="$val" ;;
                @dispatch-theme)           DISPATCH_THEME="$val" ;;
            esac
        done <<< "$input"
        echo "history=$HISTORY_ENABLED"
        echo "theme=$DISPATCH_THEME"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "history=on" ]
    [ "${lines[1]}" = "theme=default" ]
}

@test "batched options: strips single-quoted empty values from tmux" {
    # tmux show-options -g outputs '' for empty string values
    local script
    script=$(cat << 'BASH'
FILE_TYPES="default-val"
input="@dispatch-file-types ''"
while IFS= read -r line; do
    key="${line%% *}"
    val="${line#* }"
    val="${val#\"}" ; val="${val%\"}"
    val="${val#\'}" ; val="${val%\'}"
    case "$key" in
        @dispatch-file-types) FILE_TYPES="$val" ;;
    esac
done <<< "$input"
echo "types=[$FILE_TYPES]"
BASH
    )
    run bash -c "$script"
    [ "${lines[0]}" = "types=[]" ]
}

# ─── Scrollback mode ─────────────────────────────────────────────────────

@test "scrollback mode strips leading $ from query" {
    run bash -c '
        QUERY="\$ls -la output"
        QUERY="${QUERY#\$}"
        echo "$QUERY"
    '
    [ "$output" = "ls -la output" ]
}

@test "scrollback mode strips leading & from query" {
    run bash -c '
        QUERY="&search term"
        QUERY="${QUERY#&}"
        echo "$QUERY"
    '
    [ "$output" = "search term" ]
}

@test "dispatch: scrollback is a valid mode" {
    run bash -c '
        MODE="scrollback"
        case "$MODE" in
            files|grep|git|dirs|sessions|session-new|windows|rename|rename-session|scrollback|commands|marks|resume) echo "valid" ;;
            *) echo "invalid" ;;
        esac
    '
    [ "$output" = "valid" ]
}

@test "scrollback dedup: removes duplicate lines preserving order" {
    run bash -c '
        input="line1
line2
line1
line3
line2
line3"
        echo "$input" | awk "!seen[\$0]++"
    '
    expected="line1
line2
line3"
    [ "$output" = "$expected" ]
}

# ─── Empty state detection ────────────────────────────────────────────────

@test "git empty state: empty git status triggers error" {
    local repo="$BATS_TEST_TMPDIR/clean-repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    echo "file" > "$repo/file.txt"
    git -C "$repo" add . && git -C "$repo" commit -q -m "init"

    run bash -c '
        cd "'"$repo"'"
        output=$(git status --porcelain 2>/dev/null)
        if [[ -z "$output" ]]; then
            echo "EMPTY"
        else
            echo "HAS_OUTPUT"
        fi
    '
    [ "$status" -eq 0 ]
    [ "$output" = "EMPTY" ]
}

@test "git empty state: dirty git status has output" {
    local repo="$BATS_TEST_TMPDIR/dirty-repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    echo "file" > "$repo/file.txt"
    git -C "$repo" add . && git -C "$repo" commit -q -m "init"
    echo "changed" > "$repo/file.txt"

    run bash -c '
        cd "'"$repo"'"
        output=$(git status --porcelain 2>/dev/null)
        if [[ -z "$output" ]]; then
            echo "EMPTY"
        else
            echo "HAS_OUTPUT"
        fi
    '
    [ "$status" -eq 0 ]
    [ "$output" = "HAS_OUTPUT" ]
}

@test "dirs empty state: empty zoxide output triggers error with zoxide message" {
    run bash -c '
        ZOXIDE_CMD="zoxide"
        dir_output=""
        if [[ -z "$dir_output" ]]; then
            if [[ -z "$ZOXIDE_CMD" ]]; then
                echo "no directories found — install zoxide for frecency: brew install zoxide"
            else
                echo "no directories in zoxide — cd around first to build history"
            fi
        fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"no directories in zoxide"* ]]
}

@test "dirs empty state: empty output without zoxide suggests installation" {
    run bash -c '
        ZOXIDE_CMD=""
        dir_output=""
        if [[ -z "$dir_output" ]]; then
            if [[ -z "$ZOXIDE_CMD" ]]; then
                echo "no directories found — install zoxide for frecency: brew install zoxide"
            else
                echo "no directories in zoxide — cd around first to build history"
            fi
        fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"install zoxide"* ]]
}

@test "dirs empty state: non-empty output skips error" {
    run bash -c '
        dir_output="/home/user/projects"
        if [[ -z "$dir_output" ]]; then
            echo "ERROR"
        else
            echo "OK"
        fi
    '
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

# ─── Commands mode ───────────────────────────────────────────────────────

@test "commands mode strips leading : from query" {
    run bash -c '
        QUERY=":deploy"
        QUERY="${QUERY#:}"
        echo "$QUERY"
    '
    [ "$output" = "deploy" ]
}

@test "dispatch: commands is a valid mode" {
    run bash -c '
        MODE="commands"
        case "$MODE" in
            files|grep|git|dirs|sessions|session-new|windows|rename|rename-session|scrollback|commands|marks|resume) echo "valid" ;;
            *) echo "invalid" ;;
        esac
    '
    [ "$output" = "valid" ]
}

# ─── Commands config parsing ────────────────────────────────────────────

@test "commands config: parses label|command format" {
    local conf="$BATS_TEST_TMPDIR/commands.conf"
    printf '# comment\nDeploy | ssh deploy.sh\n\nRestart | systemctl restart\n' > "$conf"
    run bash -c '
        grep -v "^#" "'"$conf"'" | grep -v "^[[:space:]]*$" | while IFS="|" read -r label _rest; do
            label="${label## }"; label="${label%% }"
            echo "$label"
        done
    '
    [ "${lines[0]}" = "Deploy" ]
    [ "${lines[1]}" = "Restart" ]
}

@test "commands config: handles missing file gracefully" {
    run bash -c '
        conf="/nonexistent/commands.conf"
        if [[ ! -f "$conf" ]]; then
            echo "no-config"
        fi
    '
    [ "$output" = "no-config" ]
}

@test "commands config: identifies tmux commands by prefix" {
    run bash -c '
        cmd="tmux: split-window -h"
        if [[ "$cmd" == "tmux: "* ]]; then
            echo "tmux-cmd:${cmd#tmux: }"
        else
            echo "shell-cmd:$cmd"
        fi
    '
    [ "$output" = "tmux-cmd:split-window -h" ]
}

@test "commands config: shell commands have no prefix" {
    run bash -c '
        cmd="ssh deploy.sh"
        if [[ "$cmd" == "tmux: "* ]]; then
            echo "tmux-cmd:${cmd#tmux: }"
        else
            echo "shell-cmd:$cmd"
        fi
    '
    [ "$output" = "shell-cmd:ssh deploy.sh" ]
}

# ─── Scrollback/Commands prefix triggers ─────────────────────────────────

@test "scrollback: \$ prefix triggers mode switch in transform pattern" {
    run bash -c '
        query="\$search term"
        if [[ "$query" == "\$"* ]]; then
            echo "scrollback"
        else
            echo "other"
        fi
    '
    [ "$output" = "scrollback" ]
}

@test "extract: & prefix triggers mode switch to scrollback tokens view" {
    run bash -c '
        query="&search term"
        if [[ "$query" == "&"* ]]; then
            echo "extract"
        else
            echo "other"
        fi
    '
    [ "$output" = "extract" ]
}

@test "extract: & prefix present in change_transform in dispatch.sh" {
    grep -q "\\[\\[ {q} == '&'\\*" "$SCRIPT_DIR/dispatch.sh"
}

@test "extract: & prefix passes --view=tokens in dispatch.sh" {
    grep -q "\-\-view=tokens.*\-\-query={q}" "$SCRIPT_DIR/dispatch.sh"
}

@test "commands: : prefix triggers mode switch in transform pattern" {
    run bash -c '
        query=":deploy"
        if [[ "$query" == ":"* ]]; then
            echo "commands"
        else
            echo "other"
        fi
    '
    [ "$output" = "commands" ]
}

# ─── Default commands.conf creation ───────────────────────────────────────

@test "commands: _create_default_commands creates file at specified path" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        eval "$(sed -n "/_create_default_commands()/,/^}/p" "'"$SCRIPT_DIR"'/dispatch.sh")"
        conf="'"$BATS_TEST_TMPDIR"'/subdir/commands.conf"
        _create_default_commands "$conf"
        [ -f "$conf" ] && echo "exists" || echo "missing"
    '
    [ "$output" = "exists" ]
}

@test "commands: _create_default_commands includes starter recipes" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        eval "$(sed -n "/_create_default_commands()/,/^}/p" "'"$SCRIPT_DIR"'/dispatch.sh")"
        conf="'"$BATS_TEST_TMPDIR"'/commands.conf"
        _create_default_commands "$conf"
        grep -c "Reload tmux config" "$conf"
    '
    [ "$output" = "1" ]
}

@test "commands: _create_default_commands includes comment lines" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        eval "$(sed -n "/_create_default_commands()/,/^}/p" "'"$SCRIPT_DIR"'/dispatch.sh")"
        conf="'"$BATS_TEST_TMPDIR"'/commands.conf"
        _create_default_commands "$conf"
        grep -c "^#" "$conf"
    '
    # At least 5 comment lines (header comments + section headers)
    [ "$output" -ge 5 ]
}

@test "commands: _create_default_commands uses Description | command format" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        eval "$(sed -n "/_create_default_commands()/,/^}/p" "'"$SCRIPT_DIR"'/dispatch.sh")"
        conf="'"$BATS_TEST_TMPDIR"'/commands.conf"
        _create_default_commands "$conf"
        # Count lines matching "text | text" pattern (non-comment, non-empty)
        grep -v "^#" "$conf" | grep -v "^[[:space:]]*$" | grep -c " | "
    '
    # All non-comment non-empty lines should have the pipe format
    [ "$output" -ge 9 ]
}

@test "commands: _create_default_commands creates parent directories" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        eval "$(sed -n "/_create_default_commands()/,/^}/p" "'"$SCRIPT_DIR"'/dispatch.sh")"
        conf="'"$BATS_TEST_TMPDIR"'/deep/nested/dir/commands.conf"
        _create_default_commands "$conf"
        [ -d "'"$BATS_TEST_TMPDIR"'/deep/nested/dir" ] && echo "dir_exists" || echo "no_dir"
    '
    [ "$output" = "dir_exists" ]
}

# ─── Tool-missing hints ──────────────────────────────────────────────────

@test "tool hints: both missing shows fd and bat tips joined by separator" {
    run bash -c '
        FD_CMD="" BAT_CMD=""
        header=""
        [[ -z "$FD_CMD" ]] && header="tip: install fd for faster search with .gitignore support"
        [[ -z "$BAT_CMD" ]] && header="${header:+$header  ·  }tip: install bat for syntax-highlighted preview"
        echo "$header"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"install fd"* ]]
    [[ "$output" == *"install bat"* ]]
    [[ "$output" == *"  ·  "* ]]
}

@test "tool hints: only bat missing shows bat tip only" {
    run bash -c '
        FD_CMD="fd" BAT_CMD=""
        header=""
        [[ -z "$FD_CMD" ]] && header="tip: install fd for faster search with .gitignore support"
        [[ -z "$BAT_CMD" ]] && header="${header:+$header  ·  }tip: install bat for syntax-highlighted preview"
        echo "$header"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"install fd"* ]]
    [[ "$output" == *"install bat"* ]]
}

@test "tool hints: only fd missing shows fd tip only" {
    run bash -c '
        FD_CMD="" BAT_CMD="bat"
        header=""
        [[ -z "$FD_CMD" ]] && header="tip: install fd for faster search with .gitignore support"
        [[ -z "$BAT_CMD" ]] && header="${header:+$header  ·  }tip: install bat for syntax-highlighted preview"
        echo "$header"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"install fd"* ]]
    [[ "$output" != *"install bat"* ]]
}

@test "tool hints: both present produces empty header" {
    run bash -c '
        FD_CMD="fd" BAT_CMD="bat"
        header=""
        [[ -z "$FD_CMD" ]] && header="tip: install fd for faster search with .gitignore support"
        [[ -z "$BAT_CMD" ]] && header="${header:+$header  ·  }tip: install bat for syntax-highlighted preview"
        echo "$header"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ─── Doctor script ────────────────────────────────────────────────────────

@test "doctor.sh: exists and is executable" {
    [ -x "$SCRIPT_DIR/doctor.sh" ]
}

@test "doctor.sh: reports bash version" {
    run bash "$SCRIPT_DIR/doctor.sh" 2>&1
    [[ "$output" == *"bash"* ]]
}

@test "doctor.sh: reports fzf status" {
    run bash "$SCRIPT_DIR/doctor.sh" 2>&1
    [[ "$output" == *"fzf"* ]]
}

@test "doctor.sh: reports tmux status" {
    run bash "$SCRIPT_DIR/doctor.sh" 2>&1
    [[ "$output" == *"tmux"* ]]
}

@test "doctor.sh: shows summary line" {
    run bash "$SCRIPT_DIR/doctor.sh" 2>&1
    [[ "$output" == *"Summary:"* ]]
}

# ─── Help overlay completeness ────────────────────────────────────────────

@test "help: all 11 HELP_* variables are defined in dispatch.sh" {
    # Verify every mode has a corresponding help overlay string
    local expected=(
        HELP_FILES
        HELP_GREP
        HELP_GIT
        HELP_SESSIONS
        HELP_DIRS
        HELP_WINDOWS
        HELP_SESSION_NEW
        HELP_SCROLLBACK
        HELP_COMMANDS
        HELP_MARKS
        HELP_EXTRACT
    )
    local missing=()
    local var
    for var in "${expected[@]}"; do
        if ! grep -q "^${var}=" "$SCRIPT_DIR/dispatch.sh"; then
            missing+=("$var")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing HELP variables: ${missing[*]}"
        return 1
    fi
}

@test "help: all 11 SQ_HELP_* escape variables are defined in dispatch.sh" {
    # Verify every help string is also pre-escaped for fzf bind embedding
    local expected=(
        SQ_HELP_FILES
        SQ_HELP_GREP
        SQ_HELP_GIT
        SQ_HELP_SESSIONS
        SQ_HELP_DIRS
        SQ_HELP_WINDOWS
        SQ_HELP_SESSION_NEW
        SQ_HELP_SCROLLBACK
        SQ_HELP_COMMANDS
        SQ_HELP_MARKS
        SQ_HELP_EXTRACT
    )
    local missing=()
    local var
    for var in "${expected[@]}"; do
        if ! grep -q "^${var}=" "$SCRIPT_DIR/dispatch.sh"; then
            missing+=("$var")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing SQ_HELP variables: ${missing[*]}"
        return 1
    fi
}

@test "help: every mode with ? binding has matching HELP variable" {
    # Extract mode names from ?:preview bindings, verify each has a HELP_* definition
    local help_binds
    help_binds=$(grep -oP "SQ_HELP_\w+" "$SCRIPT_DIR/dispatch.sh" | sort -u)
    local var
    for var in $help_binds; do
        # SQ_HELP_FOO → HELP_FOO should exist as a definition
        local base="${var#SQ_}"
        if ! grep -q "^${base}=" "$SCRIPT_DIR/dispatch.sh"; then
            echo "Used $var in bind but $base is not defined"
            return 1
        fi
    done
}

# ─── HOME root-switching ─────────────────────────────────────────────────

@test "change_transform: ~ prefix triggers HOME root-switch" {
    run bash -c '
        query="~"
        if [[ "$query" == "~"* ]]; then
            echo "home"
        else
            echo "no-match"
        fi
    '
    [ "$output" = "home" ]
}

@test "change_transform: ~ prefix present in dispatch.sh source" {
    run bash -c '
        grep -c "cd ~ &&\|cd.*HOME" "'"$SCRIPT_DIR"'/dispatch.sh" || echo "0"
    '
    [[ "${lines[0]}" -ge 1 ]]
}

# ─── Resume mode ─────────────────────────────────────────────────────────

@test "resume: --mode=resume falls back to files when no stored state" {
    run bash -c '
        tmux() { echo ""; }; export -f tmux
        source "'"$SCRIPT_DIR"'/helpers.sh"
        MODE="resume"
        if [[ "$MODE" == "resume" ]]; then
            MODE=$(tmux show -sv @_dispatch-last-mode 2>/dev/null) || MODE=""
            [[ -z "$MODE" ]] && MODE="files"
        fi
        echo "$MODE"
    '
    [ "$output" = "files" ]
}

@test "resume: mode validation accepts resume" {
    run bash -c '
        MODE="resume"
        case "$MODE" in
            files|grep|git|dirs|sessions|session-new|windows|rename|rename-session|scrollback|commands|marks|resume) echo "valid" ;;
            *) echo "invalid" ;;
        esac
    '
    [ "$output" = "valid" ]
}

@test "resume: mode validation accepts marks" {
    run bash -c '
        MODE="marks"
        case "$MODE" in
            files|grep|git|dirs|sessions|session-new|windows|rename|rename-session|scrollback|commands|marks|resume) echo "valid" ;;
            *) echo "invalid" ;;
        esac
    '
    [ "$output" = "valid" ]
}

# ─── Marks mode ──────────────────────────────────────────────────────────

@test "marks: dispatch.sh contains run_marks_mode function" {
    run bash -c '
        grep -c "run_marks_mode()" "'"$SCRIPT_DIR"'/dispatch.sh"
    '
    [[ "${lines[0]}" -ge 1 ]]
}

@test "marks: ctrl-g binding present in files mode" {
    run bash -c '
        grep -c "ctrl-g.*marks\|ctrl-g.*become.*marks" "'"$SCRIPT_DIR"'/dispatch.sh"
    '
    [[ "${lines[0]}" -ge 1 ]]
}

@test "marks: HELP_MARKS defined in dispatch.sh" {
    run bash -c '
        grep -c "HELP_MARKS" "'"$SCRIPT_DIR"'/dispatch.sh"
    '
    [[ "${lines[0]}" -ge 2 ]]
}

@test "marks: dispatch case includes marks mode" {
    run bash -c '
        grep -c "marks).*run_marks_mode" "'"$SCRIPT_DIR"'/dispatch.sh"
    '
    [[ "${lines[0]}" -ge 1 ]]
}

# ─── Extract mode (tokens) ────────────────────────────────────────────────

@test "extract: URL regex matches https URLs" {
    local result
    result=$(echo "Visit https://example.com/path?q=1#frag for info" \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+')
    [ "$result" = "https://example.com/path?q=1#frag" ]
}

@test "extract: URL regex matches http and ftp URLs" {
    local result
    result=$(printf "http://localhost:8080/api\nftp://files.example.com/pub\n" \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+')
    local -a lines
    mapfile -t lines <<< "$result"
    [ "${lines[0]}" = "http://localhost:8080/api" ]
    [ "${lines[1]}" = "ftp://files.example.com/pub" ]
}

@test "extract: trailing punctuation stripped from URLs" {
    run bash -c '
        printf "https://example.com.\nhttps://x.com,\nhttps://y.com)\nhttps://z.com;\nhttps://w.com:\n" \
            | sed "s/[.,;:!?)'"'"'\"'\'']*$//"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "https://example.com" ]
    [ "${lines[1]}" = "https://x.com" ]
    [ "${lines[2]}" = "https://y.com" ]
    [ "${lines[3]}" = "https://z.com" ]
    [ "${lines[4]}" = "https://w.com" ]
}

@test "extract: deduplication preserves first occurrence only" {
    run bash -c '
        printf "https://a.com\nhttps://b.com\nhttps://a.com\nhttps://c.com\nhttps://b.com\n" \
            | awk "!seen[\$0]++"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "https://a.com" ]
    [ "${lines[1]}" = "https://b.com" ]
    [ "${lines[2]}" = "https://c.com" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "extract: most-recent-first ordering via awk reverse" {
    local result
    result=$(printf "line1 https://first.com\nline2\nline3 https://last.com\n" \
        | awk '{lines[NR]=$0} END {for(i=NR;i>=1;i--) print lines[i]}' \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+')
    local -a result_lines
    mapfile -t result_lines <<< "$result"
    [ "${result_lines[0]}" = "https://last.com" ]
    [ "${result_lines[1]}" = "https://first.com" ]
}

@test "extract: full URL extraction pipeline works end-to-end" {
    local input="old line with https://old.com
some text
check https://example.com/path for info.
visit https://example.com/path again
more at https://new.com/page?q=1,"
    local result
    result=$(echo "$input" \
        | awk '{lines[NR]=$0} END {for(i=NR;i>=1;i--) print lines[i]}' \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+' \
        | sed "s/[.,;:!?)'\"\`]*$//" \
        | awk '!seen[$0]++')
    local -a result_lines
    mapfile -t result_lines <<< "$result"
    [ "${result_lines[0]}" = "https://new.com/page?q=1" ]
    [ "${result_lines[1]}" = "https://example.com/path" ]
    [ "${result_lines[2]}" = "https://old.com" ]
    [ "${#result_lines[@]}" -eq 3 ]
}

@test "extract: file path regex matches path:line and path:line:col" {
    local result
    result=$(printf 'error in src/main.rs:42\nwarning at lib/utils.js:10:5\n' \
        | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]{1,10}:[0-9]+(:[0-9]+)?' \
        | grep -v '^//')
    local -a lines
    mapfile -t lines <<< "$result"
    [ "${lines[0]}" = "src/main.rs:42" ]
    [ "${lines[1]}" = "lib/utils.js:10:5" ]
}

@test "extract: file path regex excludes URL fragments (//...)" {
    local result
    result=$(printf 'https://example.com:8080/path\n' \
        | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]{1,10}:[0-9]+(:[0-9]+)?' \
        | grep -v '^//' || true)
    # The example.com:8080 match should pass through, but //example... should not
    # since the URL itself has https:// which starts with //
    [[ -z "$result" || "$result" != "//"* ]]
}

@test "extract: git hash regex matches 7-40 hex chars" {
    local result
    # SHA-1 is exactly 40 hex chars; test with 7-char short and 40-char full
    result=$(printf 'commit abc1234\nfull hash abc1234567890abcdef1234567890abcdef1234\n' \
        | grep -oEw '[0-9a-f]{7,40}' \
        | grep -v '^[0-9]*$')
    local -a lines
    mapfile -t lines <<< "$result"
    [ "${lines[0]}" = "abc1234" ]
    [ "${lines[1]}" = "abc1234567890abcdef1234567890abcdef1234" ]
}

@test "extract: git hash regex excludes all-digit strings" {
    local result
    result=$(printf '1234567\n1234567890\nabc1234\n' \
        | grep -oEw '[0-9a-f]{7,40}' \
        | grep -v '^[0-9]*$')
    # Only abc1234 should survive (all-digit strings filtered out)
    [ "$result" = "abc1234" ]
}

@test "extract: IPv4 regex matches addresses with optional port" {
    local result
    result=$(printf 'server at 192.168.1.1\nlistening on 10.0.0.1:8080\n' \
        | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]{1,5})?')
    local -a lines
    mapfile -t lines <<< "$result"
    [ "${lines[0]}" = "192.168.1.1" ]
    [ "${lines[1]}" = "10.0.0.1:8080" ]
}

@test "extract: Ctrl+T toggle binding present in scrollback mode" {
    local src="$SCRIPT_DIR/dispatch.sh"
    run bash -c 'grep -c "ctrl-t:transform" "'"$src"'"'
    [[ "${lines[0]}" -ge 1 ]]
}

@test "extract: --view=tokens parameter supported" {
    run bash -c '
        SCROLLBACK_VIEW=""
        arg="--view=tokens"
        case "$arg" in
            --view=*) SCROLLBACK_VIEW="${arg#--view=}" ;;
        esac
        echo "$SCROLLBACK_VIEW"
    '
    [ "$output" = "tokens" ]
}

@test "extract: HELP_EXTRACT defined in dispatch.sh" {
    local src="$SCRIPT_DIR/dispatch.sh"
    run bash -c 'grep -c "^HELP_EXTRACT=" "'"$src"'"'
    [[ "${lines[0]}" -ge 1 ]]
}

@test "extract: _extract_tokens function defined in dispatch.sh" {
    local src="$SCRIPT_DIR/dispatch.sh"
    run bash -c 'grep -c "_extract_tokens()" "'"$src"'"'
    [[ "${lines[0]}" -ge 1 ]]
}

@test "extract: full pipeline deduplicates across types" {
    # Same value appearing as different types should both appear (different type prefix)
    # Same type+value should be deduped
    run bash -c '
        printf "url\thttps://a.com\nurl\thttps://b.com\nurl\thttps://a.com\n" \
            | awk "!seen[\$0]++"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "url	https://a.com" ]
    [ "${lines[1]}" = "url	https://b.com" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "extract: ANSI escapes stripped before extraction" {
    # _extract_tokens strips ANSI before regex extraction
    local input=$'\033[32mhttps://example.com\033[0m and \033[31m192.168.1.1\033[0m'
    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$input" > "$tmp"
    # Simulate the ANSI strip step
    local result
    result=$(sed 's/\x1b\[[0-9;]*m//g' "$tmp" \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+')
    command rm -f "$tmp"
    [ "$result" = "https://example.com" ]
}

@test "extract: ANSI color codes stripped from type field in result handler" {
    # Simulate what handle_scrollback_result does: extract type and strip ANSI
    local item=$'\033[36murl\033[0m\thttps://example.com'
    local ttype="${item%%	*}"
    ttype=$(printf '%s' "$ttype" | sed 's/\x1b\[[0-9;]*m//g')
    [ "$ttype" = "url" ]
}

@test "extract: colored type labels present in _extract_tokens output format" {
    # Verify awk output includes ANSI color codes
    local src="$SCRIPT_DIR/dispatch.sh"
    run bash -c 'grep -c "\\\\033\[3[0-9]m" "'"$src"'"'
    # Should have at least 7 colored type labels (url, path, hash, ip, uuid, diff, + file later)
    [[ "${lines[0]}" -ge 6 ]]
}

@test "extract: URL with balanced parens preserved (Wikipedia)" {
    local result
    result=$(echo "see https://en.wikipedia.org/wiki/Bash_(Unix_shell) for info" \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+' \
        | while IFS= read -r url; do
            opens="${url//[^(]/}"; closes="${url//[^)]/}"
            while [[ ${#closes} -gt ${#opens} && "$url" == *')' ]]; do
                url="${url%)}"; closes="${closes%)}"
            done
            while [[ "$url" =~ [.,\;:!\?\"\'~\`]$ ]]; do url="${url%?}"; done
            printf '%s\n' "$url"
        done)
    [ "$result" = "https://en.wikipedia.org/wiki/Bash_(Unix_shell)" ]
}

@test "extract: URL in markdown link strips trailing paren" {
    local result
    result=$(echo "[link](https://example.com/page)" \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+' \
        | while IFS= read -r url; do
            opens="${url//[^(]/}"; closes="${url//[^)]/}"
            while [[ ${#closes} -gt ${#opens} && "$url" == *')' ]]; do
                url="${url%)}"; closes="${closes%)}"
            done
            while [[ "$url" =~ [.,\;:!\?\"\'~\`]$ ]]; do url="${url%?}"; done
            printf '%s\n' "$url"
        done)
    [ "$result" = "https://example.com/page" ]
}

@test "extract: bare URL without parens unchanged" {
    local result
    result=$(echo "visit https://example.com/path?q=1&r=2 today" \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+' \
        | while IFS= read -r url; do
            opens="${url//[^(]/}"; closes="${url//[^)]/}"
            while [[ ${#closes} -gt ${#opens} && "$url" == *')' ]]; do
                url="${url%)}"; closes="${closes%)}"
            done
            while [[ "$url" =~ [.,\;:!\?\"\'~\`]$ ]]; do url="${url%?}"; done
            printf '%s\n' "$url"
        done)
    [ "$result" = "https://example.com/path?q=1&r=2" ]
}

@test "extract: URL strips trailing punctuation" {
    local result
    result=$(echo "check https://example.com/page, and more" \
        | grep -oE '(https?|ftp)://[^][:space:]"<>{}|\\^`[]+' \
        | while IFS= read -r url; do
            opens="${url//[^(]/}"; closes="${url//[^)]/}"
            while [[ ${#closes} -gt ${#opens} && "$url" == *')' ]]; do
                url="${url%)}"; closes="${closes%)}"
            done
            while [[ "$url" =~ [.,\;:!\?\"\'~\`]$ ]]; do url="${url%?}"; done
            printf '%s\n' "$url"
        done)
    [ "$result" = "https://example.com/page" ]
}

@test "extract: diff path regex matches --- a/ format" {
    local result
    result=$(echo "--- a/src/main.rs" \
        | grep -oE '[-+]{3} [ab]/[^ ]+' | sed 's/^[-+]* [ab]\///')
    [ "$result" = "src/main.rs" ]
}

@test "extract: diff path regex matches +++ b/ format" {
    local result
    result=$(echo "+++ b/lib/utils.js" \
        | grep -oE '[-+]{3} [ab]/[^ ]+' | sed 's/^[-+]* [ab]\///')
    [ "$result" = "lib/utils.js" ]
}

@test "extract: diff path strips trailing quotes from scrollback strings" {
    local result
    result=$(echo '+++ b/src/main.rs"'"'" \
        | grep -oE '[-+]{3} [ab]/[^ ]+' | sed 's/^[-+]* [ab]\///' | tr -d "\"'")
    [ "$result" = "src/main.rs" ]
}

@test "extract: diff path strips trailing double quote only" {
    local result
    result=$(echo '+++ b/lib/utils.js"' \
        | grep -oE '[-+]{3} [ab]/[^ ]+' | sed 's/^[-+]* [ab]\///' | tr -d "\"'")
    [ "$result" = "lib/utils.js" ]
}

@test "extract: diff path regex rejects non-diff lines" {
    local result
    result=$(echo "-- not a diff" \
        | grep -oE '[-+]{3} [ab]/[^ ]+' || true)
    [ -z "$result" ]
}

@test "extract: UUID regex matches standard format" {
    local result
    result=$(echo "request id: 550e8400-e29b-41d4-a716-446655440000 done" \
        | grep -oEi '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    [ "$result" = "550e8400-e29b-41d4-a716-446655440000" ]
}

@test "extract: UUID regex rejects short/malformed UUIDs" {
    local result
    result=$(echo "not-a-uuid: 550e8400-e29b-41d4-a716 or abc-def" \
        | grep -oEi '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || true)
    [ -z "$result" ]
}

@test "extract: UUID regex is case-insensitive" {
    local result
    result=$(echo "ID: 550E8400-E29B-41D4-A716-446655440000" \
        | grep -oEi '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    [ "$result" = "550E8400-E29B-41D4-A716-446655440000" ]
}

@test "extract: path with line number validated against existing file" {
    # Create a real file to validate against
    touch "$BATS_TEST_TMPDIR/main.rs"
    local result
    result=$(cd "$BATS_TEST_TMPDIR" && echo "error at main.rs:42" \
        | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]{1,10}:[0-9]+(:[0-9]+)?' \
        | grep -v '^//' \
        | while IFS= read -r match; do
            [[ -f "${match%%:*}" ]] && printf 'path\t%s\n' "$match"
        done)
    [ "$result" = "path	main.rs:42" ]
}

@test "extract: path with line number rejected for non-existent file" {
    local result
    result=$(cd "$BATS_TEST_TMPDIR" && echo "error at nonexistent.xyz:42" \
        | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]{1,10}:[0-9]+(:[0-9]+)?' \
        | grep -v '^//' \
        | while IFS= read -r match; do
            [[ -f "${match%%:*}" ]] && printf 'path\t%s\n' "$match"
        done || true)
    [ -z "$result" ]
}

@test "extract: bare file path detected when file exists" {
    touch "$BATS_TEST_TMPDIR/utils.js"
    local result
    result=$(cd "$BATS_TEST_TMPDIR" && echo "see utils.js for details" \
        | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]{1,10}' \
        | grep -v '^//' | sort -u \
        | while IFS= read -r match; do
            [[ -f "$match" ]] && printf 'file\t%s\n' "$match"
        done)
    [ "$result" = "file	utils.js" ]
}

@test "extract: bare file path not emitted when file does not exist" {
    local result
    result=$(cd "$BATS_TEST_TMPDIR" && echo "see phantom.xyz for details" \
        | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]{1,10}' \
        | grep -v '^//' | sort -u \
        | while IFS= read -r match; do
            [[ -f "$match" ]] && printf 'file\t%s\n' "$match"
        done || true)
    [ -z "$result" ]
}

@test "extract: ctrl-f filter binding present in scrollback mode" {
    local src="$SCRIPT_DIR/dispatch.sh"
    run bash -c 'grep -c "ctrl-f:transform" "'"$src"'"'
    [[ "${lines[0]}" -ge 1 ]]
}

@test "extract: filter cycle order is all→url→path→hash→ip→uuid→diff→file→all" {
    # Test the case statement cycle logic used in the filter transform
    run bash -c '
        for cur in all url path hash ip uuid diff file; do
            case "$cur" in
                all) next=url;; url) next=path;; path) next=hash;; hash) next=ip;;
                ip) next=uuid;; uuid) next=diff;; diff) next=file;; file) next=all;;
                *) next=all;;
            esac
            printf "%s→%s " "$cur" "$next"
        done
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"all→url"* ]]
    [[ "$output" == *"url→path"* ]]
    [[ "$output" == *"path→hash"* ]]
    [[ "$output" == *"hash→ip"* ]]
    [[ "$output" == *"ip→uuid"* ]]
    [[ "$output" == *"uuid→diff"* ]]
    [[ "$output" == *"diff→file"* ]]
    [[ "$output" == *"file→all"* ]]
}

@test "extract: filter file created and initialized to 'all'" {
    local src="$SCRIPT_DIR/dispatch.sh"
    # Verify filter file creation in run_scrollback_mode
    run bash -c 'grep "printf.*all.*filter_file" "'"$src"'"'
    [ "$status" -eq 0 ]
}

@test "extract: ctrl-t toggle resets filter to all" {
    local src="$SCRIPT_DIR/dispatch.sh"
    # Both branches of the toggle_cmd should reset the filter
    run bash -c 'grep -c "printf all.*filter_file" "'"$src"'"'
    [[ "${lines[0]}" -ge 2 ]]
}

@test "extract: grep ESC-anchor filters by type in first field only" {
    # Simulate the grep filter approach: mTYPE\033 matches only type labels
    local tokens_file
    tokens_file=$(mktemp)
    printf "\033[36murl\033[0m\thttps://example.com\n" > "$tokens_file"
    printf "\033[33mpath\033[0m\tsrc/main.rs:42\n" >> "$tokens_file"
    printf "\033[35mhash\033[0m\tabc1234\n" >> "$tokens_file"

    # Filter for url — should match only the url line
    local esc=$'\033'
    local result
    result=$(grep "murl${esc}" "$tokens_file" | wc -l)
    [ "$result" -eq 1 ]

    # Filter for path — should match only the path line
    result=$(grep "mpath${esc}" "$tokens_file" | wc -l)
    [ "$result" -eq 1 ]

    # Filter for hash — should match only the hash line
    result=$(grep "mhash${esc}" "$tokens_file" | wc -l)
    [ "$result" -eq 1 ]

    # "url" in the URL value should NOT be matched by murl\033
    # (the ESC byte after "url" only appears in the type label, not the value)
    printf "\033[35mhash\033[0m\thttps://myurl.com/abc1234\n" >> "$tokens_file"
    result=$(grep "murl${esc}" "$tokens_file" | wc -l)
    [ "$result" -eq 1 ]  # Still only the actual url-typed line

    command rm -f "$tokens_file"
}

@test "extract: ^f filter hint in tokens border label" {
    local src="$SCRIPT_DIR/dispatch.sh"
    run bash -c 'grep "tokens_label_inner" "'"$src"'" | grep -c "\\^f filter"'
    [[ "${lines[0]}" -ge 1 ]]
}

@test "extract: ^f filter hint in HELP_EXTRACT" {
    local src="$SCRIPT_DIR/dispatch.sh"
    run bash -c 'grep -A20 "HELP_EXTRACT=" "'"$src"'" | grep -c "filter"'
    [[ "${lines[0]}" -ge 1 ]]
}

@test "extract: browser detection uses BROWSER then xdg-open then open" {
    run bash -c '
        src="'"$SCRIPT_DIR"'/actions.sh"
        ok=0
        sed -n "/action_open_url/,/^}/p" "$src" | grep -q "BROWSER" && ok=$((ok+1))
        sed -n "/action_open_url/,/^}/p" "$src" | grep -q "xdg-open" && ok=$((ok+1))
        sed -n "/action_open_url/,/^}/p" "$src" | grep -q "open" && ok=$((ok+1))
        echo "$ok"
    '
    [[ "${lines[0]}" -ge 3 ]]
}
