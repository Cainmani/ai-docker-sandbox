# Changelog

All notable changes to AI Docker CLI Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] - 2026-02-11

### Added
- **Auth persistence across container rebuilds**: Credentials for all tools now survive Force Rebuild
  - New `tool-auth` Docker volume with symlinks for gh, openai, gemini, codex, and shell_gpt configs
  - `~/.claude.json` (onboarding flag) persisted via symlink into claude-config volume
  - `OPENAI_API_KEY` auto-loaded from persisted config on shell startup
  - No more re-authentication after rebuilding the container
- **Welcome banner wait spinner**: If tools are still installing when you attach, a spinner shows until installation completes, then the full welcome banner displays
- **Auth persistence test suite**: 27 automated tests covering first run, migration, rebuild, and idempotent re-run scenarios
- **fail2ban SSH protection**: Automatically protects SSH from brute force attacks when mobile access is enabled (closes #35)
  - Bans IPs after 5 failed login attempts for 10 minutes
  - Integrated into `setup_mobile_access.sh` - no manual configuration needed
  - Check status with `fail2ban-client status sshd`

### Fixed
- **Critical: Tools fail to install on new builds** (`set -u` unbound variable crashes)
  - `install_cli_tools.sh`: `$1` unguarded when called without arguments — caused total install failure
  - `install_cli_tools.sh`: EXIT trap created marker file on crash, permanently preventing retries
  - `configure_tools.sh`: `$ANTHROPIC_API_KEY` and `$LOG_FILE` unguarded — crashed `config-status`
  - `auto_update.sh`: `$1`/`$2` unguarded in 4 locations
- **WSL RAM/CPU detection showing 0 in setup wizard**: `wsl_config.ps1` was not embedded in the .exe after PR #41 extracted it to a separate file. Added to build embed list and extraction logic
- **Username validation accepting uppercase**: PowerShell `-notmatch` is case-insensitive; changed to `-cnotmatch` so "Caide" is correctly rejected
- **`claude` command not found after native installer migration**: Replaced hardcoded dead npm path in `claude_wrapper.sh` with multi-location fallback (`~/.local/bin/claude`, `~/.local/share/claude/local/claude`, npm global)
- **Segmentation fault in `update-container-tools`**: Fixed infinite recursion caused by function name collision between `log_message()` in auto_update.sh and the logging library. Renamed to `update_log()` to avoid conflict
- **Update script checking for non-installed tools**: Removed references to azure-cli, google-cloud-sdk, bat, ripgrep, fd-find, fzf, httpie, jq, aws-cli, and codeium from apt update checks
- **Configure-tools showing non-installed tools**: Removed AWS CLI, Azure CLI, Google Cloud CLI, and Codeium from the configuration wizard menu

### Changed
- Replaced timestamp-based credential staleness check with simple existence check (credentials in volumes are always current)
- Updated `docs/CLI_TOOLS_GUIDE.md` to accurately reflect installed tools (Claude, GitHub CLI, OpenAI Codex, OpenAI SDK, Gemini, Vibe Kanban)
- Updated `README.md` to list only actually installed AI CLI tools
- Simplified apt update command to only check `gh` package (the only apt-installed CLI tool)
- Updated `docs/REMOTE_ACCESS.md` with fail2ban security documentation

### Security
- **Log sanitization for launch scripts**: Added `Sanitize-LogMessage` to `launch_claude.ps1` and `launch_vibe_kanban.ps1` — redacts Windows username, container username, API keys, and tokens before writing to log files
- **Fallback log sanitization**: `auto_update.sh` fallback logging now sanitizes messages when the logging library is unavailable
- Removed accidentally tracked PowerShell log file from repository

## [1.2.1] - 2026-01-27

### Fixed
- **Container restart fails after setup** (Critical): Docker Compose requires secret files to exist for bind mounts. Password file is now replaced with "SETUP_COMPLETE" placeholder instead of being deleted, allowing container restarts without "bind source path does not exist" errors
- **add-ssh-key "USER: unbound variable"**: Script used `$USER` which is unset when running as root in Docker. Changed to `$(whoami)` for reliable operation
- **Welcome screen not shown via "Launch Workspace"**: Added `-l` flag to bash command to invoke as login shell, ensuring `.bashrc` is sourced and welcome banner displays

### Changed
- Renamed `Remove-SecurePasswordFile` to `Replace-PasswordWithPlaceholder` in setup wizard
- Password security maintained: 3-pass secure overwrite still performed before writing placeholder

## [1.2.0] - 2026-01-27

### Added
- **Mobile Access**: Optional SSH + Mosh + tmux support for accessing Claude Code from mobile devices
  - Mosh provides seamless roaming between WiFi and cellular networks
  - tmux provides session persistence and scrollback (required since Mosh has no scrollback)
  - SSH key authentication only (passwords disabled for security)
  - Non-standard port 2222 to reduce automated scans
  - Mosh UDP ports 60001-60005 for up to 5 concurrent connections
- New environment variables for mobile access configuration:
  - `ENABLE_MOBILE_ACCESS` (default: 0) - Set to 1 to enable
  - `SSH_PORT` (default: 2222) - SSH server port
  - `MOSH_PORT_START` (default: 60001) - First Mosh UDP port
  - `MOSH_PORT_END` (default: 60005) - Last Mosh UDP port
- Mobile-optimized tmux configuration with Ctrl+A prefix (easier on mobile keyboards)
- New documentation: `docs/REMOTE_ACCESS.md` - comprehensive guide for mobile setup
- SSH keys persistence via Docker volume (`ssh-keys`)
- Locale configuration (en_US.UTF-8) required for Mosh
- **`add-ssh-key` command** for easy SSH key management in the container
  - `add-ssh-key "key"` - Add a new SSH public key
  - `add-ssh-key --list` - List all authorized keys
  - `add-ssh-key --remove N` - Remove key by number
  - Validates key format and checks for duplicates
  - Color-coded output for non-technical users

### Changed
- Updated README.md with mobile access feature and documentation link
- Updated USER_MANUAL.md with "Mobile Phone Access (Advanced)" section and Security Features section
- Updated QUICK_REFERENCE.md with tmux quick reference commands
- Dockerfile now includes openssh-server, mosh, tmux, and locales packages

### Security
- **Docker Secrets for password handling**: Password is no longer stored in `.env` file
  - Password written to temporary file that is securely deleted after container starts
  - Uses Docker Secrets (tmpfs/memory-only) inside container
  - Not visible in `docker inspect` output or `/proc/*/environ`
  - Credential environment variables automatically cleaned up after use
- Added `.gitignore` in docker directory to prevent accidental commits of `.secrets/`
- Updated password handling UI text to reflect new secure storage method

## [1.1.3] - 2026-01-26

### Added
- Container-side logging with automatic log rotation (10MB trigger, 3 compressed backups)
- Log files: `install.log`, `entrypoint.log`, `update.log`, `configure.log`
- Logs stored in `<workspace>/.ai-docker-cli/logs/` for easy access from Windows
- Logs are sanitized at write time for privacy (API keys, passwords, tokens redacted)
- "Report Issue" button now opens the logs folder for easy attachment to bug reports

### Changed
- Updated bug report template with container logs location and sanitization note

## [1.1.2] - 2025-01-20

### Changed
- Renamed `update-tools` to `update-container-tools` for clarity (old alias still works)
- Renamed `check-updates` to `check-container-updates` for clarity (old alias still works)
- Update commands now dynamically update ALL installed npm/pip packages instead of hardcoded list
- Login banner now shows NOTE clarifying that commands update container tools only

### Added
- Clear messaging in update script explaining scope (container tools vs launcher app)
- Help text clarifies that launcher app updates must be downloaded from GitHub

### Fixed
- Confusion between container tool updates and launcher app updates

## [1.1.1] - 2025-01-20

### Changed
- Removed Codex OAuth workaround (Page 6 in setup wizard) - OpenAI fixed native Docker OAuth support ([#2798](https://github.com/openai/codex/issues/2798))
- Removed Codex auth auto-sync from launch script - no longer needed
- Users can now authenticate Codex directly in container with `codex auth login`

### Added
- Retry logic with cache clearing for npm package installations
- Handles ECONNRESET errors for large packages like @openai/codex (~100MB)
- 3 retry attempts with npm cache clean between failures
- Retry logic for pip package installations
- Versioning requirements documentation in CLAUDE.md

### Fixed
- Codex CLI installation failures due to transient network errors during first-time setup

## [1.1.0] - 2025-01-17

### Added
- Vibe Kanban integration for parallel AI agent orchestration
- "Launch Vibe Kanban" button in main menu
- Vibe Kanban auto-installation during first-time setup
- Port 5173 exposure for Vibe Kanban web interface
- Diagnostic logging for Vibe Kanban startup

### Changed
- Improved UI flow and button layout
- Consolidated AppData folders into single AI-Docker-CLI directory

### Fixed
- First Time Setup page minimization on startup
- Force rebuild now uses --no-cache flag
- Error handling for missing .env file

## [1.0.1] - 2025-12-11

### Added
- Version display in GUI footer (bottom-left corner)
- "Report Issue" clickable link in GUI footer (bottom-right corner)
- Link opens GitHub bug report template directly

### Changed
- Increased form height to accommodate new footer elements

## [1.0.0] - 2025-12-11

### Added
- Initial release of AI Docker CLI Manager
- Setup wizard with Matrix-themed UI
- Support for multiple AI CLI tools:
  - Claude Code CLI
  - GitHub CLI (gh)
  - Google Gemini CLI
  - OpenAI Python SDK
  - OpenAI Codex CLI
- Docker container isolation for secure AI operations
- Automatic CLI tools installation inside container
- Workspace directory management (AI_Work folder)
- Ubuntu credentials configuration
- Docker status checking and validation
- DEV MODE for UI testing (Shift+Click)
- Comprehensive documentation
- Production-level logging system (`%LOCALAPPDATA%\AI-Docker-CLI\logs\`)
- Live terminal display during Docker build
- Docker Desktop startup check with retry loop
- Codex subscription authentication support (OAuth flow)
- Auto-update checker for new releases
- GitHub integration (issue templates, CI/CD workflows)

### Security
- Secure password hashing for Ubuntu user
- Docker isolation prevents AI access to host system files
- Credentials stored securely in container
- Codex auth.json validation before sync
- Process check before removing .codex folder

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 1.2.2 | 2026-02-11 | Auth persistence, set -u fixes, WSL detection, log sanitization |
| 1.2.1 | 2026-01-27 | Fix container restart, add-ssh-key, and welcome screen bugs |
| 1.2.0 | 2026-01-27 | Mobile access via SSH + Mosh + tmux |
| 1.1.3 | 2026-01-26 | Container-side logging with rotation |
| 1.1.2 | 2025-01-20 | Clarify update-tools scope, dynamic package updates |
| 1.1.1 | 2025-01-20 | Remove Codex OAuth workaround, add install retry logic |
| 1.1.0 | 2025-01-17 | Vibe Kanban integration |
| 1.0.1 | 2025-12-11 | Add version display and Report Issue link |
| 1.0.0 | 2025-12-11 | Initial production release |

[Unreleased]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.2.2...HEAD
[1.2.2]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/Cainmani/ai-docker-sandbox/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Cainmani/ai-docker-sandbox/releases/tag/v1.0.0
