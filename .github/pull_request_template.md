## What

<!-- Brief description of the change -->

## Why

<!-- Link to issue (e.g., Closes #123) or explain the problem -->

## Breaking changes

<!-- Describe any breaking changes. Delete this section if N/A. -->

## Testing

- [ ] `shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh` passes
- [ ] `bats tests/` passes
- [ ] Manually tested in tmux (version: )

## Checklist

- [ ] New scripts are executable (`chmod +x`)
- [ ] ShellCheck directives added for sourced files (`# shellcheck source=helpers.sh`)
- [ ] Graceful fallback maintained for optional tools (`fd`, `bat`, `rg`, `zoxide`)
- [ ] PR title follows [conventional commits](https://www.conventionalcommits.org/) format (lowercase)
