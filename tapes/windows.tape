# VHS recording: Window Picker mode
Output docs/assets/windows.gif
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

# Open session picker, navigate to api-server, then Ctrl+W for windows
Alt+w
Sleep 1.5s
Down
Sleep 1s
Ctrl+w
Sleep 2s

# Navigate windows
Down
Sleep 1.5s

# Close
Escape
Sleep 500ms

Hide
Type "exit"
Enter
Sleep 300ms
Type "tmux -L demo-vhs kill-server 2>/dev/null; rm -rf /tmp/demo-project"
Enter
