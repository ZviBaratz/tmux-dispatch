# VHS recording script for tmux-dispatch demo
# Run with: vhs tapes/demo.tape
# Produces: assets/demo.gif (run from repo root)
# Requires: vhs (https://github.com/charmbracelet/vhs), tmux, fzf, fd, bat, rg

Output assets/demo.gif
Set Shell bash
Set FontSize 14
Set Width 1200
Set Height 700
Set Padding 10

# ─── Setup (hidden from recording) ───────────────────────────────────────────

Hide
Type "bash tapes/demo-setup-modes.sh && tmux -L demo-vhs attach -t demo"
Enter
Sleep 2s
Type "clear"
Enter
Sleep 500ms
Show

Sleep 1s

# ─── 1. File finder — welcome cheat sheet + bat preview ──────────────────────

Alt+o
Sleep 2.5s

# ─── 2. Filter files — "main" narrows list, bat preview shows ────────────────

Type@150ms "main"
Sleep 2s

# ─── 3. Open in popup editor — Enter opens nvim, :q returns to fzf ───────────

Enter
Sleep 2s
Type ":q"
Enter
Sleep 1s

# ─── 4. Send to pane — still in fzf, Down+Ctrl+O sends next file to pane ────

Down
Sleep 500ms
Ctrl+o
Sleep 2s
Type ":q"
Enter
Sleep 1s

# ─── 5. Multi-select + rename — Tab to select, then Ctrl+R inline rename ────

Alt+o
Sleep 1s
Tab
Sleep 500ms
Tab
Sleep 1.5s
Ctrl+u
Sleep 300ms
Type@150ms "VER"
Sleep 1s
# Ctrl+R transitions to rename mode (fzf query = new filename)
Ctrl+r
Sleep 1s
Type ".txt"
Sleep 500ms
Enter
Sleep 1.5s
Escape
Sleep 1s

# ─── 6. Sessions — preview grid + Ctrl+R inline rename ───────────────────────

Alt+w
Sleep 2s
Down
Sleep 500ms
# Ctrl+R transitions to rename-session mode
Ctrl+r
Sleep 1s
Ctrl+u
Type "backend"
Sleep 500ms
Enter
Sleep 1.5s
Escape
Sleep 1s

# ─── 7. Live grep — ">" prefix switches from files to grep ───────────────────
# (Alt+s has a VHS parser bug — github.com/charmbracelet/vhs/issues/442)

Alt+o
Sleep 500ms
Type@150ms ">Hello"
Sleep 2s
Escape
Sleep 1s

# ─── Cleanup (hidden) ────────────────────────────────────────────────────────

Hide
Type "exit"
Enter
Sleep 300ms
Type "tmux -L demo-vhs kill-server 2>/dev/null; rm -rf /tmp/demo-project"
Enter
