#!/bin/bash
# Wrapper for Claude Code CLI
exec node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js "$@"

