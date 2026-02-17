# VHS recording: Session Picker mode
Output docs/assets/sessions.gif
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

# Open session picker directly
Alt+w
Sleep 2s

# Navigate sessions — see preview grid
Down
Sleep 2s
Down
Sleep 1.5s

# Close
Escape
Sleep 500ms

Hide
Type "exit"
Enter
Sleep 300ms
Type "tmux -L demo-vhs kill-server 2>/dev/null; rm -rf /tmp/demo-project /tmp/demo-dirs /tmp/demo-zoxide"
Enter
