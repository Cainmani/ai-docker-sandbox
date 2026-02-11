#!/bin/bash
# Wrapper for Claude Code CLI
# Delegates to native installer location; falls back to npm global.
# The native installer (https://claude.ai/install.sh) places claude at ~/.local/bin/claude
if [ -x "${HOME}/.local/bin/claude" ]; then
    exec "${HOME}/.local/bin/claude" "$@"
elif [ -x "${HOME}/.local/share/claude/local/claude" ]; then
    exec "${HOME}/.local/share/claude/local/claude" "$@"
elif [ -f "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js" ]; then
    exec node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js "$@"
else
    echo "Claude Code is not installed. Run: curl -fsSL https://claude.ai/install.sh | sh" >&2
    exit 1
fi
