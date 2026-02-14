# Contributing to tmux-dispatch

Contributions are welcome! Here's how to help.

## Reporting Bugs

Please include:
- tmux version (`tmux -V`)
- fzf version (`fzf --version`)
- bash version (`bash --version`)
- OS and terminal emulator
- Steps to reproduce

## Code Contributions

1. Fork and branch from `main`
2. Follow the project conventions:
   - `#!/usr/bin/env bash` shebang
   - `set -euo pipefail` in executable scripts
   - ShellCheck must pass: `shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh`
   - New scripts must be executable (`chmod +x`)
   - Maintain graceful fallbacks for optional tools
   - tmux options use the `@dispatch-` prefix
   - Conventional commits, lowercase (`feat: add feature`, `fix: resolve bug`)
3. Run checks before submitting:
   ```bash
   shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh
   bats tests/
   ```
4. Open a pull request with a clear description

## Testing

- Unit tests use [bats-core](https://github.com/bats-core/bats-core)
- Manual testing requires a running tmux session
- Reload plugin: `tmux source-file ~/.tmux.conf`
