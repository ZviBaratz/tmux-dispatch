---
title: FAQ
nav_order: 6
---

# Frequently Asked Questions

### Alt keys (Alt+o, Alt+s, Alt+w) don't work

This is the most common issue. Most terminal emulators need a setting change to send Alt as the correct escape sequence:

- **iTerm2**: Preferences → Profiles → Keys → Left Option Key → Esc+
- **Alacritty**: No change needed (works by default)
- **Kitty**: No change needed (works by default)
- **Windows Terminal**: Settings → Actions → remove any conflicting Alt keybindings

See [Troubleshooting](reference/troubleshooting) for more details.

Alternatively, use the prefix keybinding `prefix + e` which works in all terminals.

### Does this work on macOS?

Yes, but macOS ships bash 3.2 which is too old. Install a newer bash:

```bash
brew install bash
```

tmux-dispatch will automatically find the Homebrew bash. No need to change your default shell.

### What fzf version do I need?

- **0.38+**: Required for mode switching (the `become` action)
- **0.45+**: Recommended for dynamic border labels
- **0.49+**: Recommended for all features

Check your version: `fzf --version`

### Can I use this without fd, bat, or ripgrep?

Yes, with reduced functionality:

- **Without fd**: Falls back to `find` (slower, no smart defaults)
- **Without bat**: Falls back to `head` (no syntax highlighting in preview)
- **Without ripgrep**: Grep mode is unavailable (no fallback -- rg is required for live grep)
- **Without zoxide**: Directory mode uses `fd`/`find` instead of frecency-ranked results

### How do I change the default keybindings?

Add to your `~/.tmux.conf`:

```tmux
# Change file finder to Ctrl+f
set -g @dispatch-find-key 'C-f'

# Change grep to Ctrl+g
set -g @dispatch-grep-key 'C-g'

# Disable a keybinding
set -g @dispatch-session-key 'none'
```

See [Configuration](reference/configuration) for all options.

### How do I use a different editor?

tmux-dispatch auto-detects nvim → vim → vi. To override:

```tmux
# Editor inside the popup
set -g @dispatch-popup-editor 'nvim'

# Editor sent to your pane via Ctrl+O
set -g @dispatch-pane-editor 'code'
```
