# VHS recording: File Finder mode
Output docs/assets/files.gif
Set Shell bash
Set FontSize 14
Set Width 1200
Set Height 700
Set Padding 10

Hide
Type "bash tapes/demo-setup-modes.sh && tmux -L demo-vhs attach -t demo"
Enter
Sleep 2s
Type "clear"
Enter
Sleep 500ms
Show

Sleep 500ms

# Open file finder — welcome cheat sheet visible
Alt+o
Sleep 2s

# Type to filter — preview updates, cheat sheet disappears
Type@150ms "main"
Sleep 1.5s

# Navigate and see bat preview
Down
Sleep 1s

# Open file in popup editor
Enter
Sleep 1.5s
Type ":q"
Enter
Sleep 1s
Escape
Sleep 500ms

Hide
Type "exit"
Enter
Sleep 300ms
Type "tmux -L demo-vhs kill-server 2>/dev/null; rm -rf /tmp/demo-project /tmp/demo-dirs /tmp/demo-zoxide"
Enter
