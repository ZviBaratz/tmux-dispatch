# VHS recording script for tmux-fzf-finder demo
# Run with: vhs demo.tape
# Produces: demo.gif

Output demo.gif
Set Shell bash
Set FontSize 14
Set Width 1200
Set Height 700
Set Padding 10

# Start tmux with the plugin loaded
Type "tmux new-session -d -s demo -c /tmp/demo-project && tmux send-keys -t demo 'clear' Enter && tmux attach -t demo"
Enter
Sleep 2s

# Create sample project files
Type "mkdir -p src tests docs && echo 'hello world' > src/main.sh && echo 'function greet() { return 42; }' > src/utils.sh && echo '# README' > docs/guide.md && echo 'test case' > tests/test.sh && clear"
Enter
Sleep 1s

# Open file finder with Alt+F
Type@100ms ""
Alt+f
Sleep 2s

# Type a partial filename to filter
Type@150ms "main"
Sleep 1.5s

# Switch to grep mode with Ctrl+G
Ctrl+g
Sleep 1.5s

# Search for content
Type@150ms "hello"
Sleep 2s

# Press Escape to close
Escape
Sleep 1s

# Clean up
Type "tmux kill-session -t demo 2>/dev/null; exit"
Enter
