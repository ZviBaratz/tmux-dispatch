#!/usr/bin/env bash
# =============================================================================
# doctor.sh — Health check diagnostic for tmux-dispatch
# =============================================================================
# Checks the user's environment for compatibility with tmux-dispatch.
# Run standalone: bash scripts/doctor.sh
# =============================================================================

set -euo pipefail

# ─── Color helpers ──────────────────────────────────────────────────────────
_green=$'\033[32m'
_yellow=$'\033[33m'
_red=$'\033[31m'
_bold=$'\033[1m'
_dim=$'\033[2m'
_reset=$'\033[0m'

ok()   { printf "  ${_green}✓${_reset} %s\n" "$*"; }
warn() { printf "  ${_yellow}!${_reset} %s\n" "$*"; }
fail() { printf "  ${_red}✗${_reset} %s\n" "$*"; }
header() { printf "\n${_bold}%s${_reset}\n" "$*"; }
dim()  { printf "    ${_dim}%s${_reset}\n" "$*"; }

# ─── Version comparison ─────────────────────────────────────────────────────
# Returns true (0) if $1 >= $2 using version sorting
_version_at_least() {
    [[ "$(printf '%s\n%s' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

# Extract version string from command output (first match of N.N or N.N.N)
_extract_version() {
    sed 's/[^0-9.]/ /g' | { grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || true; } | head -1
}

# ─── Counters ───────────────────────────────────────────────────────────────
_ok_count=0
_warn_count=0
_fail_count=0

_count_ok()   { ok "$@"; _ok_count=$((_ok_count + 1)); }
_count_warn() { warn "$@"; _warn_count=$((_warn_count + 1)); }
_count_fail() { fail "$@"; _fail_count=$((_fail_count + 1)); }

# =============================================================================
# Required tools
# =============================================================================
header "Required tools"

# ── bash ──────────────────────────────────────────────────────────────────
bash_version="${BASH_VERSION:-unknown}"
bash_major="${BASH_VERSINFO[0]:-0}"
if [[ "$bash_major" -ge 4 ]]; then
    _count_ok "bash ${bash_version}"
else
    _count_fail "bash ${bash_version} — version 4.0+ required"
    dim "macOS users: brew install bash"
fi

# ── tmux ──────────────────────────────────────────────────────────────────
if command -v tmux &>/dev/null; then
    tmux_raw=$(tmux -V 2>/dev/null || echo "unknown")
    tmux_ver=$(echo "$tmux_raw" | _extract_version)
    if [[ -z "$tmux_ver" ]]; then
        _count_warn "tmux installed (${tmux_raw}) — could not parse version"
    elif _version_at_least "$tmux_ver" "3.2"; then
        _count_ok "tmux ${tmux_ver} (popup support: yes)"
    elif _version_at_least "$tmux_ver" "2.6"; then
        _count_ok "tmux ${tmux_ver} (popup support: no — will use split-window fallback)"
    else
        _count_fail "tmux ${tmux_ver} — version 2.6+ required (3.2+ for popup)"
    fi
else
    _count_fail "tmux not found"
fi

# ── fzf ───────────────────────────────────────────────────────────────────
if command -v fzf &>/dev/null; then
    fzf_ver=$(fzf --version 2>/dev/null | _extract_version)
    if [[ -z "$fzf_ver" ]]; then
        _count_warn "fzf installed — could not parse version"
    elif _version_at_least "$fzf_ver" "0.49"; then
        _count_ok "fzf ${fzf_ver} (full feature support)"
    elif _version_at_least "$fzf_ver" "0.38"; then
        _count_ok "fzf ${fzf_ver} (0.49+ recommended for all features)"
    else
        _count_fail "fzf ${fzf_ver} — version 0.38+ required (0.49+ recommended)"
    fi
else
    _count_fail "fzf not found — required for all modes"
fi

# ── perl ──────────────────────────────────────────────────────────────────
if command -v perl &>/dev/null; then
    perl_ver=$(perl -v 2>/dev/null | _extract_version)
    _count_ok "perl ${perl_ver:-installed}"
else
    _count_fail "perl not found — required for session preview"
fi

# =============================================================================
# Recommended tools
# =============================================================================
header "Recommended tools"

# ── fd / fdfind ───────────────────────────────────────────────────────────
if command -v fd &>/dev/null; then
    fd_ver=$(fd --version 2>/dev/null | _extract_version)
    _count_ok "fd ${fd_ver:-installed}"
elif command -v fdfind &>/dev/null; then
    fd_ver=$(fdfind --version 2>/dev/null | _extract_version)
    _count_ok "fdfind ${fd_ver:-installed} (Debian/Ubuntu name for fd)"
else
    _count_warn "fd not found — faster file finding (falls back to find)"
    dim "Install: brew install fd / apt install fd-find / cargo install fd-find"
fi

# ── bat / batcat ──────────────────────────────────────────────────────────
if command -v bat &>/dev/null; then
    bat_ver=$(bat --version 2>/dev/null | _extract_version)
    _count_ok "bat ${bat_ver:-installed}"
elif command -v batcat &>/dev/null; then
    bat_ver=$(batcat --version 2>/dev/null | _extract_version)
    _count_ok "batcat ${bat_ver:-installed} (Debian/Ubuntu name for bat)"
else
    _count_warn "bat not found — syntax-highlighted preview (falls back to head)"
    dim "Install: brew install bat / apt install bat / cargo install bat"
fi

# ── rg (ripgrep) ──────────────────────────────────────────────────────────
if command -v rg &>/dev/null; then
    rg_ver=$(rg --version 2>/dev/null | head -1 | _extract_version)
    _count_ok "rg ${rg_ver:-installed}"
else
    _count_warn "rg (ripgrep) not found — required for grep mode"
    dim "Install: brew install ripgrep / apt install ripgrep / cargo install ripgrep"
fi

# =============================================================================
# Optional tools
# =============================================================================
header "Optional tools"

# ── zoxide ────────────────────────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
    zoxide_ver=$(zoxide --version 2>/dev/null | _extract_version)
    _count_ok "zoxide ${zoxide_ver:-installed}"
else
    _count_warn "zoxide not found — frecency-ranked directory picker"
    dim "Install: brew install zoxide / cargo install zoxide"
fi

# ── tree ──────────────────────────────────────────────────────────────────
if command -v tree &>/dev/null; then
    tree_ver=$(tree --version 2>/dev/null | _extract_version)
    _count_ok "tree ${tree_ver:-installed}"
else
    _count_warn "tree not found — session-new preview enhancement"
    dim "Install: brew install tree / apt install tree"
fi

# =============================================================================
# Configuration (only if tmux server is running)
# =============================================================================
header "Configuration"

if tmux list-sessions &>/dev/null 2>&1; then
    # ── Plugin loaded ─────────────────────────────────────────────────────
    find_key=$(tmux show-option -gqv "@dispatch-find-key" 2>/dev/null || true)
    if [[ -n "$find_key" ]]; then
        _count_ok "plugin loaded (find key: ${find_key})"
    else
        _count_warn "plugin not loaded — @dispatch-find-key not set"
        dim "Reload config: tmux source-file ~/.tmux.conf"
    fi

    # ── Tool cache ────────────────────────────────────────────────────────
    cached_fd=$(tmux show -sv "@_dispatch-fd" 2>/dev/null || true)
    if [[ -n "$cached_fd" ]]; then
        _count_ok "tool cache active (fd: ${cached_fd})"
    else
        _count_warn "tool cache not populated — run dispatch once to initialize"
    fi
else
    dim "tmux server not running — skipping runtime checks"
fi

# ── commands.conf ─────────────────────────────────────────────────────────
commands_file="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-dispatch/commands.conf"
if [[ -f "$commands_file" ]]; then
    cmd_count=$(grep -v '^#' "$commands_file" | grep -cv '^[[:space:]]*$' || true)
    _count_ok "commands.conf found (${cmd_count} commands)"
    dim "$commands_file"
else
    _count_warn "commands.conf not found — will be created on first use of : prefix"
    dim "Expected at: $commands_file"
fi

# =============================================================================
# Summary
# =============================================================================
printf "\n"
total=$((_ok_count + _warn_count + _fail_count))
printf '%s%s%s ' "${_bold}" "Summary:" "${_reset}"
printf '%s%d ok%s, ' "${_green}" "$_ok_count" "${_reset}"
printf '%s%d warnings%s, ' "${_yellow}" "$_warn_count" "${_reset}"
printf '%s%d failures%s' "${_red}" "$_fail_count" "${_reset}"
printf ' (%d checks)\n' "$total"

if [[ "$_fail_count" -gt 0 ]]; then
    exit 1
fi
exit 0
