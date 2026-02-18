# VHS recording: Custom Commands mode
Output docs/assets/commands.gif
Set Shell bash
Set FontSize 14
Set Width 1200
Set Height 700
Set Padding 10

Hide
Type "bash tapes/demo-setup-modes.sh && tmux -L demo-vhs attach -t demo"
Enter
Sleep 2s

# Create a sample commands.conf for the demo
Type "mkdir -p ~/.config/tmux-dispatch"
Enter
Sleep 200ms
Type "cat > ~/.config/tmux-dispatch/commands.conf << 'EOF'"
Enter
Type "# Project commands"
Enter
Type "Run tests | bash tests/test_main.sh"
Enter
Type "Deploy staging | echo 'Deploying to staging...'"
Enter
Type "Git pull all | echo 'Pulling all repos...'"
Enter
Type "Split terminal | tmux: split-window -h"
Enter
Type "Toggle mouse | tmux: set mouse"
Enter
Type "Show version | cat VERSION"
Enter
Type "EOF"
Enter
Sleep 300ms

Type "clear"
Enter
Sleep 500ms
Show

Sleep 500ms

# Open file finder then switch to commands via : prefix
Alt+o
Sleep 1s
Type@150ms ":deploy"
Sleep 2s

# Select and run the command
Enter
Sleep 1.5s

# Close
Escape
Sleep 500ms

Hide
Type "exit"
Enter
Sleep 300ms
Type "tmux -L demo-vhs kill-server 2>/dev/null; rm -rf /tmp/demo-project /tmp/demo-dirs /tmp/demo-zoxide ~/.config/tmux-dispatch/commands.conf"
Enter
