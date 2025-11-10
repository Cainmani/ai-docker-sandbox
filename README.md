# AI Docker Setup - Secure Claude Code CLI Environment

A production-ready system for running AI Command Line Interface tools (Claude Code) in a secure Docker container, designed for non-technical users and ease of setup.

## 📚 Documentation

**For End Users:**
- **[docs/USER_MANUAL.md](docs/USER_MANUAL.md)** - Complete user guide for non-technical users (👈 START HERE)
- **[docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** - One-page cheatsheet for quick reference

**For Developers:**
- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** - Technical documentation and development guide
- **[docs/CLAUDE.md](docs/CLAUDE.md)** - Claude AI context file (for resuming work)
- **README.md** (this file) - Project overview and architecture reference

**For Testing:**
- **[tests/TESTING_CHECKLIST.md](tests/TESTING_CHECKLIST.md)** - Comprehensive QA testing guide
- **[tests/TESTING_WALKTHROUGH.md](tests/TESTING_WALKTHROUGH.md)** - Step-by-step testing procedures

## Overview

This project provides a complete, automated setup wizard and launcher for deploying Claude Code CLI in an isolated Docker environment. The AI runs in a secure Ubuntu container with controlled access to your project files, preventing unauthorized access to your Windows system.

## Features

- ✅ **One-Click Setup Wizard** - Automated installation with GUI
- ✅ **Self-Contained Application** - All config stored in AppData, .exe can be anywhere
- ✅ **Secure Isolation** - AI runs in Docker container, can't access system files
- ✅ **User-Friendly Launcher** - Quick daily access to workspace
- ✅ **Persistent Storage** - All files accessible from Windows
- ✅ **Automatic Management** - Container auto-starts when needed
- ✅ **Professional UX** - Matrix-themed GUI with progress feedback
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
   - Wait for Claude CLI installation (1-2 minutes)
   - Complete!

**Total time:** 5-10 minutes

### Daily Use

1. **Run `AI_Docker_Manager.exe`**
2. **Select "Launch Claude CLI"**
3. **Terminal opens** → You're ready to work!

Inside the container:
```bash
cd /workspace/your-project
claude
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
- Ubuntu 24.04 base
- Node.js 20.x, npm, Python 3, Git
- Claude Code CLI installed globally via npm
- User account with passwordless sudo access
- /workspace mounted from Windows AI_Work folder
- Named volume for persistent .claude configuration

### Container Lifecycle

**First Time Setup:**
1. User provides credentials and workspace location
2. Creates `.env` file with configuration
3. Builds Docker image with multi-stage build
4. Creates container with volume mounts
5. Installs Claude CLI inside container
6. Validates installation

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

1. **Morning:** Run AI_Docker_Manager.exe → Select "Launch Claude CLI"
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

### Getting Help

- **User Manual:** [docs/USER_MANUAL.md](docs/USER_MANUAL.md)
- **Quick Reference:** [docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)
- **Issues:** Report bugs or request features on GitHub

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

