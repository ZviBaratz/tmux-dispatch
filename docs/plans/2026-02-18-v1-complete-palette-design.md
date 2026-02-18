# v1.0.0 "Complete the Palette" Design

**Date**: 2026-02-18
**Status**: Approved
**Goal**: Add two features that complete the command-palette metaphor, optimize startup performance, and polish for launch — maximizing both broad adoption and power-user depth.

## Context

tmux-dispatch already has 9 modes covering files, grep, git, dirs, sessions, and windows. Three prior design passes landed security hardening, refactoring, UX polish, and onboarding improvements. This design adds the missing pieces that make the "unified command palette" story complete.

**Competitive insight**: Three separate tmux plugins (extrakto 896 stars, tmux-fuzzback 172 stars, tmux-thumbs ~900 stars) exist solely for scrollback/text extraction — totaling ~2,000 stars. Custom command palettes are served by tmux-which-key (232 stars) and tmux-command-palette (27 stars). Adding these capabilities natively eliminates the need for 2-3 additional plugins.

## Section 1: Scrollback Search Mode

**Prefix**: `$` — shell prompt symbol, suggests "terminal output."

**Mode name**: `scrollback` (`--mode=scrollback`)

### How it works

1. User types `$` in files mode → `become()` switches to scrollback mode
2. `tmux capture-pane -p -S -N` captures the originating pane's scrollback, where N is configurable via `@dispatch-scrollback-lines` (default: 10,000)
3. Lines are deduplicated (scrollback has many repeated prompts/blank lines) and piped to fzf
4. Fuzzy search filters the lines

### Actions

| Key | Action |
|-----|--------|
| Enter | Copy selected line(s) to tmux buffer + system clipboard |
| Ctrl+O | Paste selection into the originating pane (send-keys) |
| Ctrl+X | Delete selected line from shell history file (`$HISTFILE`) with reload |
| Tab/Shift-Tab | Multi-select for grabbing multiple lines |
| Backspace (empty) | Return to files mode |

### Preview

Surrounding context: 5 lines above and below the matched line from the scrollback, with the matched line highlighted.

### Border label

`scrollback $ · ? help · enter copy · ^o paste · ^x delete · S-tab select · ⌫ files`

### Help overlay

```
SCROLLBACK
─────────────────────────────
enter     copy to clipboard
^O        paste to pane
^X        delete from history
S-tab     multi-select
^D/^U     scroll preview
⌫ empty   back to files
```

### Configuration

- `@dispatch-scrollback-lines` — number of scrollback lines to capture (default: `10000`)

### Implementation notes

- ~80-120 lines as `run_scrollback_mode()` in dispatch.sh
- Ctrl+X: reads `$HISTFILE`, removes matching line(s), writes back. Shows "not in history" if line not found (scrollback contains output too, not just commands)
- Deduplication: `awk '!seen[$0]++'` to collapse repeated lines while preserving order
- Reverse line order so most recent output appears first

## Section 2: Custom User Commands Mode

**Prefix**: `:` — universal "command mode" prefix (vim, VS Code).

**Mode name**: `commands` (`--mode=commands`)

### Config file format

Location: `~/.config/tmux-dispatch/commands.conf` (overridable via `@dispatch-commands-file`)

```
# Lines starting with # are comments, blank lines ignored
# Format: label | command
#
# Commands run in a shell by default.
# Prefix with "tmux:" to run as a tmux command.

Deploy staging | ssh staging 'cd /app && docker-compose up -d'
Restart nginx  | sudo systemctl restart nginx
Git pull all   | for d in ~/projects/*/; do git -C "$d" pull; done
Split terminal | tmux: split-window -h
Toggle mouse   | tmux: set mouse
```

### How it works

1. User types `:` in files mode → `become()` switches to commands mode
2. Reads commands.conf, presents labels in fzf
3. Fuzzy search filters by label
4. Enter executes the command (shell command or tmux command based on `tmux:` prefix)

### Actions

| Key | Action |
|-----|--------|
| Enter | Execute the selected command |
| Ctrl+E | Edit commands.conf in popup editor |
| Backspace (empty) | Return to files mode |

### Preview

Shows the command that will be executed (right side of `|`). Syntax-highlighted via bat if available, plain text otherwise.

### Graceful fallback

If no commands.conf exists, fzf shows an empty list with a header message: "No commands configured — press ^E to create commands.conf"

### Border label

`commands : · ? help · enter run · ^e edit · ⌫ files`

### Help overlay

```
COMMANDS
─────────────────────────────
enter     run command
^E        edit commands.conf
⌫ empty   back to files
```

### Configuration

- `@dispatch-commands-file` — override config file path (default: `~/.config/tmux-dispatch/commands.conf`)

### Implementation notes

- ~60-80 lines as `run_commands_mode()` in dispatch.sh
- Parse: `grep -v '^#' | grep -v '^$'` then split on ` | ` (first occurrence)
- Shell commands: `bash -c "$command"`
- tmux commands: strip `tmux: ` prefix, `tmux $command`

## Section 3: Performance & Startup

### Problem

Every popup open incurs ~60ms fixed overhead before fzf starts:
- 6x `tmux show-option` subprocesses (~30ms)
- 6x+ `command -v` for tool detection (~12ms)
- `fzf --version` check with sort -V (~10ms)
- Misc setup (~8ms)

### Optimization 1: Cache tool paths in tmux server variables (~40ms saved)

Move tool detection to plugin load time (`dispatch.tmux`). Store results in tmux server variables that persist for the server lifetime:

```bash
# dispatch.tmux (runs once at plugin load)
tmux set -s @_dispatch-fd "$(detect_fd)"
tmux set -s @_dispatch-bat "$(detect_bat)"
tmux set -s @_dispatch-rg "$(detect_rg)"
tmux set -s @_dispatch-zoxide "$(detect_zoxide)"
tmux set -s @_dispatch-popup-editor "$(detect_popup_editor "...")"
tmux set -s @_dispatch-fzf-version "$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
```

```bash
# dispatch.sh (runs every popup open — fast reads)
FD_CMD=$(tmux show -sv @_dispatch-fd 2>/dev/null)
BAT_CMD=$(tmux show -sv @_dispatch-bat 2>/dev/null)
```

Server variables use `@_dispatch-` prefix (leading underscore = internal/cached, distinct from user-facing `@dispatch-` options).

### Optimization 2: Batch tmux option reads (~20ms saved)

Replace 6+ separate `tmux show-option -gqv` calls with a single `tmux show-options -g` filtered to `@dispatch-`:

```bash
# One subprocess instead of six
while IFS=' ' read -r key value; do
    case "$key" in
        @dispatch-popup-editor)  OPT_POPUP_EDITOR="$value" ;;
        @dispatch-pane-editor)   OPT_PANE_EDITOR="$value" ;;
        @dispatch-fd-args)       FD_EXTRA_ARGS="$value" ;;
        # ...
    esac
done < <(tmux show-options -g 2>/dev/null | grep '^@dispatch-')
```

### Optimization 3: Skip fzf version check on every open (~10ms saved)

The fzf version is cached in `@_dispatch-fzf-version` at plugin load. dispatch.sh reads the cached value instead of running `fzf --version | grep | sort -V`.

### Net effect

~60ms fixed overhead → ~15-20ms. Popup feels noticeably snappier.

### Out of scope

- Rewriting in a compiled language
- Background pre-warming
- Lazy-loading helpers.sh (already small at 282 lines)

## Section 4: Launch Polish

### 4a. README narrative refresh

- Update tagline to mention scrollback search and custom commands
- Add new feature bullets for scrollback and commands modes
- Update Quick Start table: add `$` and `:` prefix hints
- Sharpen "How is this different?" — position as "replaces 3-4 separate plugins"
- Update Similar Projects: add extrakto, sesh, tmux-which-key
- Update mode-switching prefix list and welcome guide

### 4b. Demo GIF updates

- New `tapes/scrollback.tape` — scrollback search, copy, history deletion
- New `tapes/commands.tape` — custom commands execution
- Update `tapes/demo.tape` — include scrollback and commands in mode-switching sequence
- Update `tapes/mode-switching.tape` — add `$` and `:` prefixes

### 4c. Documentation site updates

- New `docs/modes/scrollback.md`
- New `docs/modes/commands.md` (with config file format reference)
- Update `docs/modes/index.md` — add both modes to mode tree
- Update `docs/reference/keybindings.md` — new keybindings
- Update `docs/reference/configuration.md` — new options
- Update `docs/features/mode-switching.md` — new prefixes

### 4d. CHANGELOG update

Add to `[1.0.0]` "Added" section:
- Scrollback search mode (`$` prefix) with context preview and history deletion
- Custom user commands mode (`:` prefix) with config file support
- Performance: cached tool detection and batched option reads at plugin load

## Implementation Order

1. Performance optimizations (cache + batch) — foundation, benefits all modes
2. Scrollback search mode — largest new feature
3. Custom commands mode — smaller, benefits from patterns established in step 2
4. Tests for new modes and performance changes
5. Launch polish (README, docs, CHANGELOG, demo GIFs)

Each step is one or more well-scoped commits.
