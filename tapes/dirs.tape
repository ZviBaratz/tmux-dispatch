# VHS recording: Directory Jump mode
Output docs/assets/dirs.gif
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

# Open file finder then switch to dirs via # prefix
Alt+o
Sleep 1s
Type "#"
Sleep 1s

# Filter directories
Type@150ms "src"
Sleep 1s

# Select to cd
Enter
Sleep 500ms

Hide
Type "exit"
Enter
Sleep 300ms
Type "tmux -L demo-vhs kill-server 2>/dev/null; rm -rf /tmp/demo-project"
Enter
