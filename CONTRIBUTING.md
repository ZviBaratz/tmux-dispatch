# Contributing to tmux-dispatch

Contributions are welcome! Here's how to help.

## Reporting Bugs

Please include:
- tmux version (`tmux -V`)
- fzf version (`fzf --version`)
- bash version (`bash --version`)
- OS and terminal emulator
- Steps to reproduce

## Local Development

### Setup

```bash
# Clone and branch
git clone https://github.com/ZviBaratz/tmux-dispatch.git
cd tmux-dispatch
git checkout -b feat/my-feature

# Install dev dependencies
# macOS
brew install bats-core shellcheck bash

# Ubuntu/Debian
sudo apt install bats shellcheck
```

### Symlink for live testing

To test your changes inside a real tmux session, symlink the repo into your tmux plugins directory:

```bash
ln -s "$PWD" ~/.tmux/plugins/tmux-dispatch
```

Then reload the plugin:

```bash
tmux source-file ~/.tmux.conf
```

## Running Checks

Run all three before submitting a pull request:

### Lint (ShellCheck)

```bash
shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh
```

### Syntax check

```bash
bash -n dispatch.tmux && bash -n scripts/helpers.sh && bash -n scripts/dispatch.sh && bash -n scripts/preview.sh && bash -n scripts/actions.sh && bash -n scripts/git-preview.sh && bash -n scripts/session-preview.sh
```

### Unit tests

```bash
bats tests/
```

Tests use [bats-core](https://github.com/bats-core/bats-core). Shared fixtures and helpers live in `tests/common.bash` -- source it at the top of new test files.

## Code Contributions

1. Fork and branch from `main`
2. Follow the project conventions:
   - `#!/usr/bin/env bash` shebang
   - `set -euo pipefail` in executable scripts (not in `helpers.sh` or `dispatch.tmux`)
   - ShellCheck must pass
   - New scripts must be executable (`chmod +x`)
   - Maintain graceful fallbacks for optional tools
   - tmux options use the `@dispatch-` prefix
   - Conventional commits, lowercase (`feat: add feature`, `fix: resolve bug`)
3. Run all checks (see above)
4. Open a pull request with a clear description

## Adding a New Mode

1. **Add a mode function** -- create `run_yourmode_mode()` in `scripts/dispatch.sh` following the pattern of existing modes (e.g., `run_files_mode`, `run_grep_mode`).
2. **Add to the dispatch case statement** -- add your mode name to the `case "$MODE"` block in the `main` function so `--mode=yourmode` is recognized.
3. **Add a result handler** -- if your mode needs custom action on `Enter` (beyond opening a file), add a handler after the fzf call.
4. **Add a keybinding** -- register a `@dispatch-yourmode-key` option in `dispatch.tmux` with a sensible default (or `none` to disable by default).
5. **Add tests** -- write a `tests/yourmode.bats` file. Source `tests/common.bash` for shared fixtures.
6. **Add documentation** -- create a `docs/modes/yourmode.md` page and update the nav.

See the [Architecture Reference](docs/reference/architecture.md) for how the scripts fit together.

## Testing

- Unit tests use [bats-core](https://github.com/bats-core/bats-core)
- Shared test fixtures and mock helpers are in `tests/common.bash` -- source it at the top of new test files
- Manual testing requires a running tmux session
- Reload plugin: `tmux source-file ~/.tmux.conf`

## Release Process

Releases are automated via GitHub Actions:

1. Tag a commit on `main`: `git tag v1.x.x`
2. Push the tag: `git push origin v1.x.x`
3. GitHub Actions creates the release automatically
