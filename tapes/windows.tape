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

# Open session picker — api-server is first (alphabetical), press Ctrl+W
Alt+w
Sleep 1.5s
Ctrl+w
Sleep 1.5s

# 2D grid navigation: Right moves within row, Down jumps to next row
Right
Sleep 1.5s
Down
Sleep 1.5s
Left
Sleep 1.5s
Up
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
