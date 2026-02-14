# VHS recording script for tmux-dispatch demo
# Run with: vhs demo.tape
# Produces: demo.gif
# Requires: vhs (https://github.com/charmbracelet/vhs), tmux, fzf, fd, bat, rg

Output demo.gif
Set Shell bash
Set FontSize 14
Set Width 1200
Set Height 700
Set Padding 10

# Set up a sample project and start tmux with the plugin loaded
Type "mkdir -p /tmp/demo-project/src /tmp/demo-project/tests /tmp/demo-project/docs"
Enter
Sleep 500ms
Type "echo 'hello world' > /tmp/demo-project/src/main.sh && echo 'function greet() { return 42; }' > /tmp/demo-project/src/utils.sh && echo '# Project Guide' > /tmp/demo-project/docs/guide.md && echo 'test case' > /tmp/demo-project/tests/test.sh"
Enter
Sleep 500ms

# Start tmux session and load the plugin
Type "cd /tmp/demo-project && tmux new-session -d -s demo"
Enter
Sleep 500ms
Type "tmux run-shell $PWD/dispatch.tmux && tmux attach -t demo"
Enter
Sleep 1.5s
Type "clear"
Enter
Sleep 1s

# Open file finder with Alt+O
Alt+o
Sleep 2s

# Type a partial filename to filter
Type@150ms "main"
Sleep 1.5s

# Switch to grep mode with Ctrl+G
Ctrl+g
Sleep 2s

# Search for content
Type@150ms "hello"
Sleep 2s

# Press Escape to close
Escape
Sleep 1s

# Clean up
Type "exit"
Enter
Sleep 500ms
Type "tmux kill-session -t demo 2>/dev/null; rm -rf /tmp/demo-project"
Enter
