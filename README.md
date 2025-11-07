# AI Docker Setup - Secure Claude Code CLI Environment

A production-ready system for running AI Command Line Interface tools (Claude Code) in a secure Docker container, designed for non-technical users and ease of setup.

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

- Windows 10/11
- Docker Desktop ([Download here](https://docs.docker.com/desktop/setup/install/windows-install/))
- PowerShell 5.1+ (pre-installed on Windows)

### Installation (Run Once)

1. **Run the Setup Wizard:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File setup_wizard.ps1
   ```

2. **Follow the 7-page wizard:**
   - Welcome & overview
   - Enter username/password for container
   - Select parent folder for AI_Work directory
   - Verify Docker is running
   - Wait for Docker build (2-5 minutes)
   - Wait for Claude installation (1-2 minutes)
   - Complete!

**Total time:** 5-10 minutes

### Daily Use

**Run the Launcher:**
```powershell
powershell -ExecutionPolicy Bypass -File launch_claude.ps1
```

**Click "Launch Workspace Shell"** → Terminal opens at /workspace → Start working!

## What Gets Created

```
C:\your\chosen\path\
└── AI_Work/                          # Your workspace (mounted in container)
    ├── project-1/                    # Individual AI project
    ├── project-2/                    # Each has isolated context
    └── project-n/

C:\Users\<YourName>\AppData\Local\AI_Docker_Manager\  # App configuration (auto-created)
├── .env                              # Generated credentials
└── docker-files\                     # Docker configuration files
    ├── docker-compose.yml            # Container config
    ├── Dockerfile                    # Image definition
    ├── entrypoint.sh                 # Container initialization
    ├── claude_wrapper.sh             # Claude command wrapper
    ├── setup_wizard.ps1              # Extracted when needed
    └── launch_claude.ps1             # Extracted when needed
```

**Note**: All configuration is stored in Windows AppData, making this a true self-contained application. The .exe can be placed anywhere on your system.

## Architecture

### Components

**Setup Wizard (`setup_wizard.ps1`)**
- Collects user credentials
- Creates .env file
- Builds Docker image (Ubuntu 24.04 + Node.js + npm)
- Starts container
- Installs Claude Code CLI via npm
- Creates wrapper script

**Launcher (`launch_claude.ps1`)**
- Checks Docker status (auto-starts if needed)
- Checks container exists (guides to wizard if not)
- Starts container if stopped
- Opens terminal as your user at /workspace

**Container (ai-cli)**
- Ubuntu 24.04 base
- Node.js, npm, Python, Git
- Claude Code CLI installed globally
- Your user account with sudo access
- /workspace mounted from Windows AI_Work folder

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

1. **Morning:** Run launcher → Terminal opens
2. **Work:** Navigate to project, run `claude`
3. **Evening:** Exit terminal (files persist)
4. **Next day:** Run launcher again → Resume work

## Troubleshooting

### "Docker is not running"
**Solution:** Start Docker Desktop, wait for green icon, click Retry in launcher

### "Container does not exist"
**Solution:** Run setup wizard again:
```powershell
powershell -ExecutionPolicy Bypass -File setup_wizard.ps1
```

### "claude: command not found"
**Solution:** Container might not have completed setup. Rebuild:
```powershell
docker stop ai-cli
docker rm ai-cli
powershell -ExecutionPolicy Bypass -File setup_wizard.ps1
```

### Progress bar not showing in wizard
**Note:** Progress bar shows activity at the bottom of the wizard. Also watch the console window for detailed logging.

### Terminal shows "root@..." instead of your username
**Solution:** Rebuild the container - the user creation failed:
```powershell
docker stop ai-cli
docker rm ai-cli
docker compose build --no-cache
powershell -ExecutionPolicy Bypass -File setup_wizard.ps1
```

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

```powershell
# Stop and remove container
docker stop ai-cli
docker rm ai-cli

# Remove image
docker rmi ai-docker-ai

# Run wizard again
powershell -ExecutionPolicy Bypass -File setup_wizard.ps1
```

### Environment Variables

The `.env` file contains:
```
USER_NAME=your-username
USER_PASSWORD=your-password
WORKSPACE_PATH=C:\path\to\AI_Work
```

**Security Note:** Keep this file secure - it contains container credentials

### Customization

**Add more AI tools:** Edit `Dockerfile` to install additional packages

**Change container settings:** Edit `docker-compose.yml`

**Modify user setup:** Edit `entrypoint.sh`

## System Requirements

- **OS:** Windows 10/11
- **RAM:** 4GB minimum, 8GB recommended
- **Disk:** 10GB free space for Docker images
- **Docker:** Docker Desktop 4.0+
- **PowerShell:** 5.1+ (included in Windows)

## Files Reference

### Core Files (Required)

- `setup_wizard.ps1` - Initial setup automation
- `launch_claude.ps1` - Daily launcher
- `docker-compose.yml` - Container configuration
- `Dockerfile` - Image build instructions
- `entrypoint.sh` - Container startup script
- `claude_wrapper.sh` - Claude command wrapper

### Utility Files

- `.gitattributes` - Git line ending rules
- `fix_line_endings.ps1` - Converts CRLF to LF
- `rebuild.ps1` - Quick container rebuild

### Generated Files

- `.env` - User credentials (created by wizard)

## Development History

This project evolved through multiple iterations to achieve production quality:

- Navigation and console logging fixes
- Progress bar animation implementation
- Docker command execution improvements
- Container keep-alive mechanism
- Line ending handling (Windows CRLF → Unix LF)
- Full automation with pre-flight checks
- UI/UX improvements (950px wide, better spacing)
- Password confirmation for security
- Docker auto-start capability
- Proper role separation (wizard vs launcher)
- Claude wrapper script correction

## Future Enhancements

Potential additions:
- Support for additional AI CLIs (Codex, Gemini)
- Project template creation
- Settings GUI for configuration
- Automatic Claude updates
- Backup/restore functionality
- Compile to .exe for distribution

## Support

### Check Installation

```powershell
# Verify Docker
docker --version

# Verify container exists
docker ps -a --filter "name=ai-cli"

# Verify Claude installed
docker exec ai-cli claude --version
```

### Clean Reinstall

```powershell
# Remove everything
docker stop ai-cli
docker rm ai-cli
docker rmi ai-docker-ai
Remove-Item .env

# Start fresh
powershell -ExecutionPolicy Bypass -File setup_wizard.ps1
```

## License

This project is provided as-is for use in setting up secure AI development environments.

## Credits

Designed for ease of use while maintaining enterprise-grade security and isolation.

---

## EXE Distribution (Optional)

For even easier distribution, you can compile the project into a standalone executable.

### Main Launcher EXE

The `AI_Docker_Launcher.ps1` provides a central menu with two options:

**1. First Time Setup** - Runs the setup wizard (one-time)
**2. Launch Claude CLI** - Opens workspace terminal (daily use)

### Creating the EXE

```powershell
# Install ps2exe
Install-Module -Name ps2exe -Scope CurrentUser

# Compile the launcher
Invoke-ps2exe -inputFile "AI_Docker_Launcher.ps1" -outputFile "AI_Docker_Manager.exe" -noConsole
```

### Distribution Package

**Single-file distribution** - Just distribute `AI_Docker_Manager.exe`!

All files are embedded inside the .exe:
- setup_wizard.ps1
- launch_claude.ps1
- docker-compose.yml
- Dockerfile
- entrypoint.sh
- claude_wrapper.sh
- fix_line_endings.ps1
- .gitattributes
- README.md

Files are automatically extracted to `%LOCALAPPDATA%\AI_Docker_Manager` when needed.

### User Experience

**First time:**
1. Download `AI_Docker_Manager.exe` (place anywhere: Desktop, Downloads, etc.)
2. Double-click `AI_Docker_Manager.exe`
3. Click "1. FIRST TIME SETUP"
4. Follow wizard - configuration auto-saved to AppData

**Daily use:**
1. Double-click `AI_Docker_Manager.exe` (from anywhere)
2. Click "2. LAUNCH CLAUDE CLI"

**Benefits:**
- No installer needed
- .exe can be on Desktop, USB drive, or anywhere
- All data stored in proper Windows app location
- Clean and professional experience

**See `EXE_CREATION_GUIDE.md` for detailed compilation instructions.**

---

## Quick Reference

**First time setup:**
```powershell
powershell -ExecutionPolicy Bypass -File setup_wizard.ps1
```

**Daily use:**
```powershell
powershell -ExecutionPolicy Bypass -File launch_claude.ps1
```

**Inside container:**
```bash
cd /workspace/your-project
claude
```

**That's it!** Everything else is automatic. 🚀

