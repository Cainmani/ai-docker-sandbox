# AI Docker CLI Manager - Complete AI Tools Environment

A production-ready system for running multiple AI Command Line Interface tools (Claude, GitHub CLI, OpenAI/GPT, Gemini, AWS, Azure) in a secure Docker container with automatic installation and updates.

## 📚 Documentation

**For End Users:**
- **[docs/USER_MANUAL.md](docs/USER_MANUAL.md)** - Complete user guide for non-technical users (👈 START HERE)
- **[docs/CLI_TOOLS_GUIDE.md](docs/CLI_TOOLS_GUIDE.md)** - Complete guide to all AI CLI tools
- **[docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** - One-page cheatsheet for quick reference

**For Developers:**
- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** - Technical documentation and development guide
- **[docs/CLAUDE.md](docs/CLAUDE.md)** - Claude AI context file (for resuming work)
- **README.md** (this file) - Project overview and architecture reference

**For Testing:**
- **[tests/TESTING_CHECKLIST.md](tests/TESTING_CHECKLIST.md)** - Comprehensive QA testing guide
- **[tests/TESTING_WALKTHROUGH.md](tests/TESTING_WALKTHROUGH.md)** - Step-by-step testing procedures

**For Troubleshooting:**
- **[docs/LOGGING.md](docs/LOGGING.md)** - Production logging system documentation and troubleshooting guide

## Overview

This project provides a complete AI development environment with multiple AI CLI tools automatically installed and managed in a secure Docker container. All major AI services (Claude, OpenAI/GPT, Google Gemini, GitHub Copilot, AWS Bedrock, Azure AI) are pre-installed and ready to use with a simple configuration wizard.

## 🚀 New Features (v2.0)

- 🤖 **Multiple AI Tools** - Claude, GitHub CLI, OpenAI/GPT, Gemini, AWS, Azure, and more
- 🔄 **Auto-Installation** - All tools install automatically on first run
- 🔐 **Easy Configuration** - Interactive wizard for API keys and authentication
- 📦 **Auto-Updates** - Weekly automatic updates for all CLI tools
- 🛠️ **Development Tools** - Includes jq, httpie, bat, ripgrep, fd, fzf, and more

## Core Features

- ✅ **One-Click Setup Wizard** - Automated installation with GUI
- ✅ **Complete AI Suite** - All major AI CLI tools pre-installed
- ✅ **Self-Contained Application** - All config stored in AppData, .exe can be anywhere
- ✅ **Secure Isolation** - AI runs in Docker container, can't access system files
- ✅ **User-Friendly Launcher** - Quick daily access to workspace
- ✅ **Persistent Storage** - All files accessible from Windows
- ✅ **Automatic Management** - Container auto-starts when needed
- ✅ **Professional UX** - Matrix-themed GUI with progress feedback
- ✅ **Production Logging** - Comprehensive centralized logging for troubleshooting
- ✅ **User-Ready** - No command-line knowledge required
- ✅ **Clean Experience** - No scattered files or folders on your desktop

## Quick Start

### Prerequisites

- Windows 10/11 (64-bit)
- Docker Desktop ([Download here](https://docs.docker.com/desktop/setup/install/windows-install/))
- 4GB RAM minimum, 8GB recommended

### Installation (One-Time Setup)

1. **Download and run `AI_Docker_Manager.exe`** (or build from source)

2. **Select "First Time Setup"** from the menu

3. **Follow the interactive wizard:**
   - Enter username/password for container
   - Select location for AI_Work directory
   - Wait for Docker build (2-5 minutes)
   - Wait for CLI tools installation (3-5 minutes)
   - Complete!

**Total time:** 8-15 minutes (first run includes all tools installation)

### Daily Use

1. **Run `AI_Docker_Manager.exe`**
2. **Select "Launch AI Workspace"**
3. **Terminal opens** → All AI tools ready!

### First Time Configuration

After setup, configure your AI tools:
```bash
# Run the configuration wizard
configure-tools

# Or configure individual tools
configure-tools --claude   # Configure Claude
configure-tools --github   # Configure GitHub CLI
configure-tools --openai   # Configure OpenAI/GPT
```

### Available Commands

```bash
# AI Tools
claude          # Claude Code CLI
gh              # GitHub CLI
sgpt            # Shell GPT (OpenAI)
aider           # AI pair programming
codeium         # Codeium AI assistant

# Management
update-tools    # Update all CLI tools
config-status   # Check configuration status
```

## Project Structure

**Note**: All configuration is stored in Windows AppData, making this a true self-contained application. The .exe can be placed anywhere on your system.

### Directory Organization

```
ai-docker-cli-setup/
├── README.md                          # Main project documentation
├── .gitattributes                     # Git line ending configuration
├── AI_Docker_Manager.exe              # Compiled executable (172KB)
│
├── docs/                              # 📚 All Documentation
│   ├── USER_MANUAL.md                 # Complete user guide (end users)
│   ├── QUICK_REFERENCE.md             # One-page cheatsheet
│   ├── DEVELOPMENT.md                 # Developer documentation
│   └── CLAUDE.md                      # Claude AI context file
│
├── scripts/                           # 🔧 PowerShell Scripts & Go Source
│   ├── main.go                        # Main Go application
│   ├── docker_manager.go              # Docker operations module
│   ├── go.mod                         # Go dependencies
│   └── build.ps1                      # Build script
│
├── tests/                            # ✅ Testing Infrastructure
│   ├── TESTING_CHECKLIST.md          # Detailed QA checklist
│   ├── TESTING_WALKTHROUGH.md        # Step-by-step testing guide
│   └── TESTING_SESSION.md            # Live testing session template
│
└── docker/                           # 🐳 Docker Configuration
    ├── docker-compose.yml            # Container orchestration
    ├── Dockerfile                    # Image build instructions (multi-stage)
    └── entrypoint.sh                 # Container initialization script
```

### What Gets Installed

When you run the executable for the first time:

```
C:\your\chosen\path\
└── AI_Work/                          # Your workspace (mounted in container)
    ├── project-1/                    # Individual AI project
    ├── project-2/                    # Each has isolated context
    └── project-n/

C:\Users\<YourName>\AppData\Local\AI_Docker_Manager\  # App configuration (auto-created)
└── .env                              # Generated credentials
```

### File Statistics

- **Total Project Files**: ~15 core files
- **Documentation**: 4 user-facing files (docs/)
- **Scripts**: 4 files (Go source + build script)
- **Tests**: 3 testing documents (tests/)
- **Docker**: 3 configuration files (docker/)
- **Compiled Size**: AI_Docker_Manager.exe (~172KB)

## Architecture

### Technology Stack

**AI_Docker_Manager.exe (Go Application)**
- Built with Go 1.21+ using Bubble Tea TUI framework
- Interactive menu system with styled components
- Docker integration via Docker SDK
- Manages complete container lifecycle
- Automatic Docker Desktop detection and startup
- ~172KB compiled executable

**Container (ai-cli)**
- Ubuntu 24.04 base with comprehensive development tools
- **AI CLI Tools**: Claude, GitHub CLI, OpenAI/GPT, Gemini, Codeium, Aider
- **Cloud CLIs**: AWS, Azure, Google Cloud
- **Dev Tools**: Node.js, Python 3, Git, jq, httpie, bat, ripgrep, fd, fzf
- Auto-installation of all tools on first run
- Weekly auto-updates for all CLI tools
- User account with passwordless sudo access
- /workspace mounted from Windows AI_Work folder
- Named volumes for persistent configurations

### Container Lifecycle

**First Time Setup:**
1. User provides credentials and workspace location
2. Creates `.env` file with configuration
3. Builds Docker image with all dependencies
4. Creates container with volume mounts
5. Auto-installs all AI CLI tools (3-5 minutes)
   - Claude, GitHub CLI, OpenAI tools, Gemini
   - AWS CLI, Azure CLI, Google Cloud CLI
   - Development tools and utilities
6. Sets up auto-update cron job
7. Validates installation

**Daily Launch:**
1. Checks Docker Desktop is running (auto-starts if needed)
2. Verifies container exists
3. Starts container if stopped
4. Opens interactive terminal at /workspace

### Security

- **Isolated Environment** - AI cannot access Windows files outside AI_Work
- **Container Isolation** - Separate Linux environment from host
- **User Permissions** - AI runs as non-root user
- **Controlled Access** - Only AI_Work directory is mounted

## Usage Guide

### Creating a New Project

```bash
# Inside the container terminal
cd /workspace
mkdir my-new-project
cd my-new-project

# Start working with Claude
claude
```

### Working with Claude

```bash
# Check Claude version
claude --version

# Run Claude in current directory
claude

# Claude will have context of files in current directory
# Each project directory maintains isolated AI context
```

### Accessing Files from Windows

Your AI_Work folder is accessible from Windows File Explorer:
- All files created in /workspace appear in AI_Work
- You can edit files with your favorite Windows editors
- Changes sync automatically to the container

### Daily Workflow

1. **Morning:** Run AI_Docker_Manager.exe → Select "Launch AI Workspace"
2. **Work:** Navigate to project, run `claude`
3. **Evening:** Exit terminal (files persist)
4. **Next day:** Run launcher again → Resume work

## Troubleshooting

### "Docker is not running"
**Solution:** The application will automatically attempt to start Docker Desktop. Wait 1-2 minutes for Docker to fully start, then try again.

### "Container does not exist"
**Solution:** Run "First Time Setup" from AI_Docker_Manager.exe menu.

### "claude: command not found"
**Solution:** Container setup incomplete. Remove and recreate:
1. Run AI_Docker_Manager.exe
2. Select "Remove Container"
3. Select "First Time Setup" again

### Container won't start
**Solution:** Check Docker Desktop is running. View container logs:
```bash
docker logs ai-cli
```

### Permission errors in container
**Solution:** The entrypoint script should handle permissions automatically. If issues persist, rebuild the container.

## Advanced

### DEV Mode (UI Testing)

DEV mode allows developers to walk through the entire setup wizard UI without performing any destructive operations. This is useful for UI testing and aesthetic fixes.

**How to Activate:**
- **From Launcher:** Hold `Shift` while clicking "First Time Setup"
- **Direct script:** `powershell -ExecutionPolicy Bypass -File "setup_wizard.ps1" -DevMode`

**Visual Indicators:**
- Form title changes to `>>> AI CLI DOCKER SETUP :: [DEV MODE] <<<`
- Orange banner at top: "DEV MODE - No destructive operations will be performed"
- Console shows magenta `[DEV MODE]` messages for all simulated operations

**What Gets Simulated (not executed):**
| Operation | DEV Mode Behavior |
|-----------|-------------------|
| Container stop/remove | Logged & skipped |
| Image removal | Logged & skipped |
| `docker compose build` | Progress animation only |
| `docker compose up -d` | Progress animation only |
| Container status checks | Returns simulated "Up" |
| CLI tools installation | Quick simulated progress |
| Tool verification | Simulated as found |

### Manual Container Management

```powershell
# Check container status
docker ps -a --filter "name=ai-cli"

# Start container manually
docker start ai-cli

# Stop container manually
docker stop ai-cli

# View container logs
docker logs ai-cli

# Access container as root
docker exec -it ai-cli bash

# Access container as your user
docker exec -it -u yourusername ai-cli bash
```

### Rebuild Container

If you need to completely rebuild:

```bash
# Stop and remove container
docker stop ai-cli
docker rm ai-cli

# Remove image
docker rmi ai-docker-ai

# Run First Time Setup again from AI_Docker_Manager.exe
```

### Environment Variables

Configuration is stored in `%LOCALAPPDATA%\AI_Docker_Manager\.env`:
```env
USER_NAME=your-username
USER_PASSWORD=your-password
WORKSPACE_PATH=C:\path\to\AI_Work
```

**Security Note:** This file contains container credentials (not your Windows password)

### Building from Source

**Prerequisites:**
- Go 1.21+ installed
- Git

**Build steps:**
```bash
cd scripts
go build -o ../AI_Docker_Manager.exe .
```

Or use the PowerShell build script:
```powershell
cd scripts
.\build.ps1
```

### Customization

**Add more tools to container:** Edit `docker/Dockerfile` to install additional packages

**Change container settings:** Edit `docker/docker-compose.yml`

**Modify user setup:** Edit `docker/entrypoint.sh`

## System Requirements

- **OS:** Windows 10/11 (64-bit)
- **RAM:** 4GB minimum, 8GB recommended
- **Disk:** 10GB free space for Docker images
- **Docker:** Docker Desktop 4.0+

## Development & Contributing

### Technology Choices

**Why Go?**
- Single compiled binary (~172KB)
- Excellent Docker SDK support
- Cross-platform compatibility
- Fast execution and low resource usage

**Why Bubble Tea TUI?**
- Modern, reactive terminal UI framework
- Excellent keyboard navigation
- Clean component model
- Professional appearance

**Why Docker?**
- Complete isolation from host system
- Reproducible environment
- Easy to update and maintain
- Industry standard for containerization

### Contributing

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for:
- Development setup
- Code structure
- Testing procedures
- Contribution guidelines

## Future Enhancements

Potential additions:
- Support for additional AI CLIs
- Project template system
- Settings management UI
- Automatic Claude updates
- Backup/restore functionality
- Linux/macOS support

## Support & Verification

### Check Installation

```bash
# Verify Docker
docker --version

# Verify container exists
docker ps -a --filter "name=ai-cli"

# Verify Claude installed
docker exec ai-cli claude --version
```

### Clean Reinstall

```bash
# Remove everything
docker stop ai-cli
docker rm ai-cli
docker rmi ai-docker-ai

# Remove configuration
# Delete: %LOCALAPPDATA%\AI_Docker_Manager\.env

# Start fresh - Run AI_Docker_Manager.exe
# Select "First Time Setup"
```

## Troubleshooting

The application includes comprehensive production-level logging to help diagnose issues.

### Log File Location

All operations are logged to:
```
%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log
```

### Quick Access to Logs

```powershell
# View entire log file
notepad %LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log

# View last 50 lines
Get-Content "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Tail 50

# Find errors
Select-String -Path "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Pattern "\[ERROR\]"

# Watch logs in real-time
Get-Content "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Wait -Tail 20
```

### What Gets Logged

- Path detection and resolution
- Docker operations and status checks
- Container management operations
- User actions and button clicks
- File operations (.env reading, auth sync)
- Error conditions with full details

### Common Issues

**Issue**: "Cannot bind argument to parameter 'Path'" error
- **Solution**: Check logs for exact path values and types
- **Log entries**: Look for `scriptPath value:` and `scriptPath type:` entries

**Issue**: Container won't start
- **Solution**: Check logs for Docker status checks
- **Log entries**: Look for `Docker is running and responding` or error messages

**Issue**: Setup wizard fails
- **Solution**: Review log file for exit codes and error messages
- **Log entries**: Look for `Setup wizard process completed with exit code:`

For detailed troubleshooting guidance, see [docs/LOGGING.md](docs/LOGGING.md).

### Getting Help

- **User Manual:** [docs/USER_MANUAL.md](docs/USER_MANUAL.md)
- **Quick Reference:** [docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)
- **Logging Guide:** [docs/LOGGING.md](docs/LOGGING.md)
- **Issues:** Report bugs or request features on GitHub (include log file excerpts)

## License

This project is provided as-is for use in setting up secure AI development environments.

## Credits

Built with ❤️ for secure, user-friendly AI development environments.

**Technologies:**
- Go & Bubble Tea (TUI framework)
- Docker & Docker Compose
- Claude Code CLI by Anthropic

---

## Quick Reference Card

**First Time:**
1. Run `AI_Docker_Manager.exe`
2. Select "First Time Setup"
3. Follow the wizard

**Daily Use:**
1. Run `AI_Docker_Manager.exe`
2. Select "Launch Claude CLI"
3. Work in `/workspace`

**Inside Container:**
```bash
cd /workspace/your-project
claude
```

**That's it!** Everything else is automatic. 🚀

