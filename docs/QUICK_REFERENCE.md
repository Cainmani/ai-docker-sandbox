# AI Docker Manager - Quick Reference Cheatsheet

## 🚀 First Time Setup (Run Once Only!)

1. **Prerequisites**: Install Docker Desktop and ensure it's running (green icon in system tray)
2. **Run**: Double-click `AI_Docker_Manager.exe` → Select "**1. FIRST TIME SETUP**"
3. **Wizard Steps**:
   - Enter username and password for Linux container
   - Select parent directory for AI_Work folder (don't move this folder later!)
   - Wait for Docker build (2-5 minutes)
   - Wait for Claude CLI installation (1-2 minutes)
4. **First Use**: When you first run `claude`, authenticate with your Anthropic API key or account
   - **Authentication persists** - you only do this once, even across container rebuilds!

---

## 💻 Daily Usage

### Option A: Launch AI Workspace (Terminal)
```
1. Double-click AI_Docker_Manager.exe
2. Select "2. LAUNCH AI WORKSPACE"
3. Terminal opens → type: claude (or any AI tool)
4. Start working!
```

### Option B: Launch Vibe Kanban (Web UI)
```
1. Double-click AI_Docker_Manager.exe
2. Select "3. LAUNCH VIBE KANBAN"
3. Browser opens to http://localhost:3000
4. Create tasks, assign AI agents, work in parallel!
```

### Essential Terminal Commands
| Command | Description |
|---------|-------------|
| `claude` | Start Claude CLI |
| `pwd` | Show current directory |
| `ls` | List files |
| `cd /workspace` | Go to workspace root |
| `mkdir my-project` | Create project folder |
| `cd my-project` | Enter project folder |
| `exit` | Exit terminal |

---

## 🎛️ Vibe Kanban Quick Start

Vibe Kanban lets you run multiple AI agents simultaneously through a visual web interface.

⚠️ **SAFETY WARNING**: Vibe Kanban runs agents with `--dangerously-skip-permissions` by default. Agents have unrestricted access to execute code and commands. **Always review changes before committing!**

| Step | Action |
|------|--------|
| 1. Authenticate first | Run `configure-tools` in terminal to set up Claude/Codex/Gemini |
| 2. Launch Vibe Kanban | Click "3. LAUNCH VIBE KANBAN" in manager |
| 3. Create project | Select a git repo from `/workspace` |
| 4. Add tasks | Create tasks on the kanban board |
| 5. Assign agent | Choose Claude, Codex, or Gemini for each task |
| 6. Monitor | Watch agents work in parallel |
| 7. Review | **Always review** with built-in diff tool before accepting |

**URL**: http://localhost:3000 (opens automatically)
**Custom Port**: Edit `.env` file → `VIBE_KANBAN_PORT=8080`

---

## 📁 File Access

**Inside Container**: `/workspace` = **On Windows**: Your AI_Work folder

Files sync automatically both ways! Edit from Windows or from Claude - changes appear everywhere.

---

## 🔧 Common Troubleshooting

| Problem | Solution |
|---------|----------|
| "Docker is not running" | Start Docker Desktop, wait for green icon, retry |
| "container does not exist" | Run First Time Setup first |
| "claude: command not found" | Re-run First Time Setup |
| "Permission denied" | Use `sudo` command (your password from setup) |
| Can't find AI_Work folder | Check `.env` file for `WORKSPACE_PATH=` |
| "Vibe Kanban binary not found" | Run First Time Setup with "Force Rebuild" checked |
| Port 3000 already in use | Change port in `.env`: `VIBE_KANBAN_PORT=8080` |

---

## ⚠️ Important Rules

✅ **DO**: Create project subdirectories in AI_Work
✅ **DO**: Use "Launch AI Workspace" for daily access
✅ **DO**: Access files from Windows File Explorer anytime

❌ **DON'T**: Move or rename AI_Work folder after setup
❌ **DON'T**: Run "First Time Setup" again (unless intentionally resetting)
❌ **DON'T**: Close Docker Desktop while using Claude

---

## 📋 Workflow Example

```bash
# 1. Launch AI_Docker_Manager.exe → "2. LAUNCH AI WORKSPACE"

# 2. Inside terminal:
cd /workspace
mkdir my-website
cd my-website

# 3. Start Claude:
claude

# 4. Now ask Claude to help you build something!
# Example: "Help me create a simple HTML website with a contact form"

# 5. Files will appear in: AI_Work\my-website\ (on Windows)
```

---

## 📱 Mobile Access (Optional)

Enable SSH + Mosh + tmux for mobile phone access:

```bash
# 1. Add to .env file:
ENABLE_MOBILE_ACCESS=1

# 2. Rebuild container, then add your SSH key:
docker exec ai-cli bash -c 'echo "YOUR_KEY" >> ~/.ssh/authorized_keys'

# 3. Connect via VPN + Mosh:
mosh --ssh="ssh -p 2222" user@host

# 4. Start tmux:
tmux new -s mobile
```

### tmux Quick Reference
| Action | Keys |
|--------|------|
| Prefix | `Ctrl+A` |
| Detach | `Ctrl+A` + `d` |
| Scroll mode | `Ctrl+A` + `[` |
| Exit scroll | `q` |
| New window | `Ctrl+A` + `c` |
| Split horizontal | `Ctrl+A` + `-` |
| Split vertical | `Ctrl+A` + `|` |

See **[REMOTE_ACCESS.md](REMOTE_ACCESS.md)** for full guide.

---

## 🆘 Quick Help

- **Docker Desktop**: System tray icon must be green
- **Authentication**: Only needed first time you run `claude`
- **Your files**: Always in AI_Work folder on Windows
- **Sudo access**: Use your setup password if prompted
- **Exit Claude**: Press `Ctrl+C` or type `exit`

---

## 🎯 Pro Tips

💡 **Organize Projects**: Create separate folders for each project
```
AI_Work/
  ├── website-project/
  ├── data-analysis/
  └── automation-scripts/
```

💡 **Check Docker Status**: Before launching, ensure Docker Desktop icon is green

💡 **Backup Important Work**: AI_Work folder contains all your projects - back it up regularly!

💡 **First Time Users**: Read full USER_MANUAL.md for detailed instructions

---

**Support**: For detailed help, see USER_MANUAL.md | Technical docs: CLAUDE.md

**Version**: AI Docker Manager 2.0 | Ubuntu 24.04 Container | Claude Code CLI (latest)
