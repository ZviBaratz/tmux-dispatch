---
title: FAQ
nav_order: 6
---

# Frequently Asked Questions

### Alt key (Alt+o) doesn't work

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

### How do I add direct keybindings for grep and sessions?

By default, only `Alt+o` (file finder) is bound. All other modes are accessible via prefix characters from inside the popup (`>` for grep, `@` for sessions, etc.). To add direct keybindings, set them in your `~/.tmux.conf`:

```tmux
# Direct key for live grep
set -g @dispatch-grep-key 'M-s'

# Direct key for session picker
set -g @dispatch-session-key 'M-w'

# Direct key to reopen last mode with last query
set -g @dispatch-resume-key 'M-r'
```

Set any key to `'none'` to disable it. See [Configuration](reference/configuration) for all options.

### How do I use VS Code or another non-vim editor?

tmux-dispatch has two separate editor settings because the popup and your pane have different requirements:

- **`Enter`** opens the file inside the popup, which is a terminal environment. This editor must be a terminal program (vim, nvim, vi). Set it with `@dispatch-popup-editor`.
- **`Ctrl+O`** sends the editor command to your originating tmux pane instead. This can be any editor, including GUI editors like VS Code, Cursor, or Sublime Text. Set it with `@dispatch-pane-editor`.

For VS Code users, the typical setup is:

```tmux
# Keep the popup editor as-is (or set explicitly)
set -g @dispatch-popup-editor 'nvim'

# Send to your pane with Ctrl+O
set -g @dispatch-pane-editor 'code'
```

With this configuration, `Enter` opens the file in nvim inside the popup, and `Ctrl+O` closes the popup and runs `code <file>` in your pane.

If `@dispatch-pane-editor` is not set, it falls back to `$EDITOR`, then auto-detects nvim/vim/vi. See [Configuration](reference/configuration) for all editor options.

### Does this work over SSH?

Yes. tmux-dispatch runs entirely inside tmux, so it works over SSH the same way it does locally. The only caveat is that tools like `fd`, `bat`, and `rg` must be installed on the remote machine -- they are not forwarded from your local machine. The plugin's PATH augmentation checks common install locations (Homebrew, mise, asdf, Nix, Cargo), so tools installed via these methods are found automatically.

### Why doesn't the file list update after I create or delete a file?

The file list is generated when the popup opens and does not automatically refresh for external filesystem changes. To see new or deleted files, close the popup (`Escape`) and reopen it (`Alt+o`). In-place delete (`Ctrl+X`) and rename (`Ctrl+R`) do refresh the list immediately because they use fzf's built-in reload mechanism.

### What is frecency?

Frecency is a ranking algorithm that combines **frequency** (how often you open a file) and **recency** (how recently you opened it). Files you use often and recently appear at the top of the file finder list, even before you type anything. This means your most-used files are always a single `Enter` away. Frecency tracking is enabled by default and can be toggled with `@dispatch-history` set to `off`.

### Can I use tmux-dispatch outside of tmux?

No. tmux-dispatch is a tmux plugin that uses tmux APIs (`display-popup`, `send-keys`, `switch-client`, etc.) and is designed to run inside a tmux session. The fzf popup is launched by tmux, and actions like sending editor commands to a pane or switching sessions require an active tmux environment.
