---
title: Troubleshooting
parent: Reference
nav_order: 4
---

# Troubleshooting

Common issues and their solutions.

### Plugin not loading after install

If nothing happens when you press `Alt+o` and the keybindings are not registered:

1. **Run TPM install**: Press `prefix + I` (capital I) after adding the plugin line to `~/.tmux.conf`. TPM does not install plugins automatically when you edit the config file.

2. **Reload tmux config**: After installing, reload with `tmux source-file ~/.tmux.conf` or restart tmux.

3. **Check executable permissions**: All scripts must be executable. If you cloned manually, run:

   ```bash
   chmod +x ~/.tmux/plugins/tmux-dispatch/dispatch.tmux ~/.tmux/plugins/tmux-dispatch/scripts/*.sh
   ```

4. **Verify bash version**: tmux-dispatch requires bash 4.0+. Check with `bash --version`. On macOS, the default `/bin/bash` is 3.2 -- install a newer version with `brew install bash`.

5. **Confirm the plugin line**: Ensure your `~/.tmux.conf` contains the plugin line **before** the TPM initialization line (`run '~/.tmux/plugins/tpm/tpm'`):

   ```tmux
   set -g @plugin 'ZviBaratz/tmux-dispatch'
   # ... other plugins ...
   run '~/.tmux/plugins/tpm/tpm'
   ```

6. **Check TPM itself**: Verify TPM is installed and working by pressing `prefix + I`. If TPM is not installed, follow the [TPM installation guide](https://github.com/tmux-plugins/tpm#installation).

### Alt keys not working

Your terminal emulator must send Alt as Meta (Escape prefix). In iTerm2, go to Profiles, then Keys, then set Left Option key to Esc+. In Alacritty and Kitty this is the default behavior. In Windows Terminal, Alt keys work out of the box.

If you prefer not to configure Alt keys, you can remap the keybindings to use a tmux prefix key instead. See [Configuration](configuration) for how to change or disable individual keybindings.

### "ripgrep (rg) is required"

Grep mode requires ripgrep to be installed. Install it with your package manager:

```bash
# macOS
brew install ripgrep

# Ubuntu / Debian
sudo apt install ripgrep

# Arch Linux
pacman -S ripgrep

# Fedora
sudo dnf install ripgrep

# Via mise
mise use -g ripgrep@latest
```

### Popup not appearing

tmux versions before 3.2 do not support `display-popup`. The plugin automatically falls back to `split-window`, which opens a pane at the bottom of your terminal instead of a floating popup. Everything works the same way functionally -- you just do not get the floating overlay.

To get the popup experience, upgrade tmux to 3.2 or later.

### "unknown action: become"

Mode switching (typing prefix characters like `>`, `@`, `!`, `#` and backspace-to-home) requires fzf 0.38 or later. The `become` action was introduced in that version.

File finding and grep work without `become` -- you just cannot switch between modes within the popup. Upgrade fzf to enable mode switching:

```bash
# macOS
brew install fzf

# Via mise
mise use -g fzf@latest

# From source
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install
```

### "command not found" for fzf/fd/rg

tmux runs plugins in a minimal shell environment that may not include your login shell's PATH. The plugin automatically checks common installation locations (Homebrew on macOS and Linux, mise, asdf, Nix, Cargo), but if your tools are installed in a non-standard location, add the path to tmux's environment in your `~/.tmux.conf`:

```tmux
set-environment -g PATH "/your/custom/bin:$PATH"
```

For example, if you installed tools via Homebrew on Apple Silicon:

```tmux
set-environment -g PATH "/opt/homebrew/bin:$PATH"
```

### Clipboard not working on WSL

The `Ctrl+Y` copy action uses `tmux load-buffer -w`, which syncs to the system clipboard via tmux's `set-clipboard` option. On WSL, this may not reach the Windows clipboard automatically.

Solutions:

- Install [win32yank](https://github.com/equalsraf/win32yank) and ensure it is on your PATH
- Configure tmux to use `clip.exe` for clipboard operations
- See the [tmux wiki on clipboard](https://github.com/tmux/tmux/wiki/Clipboard) for detailed setup instructions

### Box-drawing characters garbled

The session preview uses Unicode box-drawing characters (lines and corners like `+--` rendered as proper box outlines). If these render as question marks or garbled text, your terminal font does not support Unicode box-drawing.

Switch to a Unicode-capable monospace font such as JetBrains Mono, Fira Code, or any Nerd Font variant.

### Slow file listing

If the file finder takes a long time to appear in large repositories:

**Limit search depth:**
```tmux
set -g @dispatch-fd-args "--max-depth 8"
```

**Exclude large directories:** fd respects `.gitignore` by default. For non-git directories, create a `.fdignore` file in your project root:
```
node_modules
.cache
dist
vendor
```

**Disable git indicators** for very large repos:
```tmux
set -g @dispatch-git-indicators "off"
```

**Disable frecency** if the history file has grown large:
```tmux
set -g @dispatch-history "off"
```

### Filenames with colons

Grep mode parses ripgrep output in the `file:line:content` format using the colon as a delimiter. Files with `:` in the name (rare on Unix systems, impossible on Windows) will not be parsed correctly, causing the wrong file to open or the line number to be misinterpreted.

This is a known limitation shared by virtually all fzf + ripgrep workflows. If you encounter this, rename the affected files to remove colons.
