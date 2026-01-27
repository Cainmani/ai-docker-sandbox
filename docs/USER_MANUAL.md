# AI Docker Manager - User Manual

## Quick Start Guide for Non-Technical Users

---

## Table of Contents
1. [What is AI Docker Manager?](#what-is-ai-docker-manager)
2. [Prerequisites](#prerequisites)
3. [First Time Setup](#first-time-setup)
4. [Daily Usage](#daily-usage)
5. [Using Vibe Kanban](#using-vibe-kanban)
6. [First Time Authentication](#first-time-authentication)
7. [Common Tasks](#common-tasks)
8. [Mobile Phone Access (Advanced)](#mobile-phone-access-advanced)
9. [Security Features](#security-features)
10. [Troubleshooting](#troubleshooting)
11. [Important Notes](#important-notes)

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
2. You'll see three main options:
   - **1. FIRST TIME SETUP** - Run once to create your environment
   - **2. LAUNCH AI WORKSPACE** - Open terminal for direct AI CLI access
   - **3. LAUNCH VIBE KANBAN** - Open web-based AI orchestration interface
3. Select option 2 or 3 depending on your needs
4. A terminal window or browser opens automatically

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

## Using Vibe Kanban

Vibe Kanban is a visual web interface that lets you manage multiple AI agents at once. Instead of using one AI tool at a time in the terminal, you can orchestrate Claude, Codex, and Gemini in parallel through a kanban-style board.

### ⚠️ Safety Notice - READ FIRST

**Vibe Kanban runs AI coding agents with `--dangerously-skip-permissions` (also known as `--yolo` mode) by default.** This gives agents unrestricted access to:
- Execute code on your system
- Run terminal commands
- Modify files without confirmation

**Important Safety Practices:**
- Always review what agents are doing before accepting changes
- Ensure you have backups of important work
- Use git branches to isolate agent changes
- The diff tool helps you review changes before committing
- Consider running on non-critical projects first

This software is experimental - use it responsibly. Learn more at: https://vibekanban.com/docs/getting-started#safety-notice

### How to Launch Vibe Kanban

1. Double-click `AI_Docker_Manager.exe`
2. Select:
   ```
   [3. LAUNCH VIBE KANBAN]
   ```
3. Your web browser opens automatically to `http://localhost:3000`
4. The Vibe Kanban interface appears

### Configuring the Port

By default, Vibe Kanban runs on port 3000. To use a different port:

1. Open the `.env` file in `%LOCALAPPDATA%\AI-Docker-CLI\`
2. Add or modify: `VIBE_KANBAN_PORT=8080` (or your preferred port)
3. Restart the container (close terminal and launch again)
4. Browser will open to the new port automatically

### First Time Setup for Vibe Kanban

Before using Vibe Kanban, you must authenticate your AI tools:

1. Launch the AI Workspace first (option 2)
2. Run `configure-tools` in the terminal
3. Set up authentication for Claude, Codex, or Gemini
4. Exit the terminal
5. Now launch Vibe Kanban (option 3)

### Using the Vibe Kanban Interface

**Creating Tasks:**
1. Click "Create Project" and select a git repository from `/workspace`
2. Add tasks to the kanban board
3. Select which AI agent to use (Claude, Codex, Gemini)
4. The agent works on your task automatically

**Monitoring Progress:**
- Tasks move through columns: To Do → In Progress → Done
- Each agent runs in isolation using git worktrees
- Review changes with the built-in diff tool

**Multiple Agents:**
- Run different tasks with different agents simultaneously
- Claude might work on code while Codex writes tests
- Compare results between different AI models

### Stopping Vibe Kanban

- Close the browser tab
- The server continues running in the background
- Re-open by clicking "3. LAUNCH VIBE KANBAN" again
- To fully stop: Open terminal and press Ctrl+C in the Vibe Kanban process

### Vibe Kanban Troubleshooting

#### Problem: "Vibe Kanban binary not found in PATH"

**Solution:**
1. Run First Time Setup with "Force Rebuild" checked
2. This reinstalls all CLI tools including Vibe Kanban
3. Your Claude and GitHub logins will be preserved

#### Problem: Port 3000 already in use

**Solution:**
1. Change the port in `.env` file (see "Configuring the Port" above)
2. Or find and stop the process using port 3000:
   ```powershell
   # In PowerShell on Windows
   netstat -ano | findstr :3000
   taskkill /PID <process_id> /F
   ```

#### Problem: Browser doesn't open automatically

**Solution:**
1. Manually open your browser
2. Navigate to `http://localhost:3000` (or your configured port)
3. Check logs at `%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log`

#### Problem: Agents not responding or failing

**Solution:**
1. Verify AI tools are authenticated: `configure-tools --status`
2. Check the Vibe Kanban logs in the terminal window
3. Restart Vibe Kanban by closing and relaunching

### Vibe Kanban Tips

- Always ensure your `/workspace` contains git repositories
- Authenticate AI tools BEFORE using Vibe Kanban
- Use the diff tool to review changes before committing
- Multiple agents can work on different branches simultaneously
- **Always review agent changes** - they have full system access

For more information, visit: https://vibekanban.com/docs

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

## Mobile Phone Access (Advanced)

You can access Claude Code from your mobile phone (iPhone or Android) using SSH, Mosh, and tmux. This is an optional feature for advanced users.

### Why Use Mobile Access?

- **Work from anywhere**: Use Claude on your phone when away from your computer
- **Seamless roaming**: Mosh maintains your connection when switching between WiFi and cellular
- **Session persistence**: tmux keeps your session alive even if you disconnect

### Quick Setup

1. **Enable mobile access** - Add to your `.env` file:
   ```
   ENABLE_MOBILE_ACCESS=1
   ```

2. **Rebuild container** - Run First Time Setup again or restart the container

3. **Generate SSH key on mobile** - In your mobile terminal app:
   ```bash
   ssh-keygen -t ed25519 -C "my-phone"
   cat ~/.ssh/id_ed25519.pub
   ```

4. **Add your public key to the container**:
   ```bash
   docker exec ai-cli bash -c 'echo "YOUR_PUBLIC_KEY" >> ~/.ssh/authorized_keys'
   ```

5. **Connect via VPN** - Use Tailscale, WireGuard, or similar to access your network

6. **Connect via Mosh**:
   ```bash
   mosh --ssh="ssh -p 2222" username@your-host-ip
   ```

7. **Start tmux** (required for scrollback):
   ```bash
   tmux new -s mobile
   ```

### Recommended Mobile Apps

| Platform | App | Notes |
|----------|-----|-------|
| **iOS** | Blink Shell | Best Mosh support ($19.99) |
| **iOS** | Termius | Free tier available |
| **Android** | Termius | Cross-platform |
| **Android** | Termux + mosh | Free, power users |

### Basic tmux Commands

| Action | Keys |
|--------|------|
| Prefix key | `Ctrl+A` |
| Detach | `Ctrl+A` then `d` |
| New window | `Ctrl+A` then `c` |
| Next window | `Ctrl+A` then `n` |
| Enter scroll mode | `Ctrl+A` then `[` |
| Exit scroll mode | `q` |

### Important Security Note

- **Always use a VPN** - Never expose SSH/Mosh ports directly to the internet
- **SSH keys only** - Password authentication is disabled for security
- The default SSH port is 2222 (not the standard 22)

For complete setup instructions, troubleshooting, and security best practices, see:
**[Remote Access Guide](REMOTE_ACCESS.md)**

---

## Security Features

AI Docker Manager implements enterprise-level security practices to protect your credentials and data.

### Password Security (Docker Secrets)

Your container password is handled securely using Docker Secrets:

- **Never stored on disk**: Password is written to a temporary file that is securely deleted after the container starts
- **Not visible in docker inspect**: Unlike environment variables, Docker Secrets are not exposed in container inspection
- **Memory-only storage**: The password file is mounted as tmpfs (RAM) inside the container
- **Automatic cleanup**: Password environment variables are unset immediately after use

**What this means for you:**
- Your password cannot be recovered from logs or configuration files
- Even if someone gains access to your Docker host, they cannot extract your password
- If you need to reset your password, you must recreate the container

### SSH Key Management

For mobile access, the container includes the `add-ssh-key` command for easy key management:

```bash
# Add a new SSH key
add-ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... my-phone"

# List all authorized keys
add-ssh-key --list

# Remove a key
add-ssh-key --remove 1
```

**Security features:**
- Password authentication is disabled (SSH keys only)
- Non-standard port (2222) reduces exposure to automated attacks
- Root login is disabled
- Only your container user can connect

### Best Practices

1. **Use a VPN** when accessing from outside your home network (e.g., Tailscale)
2. **Use Ed25519 keys** - they're more secure and faster than RSA
3. **Rotate keys periodically** if you suspect compromise
4. **Never share your private key** - only share the `.pub` (public) file

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
