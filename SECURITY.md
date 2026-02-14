# Security Policy

## Scope

tmux-dispatch executes external commands (`fd`, `rg`, `bat`, editors) and processes file paths and search results. Security issues could include command injection via crafted filenames or unexpected shell expansion.

## Reporting a Vulnerability

If you discover a security vulnerability:

1. **Do not** open a public GitHub issue
2. Use [GitHub's private vulnerability reporting](https://github.com/ZviBaratz/tmux-dispatch/security/advisories/new)
3. Include: description, steps to reproduce, and potential impact
4. You will receive a response within 7 days

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |
| < 1.0   | No        |
