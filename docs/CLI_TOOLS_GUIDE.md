# AI CLI Tools Suite - Complete Guide

## Overview

The AI Docker CLI Manager now automatically installs and manages a comprehensive suite of AI command-line tools, providing a unified environment for AI development and interaction.

## Installed Tools

### Core AI Tools

| Tool | Command | Description | Documentation |
|------|---------|-------------|---------------|
| **Claude Code CLI** | `claude` | Anthropic's official CLI for Claude AI | [Claude Docs](https://docs.anthropic.com) |
| **GitHub CLI** | `gh` | GitHub's official command line tool | [GitHub CLI](https://cli.github.com) |
| **Shell GPT** | `sgpt` | OpenAI GPT in your terminal | [Shell-GPT](https://github.com/TheR1D/shell_gpt) |
| **Aider** | `aider` | AI pair programming tool | [Aider](https://aider.chat) |
| **Codeium** | `codeium` | Free AI code completion | [Codeium](https://codeium.com) |

### Cloud Provider CLIs

| Tool | Command | Description | Use Case |
|------|---------|-------------|----------|
| **AWS CLI** | `aws` | Amazon Web Services CLI | Access to Bedrock, SageMaker |
| **Azure CLI** | `az` | Microsoft Azure CLI | Azure OpenAI, Cognitive Services |
| **Google Cloud CLI** | `gcloud` | Google Cloud Platform CLI | Vertex AI, PaLM API |

### Development Tools

| Tool | Command | Description |
|------|---------|-------------|
| **jq** | `jq` | JSON processor |
| **HTTPie** | `http` | Modern HTTP client |
| **bat** | `bat` | Cat with syntax highlighting |
| **ripgrep** | `rg` | Fast recursive grep |
| **fd** | `fd` | Modern find replacement |
| **fzf** | `fzf` | Fuzzy finder |
| **tldr** | `tldr` | Simplified man pages |

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
   - Google Gemini API key
   - AWS credentials
   - Azure credentials
   - Google Cloud credentials

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
| `update-tools` | Update all CLI tools |
| `check-updates` | Check for available updates |
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

# Use Shell-GPT
sgpt "Write a bash script to backup files"

# Use with code generation
sgpt --code "Python function to sort a list"
```

### Aider (AI Pair Programming)

```bash
# Start aider in your project
cd /workspace/my-project
aider

# Specify files to work with
aider file1.py file2.js

# Use with specific model
aider --model gpt-4
```

### Gemini CLI

```bash
# Set API key
export GEMINI_API_KEY="your-key-here"

# Use Gemini
gemini "Explain quantum computing"
```

### AWS CLI for AI Services

```bash
# Configure AWS
aws configure

# Use Amazon Bedrock
aws bedrock list-foundation-models

# Use SageMaker
aws sagemaker list-endpoints
```

### Azure CLI for AI Services

```bash
# Login to Azure
az login

# Use Azure OpenAI
az cognitiveservices account list
```

## Auto-Update System

The system automatically checks for updates weekly. You can also manually trigger updates:

### Manual Update

```bash
# Check for updates
check-updates

# Apply updates
update-tools
```

### Update Schedule

- Automatic checks: Weekly (Sunday 2 AM)
- Update types:
  - npm packages (Claude, Continue, tldr)
  - Python packages (OpenAI, Shell-GPT, Aider)
  - System packages (GitHub CLI, AWS CLI, Azure CLI)

### Customize Update Schedule

```bash
# Change update interval (days)
export UPDATE_INTERVAL_DAYS=3

# Disable auto-updates
crontab -e
# Comment out the auto_update.sh line
```

## Environment Variables

The following environment variables are automatically configured:

| Variable | Description | Set By |
|----------|-------------|--------|
| `OPENAI_API_KEY` | OpenAI API key | configure-tools |
| `GEMINI_API_KEY` | Google Gemini API key | configure-tools |
| `PATH` | Includes ~/.local/bin | .bashrc |

## File Locations

| Type | Location | Purpose |
|------|----------|---------|
| CLI configs | `/home/$USER/.config/` | Tool configurations |
| API keys | `/home/$USER/.config/{tool}/` | Secure key storage |
| Installation marker | `/home/$USER/.cli_tools_installed` | Installation status |
| Version tracking | `/home/$USER/.cli_tools_versions` | Installed versions |
| Update logs | `/home/$USER/.cli_tools_update.log` | Update history |

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
   cat ~/.cli_tools_update.log
   ```

2. Manual update:
   ```bash
   update-tools --force
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
   - Use the right tool for the task
   - Claude for complex coding tasks
   - Shell-GPT for quick commands
   - Aider for iterative development

4. **Resource Management:**
   - Monitor API usage
   - Set rate limits where possible
   - Use local models when appropriate

## Advanced Usage

### Combining Tools

```bash
# Use GitHub CLI with Claude
gh issue list | claude "Summarize these issues"

# Use jq with API responses
aws bedrock list-models | jq '.models[].name'

# Pipe through multiple tools
fd "*.py" | xargs rg "TODO" | claude "Create tasks from these TODOs"
```

### Custom Aliases

Add to your `.bashrc`:

```bash
# Quick AI commands
alias ai-commit="sgpt 'Write a git commit message for these changes' && git diff"
alias ai-explain="claude 'Explain this code:' && cat"
alias ai-review="aider --read-only"
```

### Scripting with AI Tools

```bash
#!/bin/bash
# AI-assisted script example

# Get AI help for command
CMD=$(sgpt --code "Command to find large files")
eval $CMD

# Process with Claude
claude "Analyze these results and suggest cleanup"
```

## Support and Resources

- **Documentation:** `/workspace/ai-docker-cli-setup/docs/`
- **Issues:** Report at GitHub repository
- **Updates:** Check release notes in update logs

## Version Information

To check installed versions:

```bash
# All versions
cat ~/.cli_tools_versions

# Individual tools
claude --version
gh --version
sgpt --version
aws --version
az --version
gcloud --version
```

## Security Notes

- All API keys are stored locally in your container
- Keys are never transmitted except to their respective services
- Container isolation protects your host system
- Regular updates include security patches

---

*Last Updated: November 2024*
*AI Docker CLI Manager v2.0*