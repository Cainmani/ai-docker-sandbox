# AI CLI Tools Suite - Complete Guide

## Overview

The AI Docker CLI Manager automatically installs and manages a suite of AI command-line tools, providing a unified environment for AI development and interaction.

## Installed Tools

### Core AI Tools

| Tool | Command | Description | Documentation |
|------|---------|-------------|---------------|
| **Claude Code CLI** | `claude` | Anthropic's official CLI for Claude AI | [Claude Docs](https://docs.anthropic.com) |
| **GitHub CLI** | `gh` | GitHub's official command line tool | [GitHub CLI](https://cli.github.com) |
| **OpenAI Codex CLI** | `codex` | OpenAI's coding assistant CLI | [Codex CLI](https://github.com/openai/codex) |
| **OpenAI SDK** | `python3 -c "import openai"` | OpenAI Python SDK | [OpenAI Python](https://github.com/openai/openai-python) |
| **Google Gemini CLI** | `gemini` | Google's AI assistant CLI | [Gemini CLI](https://github.com/google-gemini/gemini-cli) |
| **Vibe Kanban** | `vibe-kanban` | Orchestrate AI agents in parallel via web UI | [Vibe Kanban](https://vibekanban.com) |

## Quick Start

### First Time Setup

1. **Launch the environment:**
   ```bash
   # Run from Windows
   launch_claude.ps1
   ```

2. **Configure your tools:**
   ```bash
   # In the container terminal
   configure-tools
   ```

3. **Follow the interactive wizard to set up:**
   - Claude API key
   - GitHub authentication
   - OpenAI API key
   - OpenAI Codex CLI
   - Google Gemini API key

### Configuration Commands

| Command | Description |
|---------|-------------|
| `configure-tools` | Interactive configuration wizard |
| `configure-tools --status` | Check configuration status |
| `configure-tools --claude` | Configure Claude only |
| `configure-tools --github` | Configure GitHub CLI only |
| `configure-tools --openai` | Configure OpenAI tools |
| `configure-tools --all` | Configure all tools at once |

### Management Commands

| Command | Description |
|---------|-------------|
| `update-container-tools` | Update all CLI tools in container |
| `check-container-updates` | Check for available updates |
| `config-status` | View configuration status |

## Tool-Specific Configuration

### Claude Code CLI

```bash
# First time authentication
claude auth login

# Start using Claude
claude chat "Help me write a Python script"
```

### GitHub CLI

```bash
# Authenticate with GitHub
gh auth login

# Check authentication status
gh auth status

# Common operations
gh repo list
gh issue list
gh pr create
```

### OpenAI/GPT Tools

```bash
# Set API key (done via configure-tools)
export OPENAI_API_KEY="your-key-here"

# Use OpenAI Python SDK
python3 -c "from openai import OpenAI; client = OpenAI(); print('Connected!')"
```

### OpenAI Codex CLI

```bash
# Authenticate with OpenAI
codex auth

# Start coding with Codex
codex "Write a Python function to sort a list"
```

### Gemini CLI

```bash
# Set API key
export GEMINI_API_KEY="your-key-here"

# Use Gemini
gemini "Explain quantum computing"
```

### Vibe Kanban (AI Agent Orchestration)

Vibe Kanban is a web-based tool that lets you orchestrate multiple AI coding agents in parallel through a visual kanban interface.

**Launch from Windows GUI:**
1. Click "3. LAUNCH VIBE KANBAN" in the AI Docker Manager
2. Browser automatically opens to `http://localhost:3000`

**Launch from Terminal:**
```bash
# Start Vibe Kanban server (inside container)
HOST=0.0.0.0 PORT=3000 vibe-kanban

# Then open http://localhost:3000 in your Windows browser
```

**Supported Agents:**
- Claude Code (claude)
- OpenAI Codex (codex)
- Gemini CLI (gemini)
- GitHub CLI (gh)

## Auto-Update System

The system automatically checks for updates weekly. You can also manually trigger updates:

### Manual Update

```bash
# Check for updates
check-container-updates

# Apply updates
update-container-tools
```

### Update Schedule

- Automatic checks: Weekly (Sunday 2 AM)
- Update types:
  - npm packages (Gemini CLI, Codex CLI, Vibe Kanban)
  - Python packages (OpenAI SDK)
  - System packages (GitHub CLI)

### Customize Update Schedule

```bash
# Change update interval (days)
export UPDATE_INTERVAL_DAYS=3

# Force update check regardless of interval
update-container-tools --force
```

## Environment Variables

The following environment variables are automatically configured:

| Variable | Description | Set By |
|----------|-------------|--------|
| `OPENAI_API_KEY` | OpenAI API key | configure-tools |
| `GEMINI_API_KEY` | Google Gemini API key | configure-tools |
| `PATH` | Includes ~/.local/bin and ~/.npm-global/bin | .bashrc |

## File Locations

| Type | Location | Purpose |
|------|----------|---------|
| CLI configs | `/home/$USER/.config/` | Tool configurations |
| API keys | `/home/$USER/.config/{tool}/` | Secure key storage |
| Installation marker | `/home/$USER/.cli_tools_installed` | Installation status |
| Version tracking | `/home/$USER/.cli_tools_versions` | Installed versions |
| Update logs | `/workspace/.ai-docker-cli/logs/update.log` | Update history |

## Troubleshooting

### Tool Not Found

If a tool command is not found:

1. Check installation status:
   ```bash
   config-status
   ```

2. Force reinstall:
   ```bash
   /usr/local/bin/install_cli_tools.sh --force
   ```

### Authentication Issues

For authentication problems:

1. Re-run configuration:
   ```bash
   configure-tools --[tool-name]
   ```

2. Check API key:
   ```bash
   echo $OPENAI_API_KEY  # Example for OpenAI
   ```

### Update Failures

If updates fail:

1. Check logs:
   ```bash
   cat /workspace/.ai-docker-cli/logs/update.log
   ```

2. Manual update:
   ```bash
   update-container-tools --force
   ```

### Network Issues

For tools requiring internet:

1. Check connectivity:
   ```bash
   curl -I https://api.github.com
   ```

2. Check DNS:
   ```bash
   nslookup api.openai.com
   ```

## Best Practices

1. **API Key Security:**
   - Never commit API keys to git
   - Use environment variables
   - Keys are stored securely in ~/.config/

2. **Regular Updates:**
   - Let auto-updates run weekly
   - Check for updates before major projects
   - Review update logs periodically

3. **Tool Selection:**
   - Use Claude for complex coding tasks
   - Use Codex for quick code generation
   - Use Gemini for general AI queries

4. **Resource Management:**
   - Monitor API usage
   - Set rate limits where possible

## Advanced Usage

### Combining Tools

```bash
# Use GitHub CLI with Claude
gh issue list | claude "Summarize these issues"

# Pipe commands through AI tools
cat error.log | claude "Analyze these errors and suggest fixes"
```

### Custom Aliases

Add to your `.bashrc`:

```bash
# Quick AI commands
alias ai-commit="claude 'Write a git commit message for these changes:' && git diff"
alias ai-explain="claude 'Explain this code:'"
```

## Support and Resources

- **Documentation:** `/workspace/ai-docker-sandbox/docs/`
- **Issues:** Report at GitHub repository
- **Updates:** Check release notes in update logs

## Version Information

To check installed versions:

```bash
# Individual tools
claude --version
gh --version
codex --version
gemini --version
```

## Security Notes

- All API keys are stored locally in your container
- Keys are never transmitted except to their respective services
- Container isolation protects your host system
- Regular updates include security patches

---

*Last Updated: February 2026*
*AI Docker CLI Manager v2.1*
