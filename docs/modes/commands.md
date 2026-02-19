---
title: Custom Commands
parent: Modes
nav_order: 8
---
# Custom Commands

Custom commands mode gives you a personal command palette -- a configurable list of frequently used commands that you can invoke with a few keystrokes. Define your own commands in a simple config file, and they appear as fuzzy-searchable entries in the popup. Commands can be shell commands (run in the originating pane) or tmux commands (executed directly by tmux).

This is useful for workflows you repeat often: deploying, running test suites, toggling tmux settings, restarting services, or any command sequence you'd otherwise have to type or remember.

## How to access

- Type `:` from files mode -- the remainder of your query filters the command list.
- Or bind a dedicated key via `@dispatch-commands-key` to open commands directly.

## Config file format

Commands are defined in `~/.config/tmux-dispatch/commands.conf` (or a custom path via `@dispatch-commands-file`). The format is one command per line:

```
# Lines starting with # are comments
# Format: label | command

deploy staging | ssh staging ./deploy.sh
run tests | npm test
restart api | systemctl restart api-server
lint project | npm run lint

# Prefix with tmux: to run as a tmux command instead of a shell command
tmux: split horizontally | split-window -h
tmux: toggle status bar | set-option -g status
tmux: reload config | source-file ~/.tmux.conf
```

Each line has two parts separated by `|`:
- **Label** -- the text shown in the fuzzy finder (and what you search against)
- **Command** -- the shell command or tmux command to execute

Lines starting with `#` are comments and are ignored. Empty lines are also ignored.

Commands prefixed with `tmux:` in the label are executed as tmux commands (the command part is passed to `tmux` directly). All other commands are sent to the originating pane as shell commands.

## Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Execute the selected command |
| `Ctrl+E` | Edit `commands.conf` in popup editor |
| `Backspace` on empty | Return to files (home) |
| `?` | Show help cheat sheet in preview |
| `Escape` | Close popup |

## Graceful fallback

If no config file exists when you enter commands mode, the popup shows a helpful message explaining how to create one, along with the expected file path. You can press `Ctrl+E` to create and edit the config file immediately, or press Backspace to return to files mode.

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-commands-key` | `none` | Direct keybinding (disabled by default; use `:` prefix from files mode) |
| `@dispatch-commands-file` | `~/.config/tmux-dispatch/commands.conf` | Path to the custom commands configuration file |

## Tips

- From files mode, type `:deploy` to instantly filter your commands for anything matching "deploy" -- the `:` switches to commands and `deploy` becomes the filter query.
- Use `Ctrl+E` to quickly add new commands without leaving the popup. After saving, the command list reloads automatically.
- Group related commands with comments in your config file for better organization.
- tmux commands are useful for toggling settings, managing layouts, or running tmux actions that don't make sense as shell commands.
- The config file is a plain text file -- you can version-control it, symlink it across machines, or generate it with a script.
- If you change the config file path with `@dispatch-commands-file`, make sure the directory exists. The plugin will not create directories automatically.
