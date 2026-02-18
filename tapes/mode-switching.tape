# VHS recording: Mode Switching
Output docs/assets/mode-switching.gif
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

# Start in files mode
Alt+o
Sleep 1.5s

# Switch to grep with > prefix
Type@150ms ">Hello"
Sleep 1.5s

# Backspace to return home (clear query first)
Backspace
Backspace
Backspace
Backspace
Backspace
Sleep 500ms
Backspace
Sleep 1s

# Switch to sessions with @
Type "@"
Sleep 1.5s

# Backspace to return home
Backspace
Sleep 1s

# Switch to git with !
Type "!"
Sleep 1.5s

# Backspace to return home
Backspace
Sleep 1s

# Switch to scrollback with $
Type "$"
Sleep 1.5s

# Backspace to return home
Backspace
Sleep 1s

# Switch to commands with :
Type ":"
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
