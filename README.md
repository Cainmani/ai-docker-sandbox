<p align="center">
  <img src="assets/logo.svg" alt="AI Docker CLI Manager" width="128" height="128">
</p>

<h1 align="center">AI Docker CLI Manager</h1>

<p align="center">
  <strong>Run AI tools securely in an isolated Docker container</strong>
</p>

<p align="center">
  <a href="https://github.com/Cainmani/ai-docker-cli-setup/releases/latest">
    <img src="https://img.shields.io/badge/Download-v1.0.0-brightgreen?style=for-the-badge&logo=windows" alt="Download Latest Release">
  </a>
  &nbsp;
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT License">
  </a>
</p>

<p align="center">
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-features">Features</a> •
  <a href="docs/USER_MANUAL.md">User Manual</a> •
  <a href="CONTRIBUTING.md">Contributing</a> •
  <a href="https://github.com/Cainmani/ai-docker-cli-setup/issues/new?template=bug_report.yml">Report Bug</a>
</p>

---

## 📥 Download

<table>
<tr>
<td width="50%">

### Windows (Recommended)

**[⬇️ Download AI_Docker_Manager.exe](https://github.com/Cainmani/ai-docker-cli-setup/releases/latest/download/AI_Docker_Manager.exe)**

> **Note:** Windows SmartScreen may show a warning because the app isn't code-signed.
> Click **"More info"** → **"Run anyway"** to proceed.
> [Why does this happen?](#-windows-smartscreen-warning)

</td>
<td width="50%">

### Requirements

- Windows 10/11 (64-bit)
- [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)
- 4GB RAM (8GB recommended)
- 10GB free disk space

</td>
</tr>
</table>

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🤖 **Multiple AI Tools** | Claude, GitHub CLI, OpenAI/GPT, Gemini, Codex, and more |
| 🎯 **Vibe Kanban** | Orchestrate multiple AI agents in parallel via web UI |
| 🔒 **Secure Isolation** | AI runs in Docker container - can't access your system files |
| 🚀 **One-Click Setup** | Interactive wizard handles everything automatically |
| 🔄 **Auto-Updates** | CLI tools update automatically every week |
| 📁 **Easy File Access** | Your AI_Work folder is accessible from Windows |
| 🎨 **Modern UI** | Matrix-themed interface with live progress feedback |

### Included AI CLI Tools

- **Claude Code** - Anthropic's AI coding assistant
- **Vibe Kanban** - Web UI to orchestrate AI agents in parallel (⚠️ runs with elevated permissions)
- **GitHub CLI** - GitHub's official command-line tool
- **OpenAI Tools** - Shell GPT, Aider, Codex
- **Google Gemini** - Google's AI assistant
- **Cloud CLIs** - AWS, Azure, Google Cloud

---

## 🚀 Quick Start

### Installation (5-10 minutes)

1. **Download** `AI_Docker_Manager.exe` from the link above
2. **Run** the executable
3. **Click** "First Time Setup"
4. **Follow** the wizard:
   - Enter username/password for container
   - Select location for your AI_Work folder
   - Wait for Docker build and tool installation

### Daily Use (10 seconds)

1. **Run** `AI_Docker_Manager.exe`
2. **Choose your interface:**
   - **"Launch AI Workspace"** - Terminal access to all AI tools
   - **"Launch Vibe Kanban"** - Web UI for parallel AI agents
3. **Start working** - all AI tools are ready!

```bash
# Inside the container (terminal mode)
cd /workspace/my-project
claude                    # Start Claude Code
gh repo clone user/repo   # Use GitHub CLI
sgpt "explain this code"  # Use Shell GPT
```

> **Vibe Kanban Note:** Opens at `http://localhost:3000`. Runs agents with elevated permissions - always review changes before committing.

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| **[User Manual](docs/USER_MANUAL.md)** | Complete guide for end users |
| **[CLI Tools Guide](docs/CLI_TOOLS_GUIDE.md)** | Reference for all AI tools |
| **[Quick Reference](docs/QUICK_REFERENCE.md)** | One-page cheatsheet |
| **[Troubleshooting](docs/LOGGING.md)** | Logging and debugging guide |
| **[Migration Guide](docs/MIGRATION.md)** | Upgrading between versions |
| **[Development Guide](docs/DEVELOPMENT.md)** | For contributors |

---

## ⬆️ Upgrading

### From v1.0.x to v1.1.x

**Breaking change:** Claude Code has been migrated from npm to the native installer.

**Existing users must:**
1. Run "First Time Setup" with **Force Rebuild** checked
2. Re-authenticate **all** tools (Claude, GitHub CLI, etc.)

Your Claude conversation history will be preserved. See the **[Migration Guide](docs/MIGRATION.md)** for details.

---

## 🛡️ Security

AI Docker CLI Manager keeps your system safe:

- **Isolated Environment** - AI only sees files in your AI_Work folder
- **Container Sandboxing** - Runs in a separate Linux environment
- **User Permissions** - AI runs as a non-root user
- **No Internet Backdoors** - Only accesses AI APIs you configure

---

## ❓ FAQ

### Windows SmartScreen Warning

When you run the .exe, Windows may show:

> "Windows protected your PC - Microsoft Defender SmartScreen prevented an unrecognized app from starting"

**This is normal for unsigned apps.** To proceed:
1. Click **"More info"**
2. Click **"Run anyway"**

The app is open-source - you can [review the code](scripts/) or [build from source](#building-from-source).

### "Docker is not running"

The app will try to start Docker Desktop automatically. If it fails:
1. Open Docker Desktop manually
2. Wait for it to fully start (green icon in system tray)
3. Try again

### Container Issues

```bash
# View container logs
docker logs ai-cli

# Restart container
docker restart ai-cli

# Full rebuild
docker stop ai-cli && docker rm ai-cli && docker rmi docker-files-ai
# Then run "First Time Setup" again
```

### Where are my files?

- **Workspace:** The folder you selected during setup (e.g., `C:\Users\You\Documents\AI_Work`)
- **App Config:** `%LOCALAPPDATA%\AI-Docker-CLI\`
- **Logs:** `%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log`

---

## 🔧 Advanced Usage

### DEV Mode (UI Testing)

Hold **Shift** while clicking "First Time Setup" to enter DEV mode - walks through the UI without making changes.

### Manual Container Management

```bash
docker ps -a --filter "name=ai-cli"  # Check status
docker start ai-cli                   # Start
docker stop ai-cli                    # Stop
docker exec -it ai-cli bash           # Shell access
```

### Building from Source

```powershell
# Install ps2exe module
Install-Module -Name ps2exe -Force

# Build the executable
Invoke-ps2exe -inputFile "scripts/AI_Docker_Complete.ps1" -outputFile "AI_Docker_Manager.exe" -noConsole
```

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- 🐛 [Report a bug](https://github.com/Cainmani/ai-docker-cli-setup/issues/new?template=bug_report.yml)
- 💡 [Request a feature](https://github.com/Cainmani/ai-docker-cli-setup/issues/new?template=feature_request.yml)
- 📖 [Improve documentation](https://github.com/Cainmani/ai-docker-cli-setup/pulls)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

**Logo:** Based on [Tabler Icons](https://github.com/tabler/tabler-icons) (MIT License)

---

## 🙏 Acknowledgments

- [Claude Code CLI](https://claude.ai/) by Anthropic
- [Docker](https://www.docker.com/)
- [Tabler Icons](https://tabler.io/icons) for the logo

---

<p align="center">
  <sub>Built with ❤️ for secure AI development</sub>
</p>
