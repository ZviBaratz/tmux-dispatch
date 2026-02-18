# VHS recording: Scrollback Search mode
Output docs/assets/scrollback.gif
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

# Run some commands so the scrollback has content
Type "echo 'Hello, world!'"
Enter
Sleep 300ms
Type "ls -la src/"
Enter
Sleep 300ms
Type "cat VERSION"
Enter
Sleep 300ms
Type "echo 'deploy complete — v1.2.0'"
Enter
Sleep 300ms
Type "git log --oneline"
Enter
Sleep 500ms
Type "clear"
Enter
Sleep 500ms
Show

Sleep 500ms

# Open file finder then switch to scrollback via $ prefix
Alt+o
Sleep 1s
Type@150ms "$deploy"
Sleep 2s

# Navigate results — context preview
Down
Sleep 1.5s

# Copy selected line
Enter
Sleep 1s

Hide
Type "exit"
Enter
Sleep 300ms
Type "tmux -L demo-vhs kill-server 2>/dev/null; rm -rf /tmp/demo-project /tmp/demo-dirs /tmp/demo-zoxide"
Enter
