# VHS recording: Bookmarks
Output docs/assets/bookmarks.gif
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

# Open file finder — bookmarked file (star) visible at top
Alt+o
Sleep 2s

# Navigate to a non-bookmarked file
Down
Down
Sleep 1s

# Bookmark it with Ctrl+B — star appears
Ctrl+b
Sleep 1.5s

# It reloads with star indicator
Sleep 1s

# Unbookmark with Ctrl+B
Ctrl+b
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
