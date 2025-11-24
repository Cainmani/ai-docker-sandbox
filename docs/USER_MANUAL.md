# AI Docker Manager - User Manual

## Quick Start Guide for Non-Technical Users

---

## Table of Contents
1. [What is AI Docker Manager?](#what-is-ai-docker-manager)
2. [Prerequisites](#prerequisites)
3. [First Time Setup](#first-time-setup)
4. [Daily Usage](#daily-usage)
5. [First Time Authentication](#first-time-authentication)
6. [Common Tasks](#common-tasks)
7. [Troubleshooting](#troubleshooting)
8. [Important Notes](#important-notes)

---

## What is AI Docker Manager?

AI Docker Manager provides a secure, isolated environment for running Claude Code CLI (an AI assistant) on your Windows PC. It uses Docker to create a "container" - think of it as a secure sandbox where the AI can work without accessing your personal files.

**Key Benefits:**
- **Secure**: AI only has access to the AI_Work folder you designate
- **Isolated**: Runs in a separate Linux environment inside your Windows PC
- **Persistent**: Your authentication and work files are saved permanently
- **Simple**: Easy-to-use GUI - no command line knowledge needed for setup

---

## Prerequisites

**Required Software:**
- Windows 10 or 11 (64-bit)
- Docker Desktop installed and running
  - Download from: https://docs.docker.com/desktop/setup/install/windows-install/
  - Ensure Docker Desktop shows a green icon in your system tray before proceeding

**Required Account:**
- Anthropic API key or Claude account credentials (for first-time authentication)

---

## First Time Setup

### Step 1: Launch Setup Wizard

Double-click `AI_Docker_Manager.exe` and select:

```
[1. FIRST TIME SETUP]
```

**IMPORTANT**: Only run first-time setup once! After initial setup, always use "Launch AI Workspace" instead.

### Step 2: Follow Wizard Pages

The wizard will guide you through 7 pages:

#### Page 1: Welcome
- Read the overview
- Click **Next**

#### Page 2: Credentials
- **Username**: Enter a username for your Linux container (e.g., `john` or `developer`)
- **Password**: Enter a password (this is for the container, not your Windows password)
- **Confirm Password**: Re-enter your password
- Click **Next**

**Note**: These credentials are stored securely in a `.env` file.

#### Page 3: Workspace Location
- Click **Browse** to select a parent directory
- Example: Select `C:\Users\YourName\Documents`
- The wizard will automatically create an `AI_Work` folder inside: `C:\Users\YourName\Documents\AI_Work`
- Click **Next**

**IMPORTANT**: Do not move or rename the AI_Work folder after setup!

#### Page 4: Docker Check
- The wizard checks if Docker Desktop is running
- If Docker is not running, start Docker Desktop and click **Retry Check**
- When you see "Docker is running", click **Next**

#### Page 5: Building Container
- The wizard now builds your secure AI environment
- **This takes 2-5 minutes** - watch the progress bar
- You'll see detailed output in the console window
- Wait for "Container started" message
- Click **Next**

#### Page 6: Installing Claude CLI
- The wizard installs Claude Code CLI via npm
- **This takes 1-2 minutes**
- Wait for "Installation complete" message
- Click **Next**

#### Page 7: Setup Complete
- Read the first-time use instructions
- Click **Finish**

### Setup Complete!
You've successfully created your secure AI environment. Now you can launch the AI Workspace.

---

## Daily Usage

### How to Start the AI Workspace

1. Double-click `AI_Docker_Manager.exe`
2. Select:
   ```
   [2. LAUNCH AI WORKSPACE]
   ```
3. A terminal window opens automatically
4. You're now inside the container at `/workspace` directory

### Inside the Terminal

You'll see a bash prompt like:
```bash
username@ai-cli:/workspace$
```

**To start Claude CLI, type:**
```bash
claude
```

Press Enter, and Claude will start!

---

## First Time Authentication

**The very first time you run `claude` command**, you'll need to authenticate:

### Authentication Process

1. After typing `claude`, you'll see a prompt asking you to authenticate
2. You have two options:

   **Option A: API Key**
   - Visit: https://console.anthropic.com/
   - Generate an API key
   - Copy and paste it into the terminal

   **Option B: Login**
   - Follow the on-screen instructions to login with your Anthropic account

3. **Important**: Your authentication is saved permanently! You only do this once.

### After Authentication

Once authenticated, Claude CLI will start immediately. In future sessions, you can just type `claude` and it will work without asking for credentials again.

---

## Common Tasks

### Task 1: Create a New Project

```bash
# Inside the container terminal
cd /workspace
mkdir my-project
cd my-project
claude
```

Now Claude can help you with files in `my-project` directory.

### Task 2: Access Your Files from Windows

Your work is automatically synced to Windows!

1. Open Windows File Explorer
2. Navigate to your AI_Work folder (e.g., `C:\Users\YourName\Documents\AI_Work`)
3. You'll see all your project folders
4. You can open, edit, and save files directly from Windows!

### Task 3: Exit Claude CLI

To exit Claude:
```bash
# Press Ctrl+C or type:
exit
```

To exit the container terminal:
```bash
# Type:
exit
```

### Task 4: Restart Claude

Just launch AI_Docker_Manager.exe again and select "Launch AI Workspace"!

---

## Troubleshooting

### Problem: "Docker is not running"

**Solution:**
1. Look for Docker Desktop icon in your system tray (bottom-right)
2. If you don't see it, open Docker Desktop from Start Menu
3. Wait until the Docker icon turns green
4. Try launching again

### Problem: "ai-cli container does not exist"

**Solution:**
You need to run First Time Setup first!
1. Open AI_Docker_Manager.exe
2. Select "1. FIRST TIME SETUP"
3. Follow the wizard

### Problem: "claude: command not found"

**Solution:**
This means the installation didn't complete properly.

Try:
```bash
# Check if claude exists
which claude

# If missing, you may need to re-run First Time Setup
```

If problem persists, re-run First Time Setup (it will ask if you want to delete the old container).

### Problem: Claude asks for authentication every time

**Solution:**
Your authentication should persist. If it doesn't:

1. Check that docker-compose.yml has the volume: `claude-config:/home/USERNAME/.claude`
2. Contact your IT support - the Docker volume may not be persisting correctly

### Problem: "Permission denied" errors inside container

**Solution:**
Your user should have full sudo access. Try:
```bash
sudo ls
```

If this asks for a password, use the password you set during First Time Setup.

### Problem: Can't find my AI_Work folder

**Solution:**
1. Open AI_Docker_Manager directory
2. Look for `.env` file
3. Open it with Notepad
4. Find the line: `WORKSPACE_PATH=C:\Path\To\Your\AI_Work`
5. That's where your files are!

---

## Important Notes

### ⚠️ DO NOT Move AI_Work Folder

Once setup is complete, **DO NOT** move or rename your AI_Work folder. The Docker container has a direct link to this folder path. If you move it, the container won't be able to find your files.

### ⚠️ First Time Setup vs Launch

- **First Time Setup**: Run ONCE to create your environment
- **Launch AI Workspace**: Run EVERY TIME you want to use the AI tools

If you accidentally run "First Time Setup" again, it will warn you that you'll lose your authentication and settings. Choose "No" to keep your existing setup.

### ✅ Files Are Synced Automatically

Any file you create inside the container at `/workspace` automatically appears in your Windows AI_Work folder, and vice versa. No manual copying needed!

### ✅ Authentication Persists Forever

Once you authenticate with Claude on first use, your credentials are stored in a Docker volume. Even if you recreate the container, your authentication will persist (unless you delete the `claude-config` Docker volume).

### ✅ Each Project is Isolated

Create separate subdirectories in AI_Work for different projects. Claude will only have context of the directory you're working in.

Example structure:
```
AI_Work/
  ├── project1/
  ├── project2/
  └── project3/
```

### ✅ You Have Sudo Access

Inside the container, you have full administrator (sudo) access with no password required. You can install packages, modify system files, etc.

---

## Quick Reference Commands

### Inside Container Terminal

| Command | Description |
|---------|-------------|
| `claude` | Start Claude CLI |
| `pwd` | Show current directory |
| `ls` | List files in current directory |
| `cd /workspace` | Go to workspace root |
| `mkdir project-name` | Create new project folder |
| `cd project-name` | Enter project folder |
| `exit` | Exit terminal/Claude |

### Common Claude CLI Commands

Once inside Claude:
- Type your questions or requests naturally
- Claude can read, write, and modify files
- Claude can run commands (with your permission)
- Type `help` for Claude CLI help

---

## Troubleshooting

The AI Docker Manager includes a comprehensive logging system to help diagnose and fix problems.

### Where Are the Logs?

All application operations are logged to a central file:

**Log File Location:**
```
%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log
```

**To Open the Log File:**
1. Press `Windows + R`
2. Type: `%LOCALAPPDATA%\AI-Docker-CLI\logs`
3. Press Enter
4. Open `ai-docker.log` with Notepad

### Common Problems and Solutions

#### Problem: Setup wizard won't start

**Solution:**
1. Make sure Docker Desktop is running (check system tray)
2. Check the log file for error messages
3. Look for: `Docker is running and responding`

#### Problem: Container won't launch

**Solution:**
1. Open the log file
2. Look for: `Container check result:` to see if container exists
3. If container doesn't exist, run "First Time Setup" again

#### Problem: Path-related errors

**Solution:**
1. Open the log file
2. Search for: `scriptPath value:` and `scriptPath type:`
3. Share these lines with support for diagnosis

#### Problem: Tools not working inside container

**Solution:**
1. Inside the container terminal, run: `configure-tools --status`
2. This shows which tools are configured
3. Run `configure-tools` to set up any missing tools

### Reading the Logs

The log file contains entries like:
```
[2025-01-24 14:32:15.123] [INFO] [LAUNCHER] Launch AI Workspace button clicked
[2025-01-24 14:32:15.234] [DEBUG] [LAUNCHER] Docker found at: C:\Program Files\...
[2025-01-24 14:32:15.345] [ERROR] [LAUNCHER] Container does not exist
```

**Log Levels:**
- `INFO` - Normal operations
- `DEBUG` - Detailed technical information
- `WARN` - Warnings (not critical)
- `ERROR` - Problems that caused failures

### Advanced: View Logs with PowerShell

If you're comfortable with PowerShell, you can view logs more easily:

```powershell
# View last 50 log entries
Get-Content "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Tail 50

# Find all errors
Select-String -Path "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Pattern "\[ERROR\]"

# Watch logs in real-time
Get-Content "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Wait -Tail 20
```

For complete troubleshooting documentation, see: [docs/LOGGING.md](LOGGING.md)

---

## Getting Help

### Technical Issues
- Check Docker Desktop is running (green icon in system tray)
- Review the log file at: `%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log`
- Look for ERROR entries in the logs
- Contact your IT support team with log file excerpts

### Claude CLI Questions
- Visit: https://docs.claude.com/
- Visit: https://support.anthropic.com/

### Anthropic API Issues
- Visit: https://console.anthropic.com/

---

## Version Information

**AI Docker Manager Version**: 2.0
**Claude Code CLI**: @anthropic-ai/claude-code (latest)
**Container OS**: Ubuntu 24.04
**Required Docker Version**: Docker Desktop 4.0+

---

*This user manual is designed for non-technical users. For technical documentation, see CLAUDE.md and README.md*

---

**Happy AI Coding! 🚀**
