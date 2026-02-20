---
layout: default
title: Path Mode
parent: Modes
nav_order: 11
---

# Path Mode

Browse files by absolute path. Type `/` in files mode to enter.

## When to Use

- You know the full path to a file but aren't in that directory
- You want to browse a system directory (e.g., `/etc/`, `/var/log/`)
- You need to open a file outside your project

## How It Works

Type `/` followed by the path. The file list updates on every keystroke,
showing files matching the directory + filter you've typed.

Examples:
- `/etc/` — list files in /etc
- `/home/user/proj` — files in directories matching "proj"
- `/var/log/sys` — files matching "sys" in /var/log

## Keybindings

| Key | Action |
|-----|--------|
| `enter` | Open in editor |
| `Ctrl+O` | Send to pane |
| `Ctrl+Y` | Copy path |
| `⌫ empty` | Back to files |
| `?` | Help overlay |
