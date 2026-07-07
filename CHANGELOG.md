# Changelog

All notable changes to AI Docker CLI Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.2] - 2026-07-07

### Fixed
- **"Set-Acl: The process does not possess the 'SeSecurityPrivilege' privilege" error during password-file creation.** `Set-Acl` writes the owner/SACL sections of the security descriptor in addition to the permission list, which requires a privilege that non-elevated PowerShell sessions don't hold. The chmod-600-equivalent lockdown now uses `icacls /inheritance:r /grant:r`, which only modifies the permission list and works without elevation. Impact of the old bug was low: the file lives under the user profile (already restricted by inherited permissions) and is scrubbed to a placeholder after setup — but the hardening now actually applies.
- **Misleading "[SECURITY] Password file permissions restricted" success message after the ACL step had just failed.** The `Set-Acl` error was non-terminating, so the failure handler never ran; the icacls exit code is now checked explicitly and failures report a warning instead of a false success.
- **Ubuntu's first-login sudo hint no longer appears in the wizard console.** The 'To run a command as administrator (user "root"), use "sudo <command>"' message is a stock Ubuntu hint printed on a sudo-group user's first login, and every rebuild re-triggered it (fresh home directory = missing `~/.sudo_as_admin_successful` flag). It was harmless but read like an error, so the entrypoint now pre-creates the flag file. Requires a container rebuild to take effect.

## [1.3.1] - 2026-07-07

Fixes the scary-but-harmless errors the setup wizard showed after rebuilding for 1.3.0. No container changes - the container itself was installing fine; the wizard just gave up waiting too early and hit a PowerShell 5.1 incompatibility during cleanup.

### Fixed
- **Wizard timed out during CLI tool installation after the 1.3.0 rebuild** ("Installation is taking longer than expected", "Claude CLI not found yet"). The wizard only waited 5 minutes, but a Force Rebuild now installs 8 tools sequentially (9router and OmniRoute were added in 1.3.0), which routinely takes longer. The wait is now 10 minutes, and the timeout/verification messages explain that installation genuinely continues in the background (your shell shows an "Installing..." spinner until it finishes - `claude` and the other tools appear once it completes).
- **"Secure replacement failed: RandomNumberGenerator does not contain a method named 'Fill'"** during password-file cleanup. `RandomNumberGenerator::Fill()` only exists in PowerShell 7 (.NET Core); Windows PowerShell 5.1 users hit the fallback path. Now uses `Create()`/`GetBytes()`, which works on both. The fallback did still replace the password with a placeholder, so no security impact - the overwrite passes just didn't run.

### Changed
- **Wizard install progress now tracks all 8 tools** (previously only the original 5), so the progress bar no longer stalls at 95% while Vibe Kanban, 9router, and OmniRoute install.

## [1.3.0] - 2026-07-07

Adds unified AI router tools (9router / OmniRoute) and fixes reaching their dashboards from the Windows host browser. Force Rebuild recommended so the container picks up the new tools and the updated port mapping.

### Added
- **9router and OmniRoute now install automatically** alongside the other CLI tools. These unified "AI router" gateways expose multiple AI subscriptions behind one OpenAI-compatible endpoint. Pinned to `9router@0.5.18` and `omniroute@3.8.45`; both are the real npm packages (not forked) and update via the weekly container tool updater.
- **"AI Router" entry in `configure-tools`** (option 6). 9router and OmniRoute are interchangeable and share one dashboard port, so the wizard runs only one at a time: pick a router, it stops any other and starts the chosen one bound to `0.0.0.0`, then prints the dashboard URL. `config-status` shows the slot as configured once either is installed.
- **Router data now persists across rebuilds.** A new `router-data` Docker volume holds each router's SQLite DB and linked-provider credentials (`DATA_DIR=~/.router-data/<tool>`, a separate subdir per tool), so you don't have to re-link your subscriptions after a Force Rebuild.

### Fixed
- **9router / OmniRoute dashboards were unreachable from the host browser** (`localhost:20128` refused to connect). Two root causes, both addressed:
  - The port was never published from the container — `docker-compose.yml` now publishes the shared router port (`AI_ROUTER_PORT`, default `20128`).
  - The routers bind to `localhost` (127.0.0.1) inside the container by default, which Docker's published port cannot reach — the `~/.bashrc` `9router`/`omniroute` wrappers now launch the real binaries bound to `0.0.0.0`, and stop any other router first so the shared port never double-binds.

### Notes
- Recreate the container to pick up the new port mapping and volume: `docker compose up -d --force-recreate` (or Force Rebuild in the launcher). Your workspace, tool logins, and router subscriptions persist — they live on mounted volumes, not in the container layer.

## [1.2.4] - 2026-07-01

Dependency refresh release. Force Rebuild recommended to pick up the updated tools.

### Changed
- **Updated pinned AI CLI tool versions** (fresh installs and rebuilds were getting months-old tools):
  - `@openai/codex` 0.98.0 → 0.142.5
  - `@google/gemini-cli` 0.27.3 → 0.49.0
  - `vibe-kanban` 0.1.7 → 0.1.44
  - `openai` (pip) 2.18.0 → 2.44.0
- **Refreshed Ubuntu 24.04 base image digest** to pull in upstream security patches

### Added
- **Weekly scheduled CI run** (Mondays 06:00 UTC) so the pinned-version check flags stale tools even when the repo is idle
- **Dependabot for GitHub Actions** — keeps workflow action pins current automatically (also resolves the Node 20 runtime deprecation warnings)

### Fixed
- **`docs/CLAUDE.md` was never in the repository**: the `.gitignore` pattern `CLAUDE.md` (meant for a personal root-level context file) also matched `docs/CLAUDE.md`, so the project's developer context doc only existed locally and `docs/DEVELOPMENT.md` linked to a missing file. The rule is now anchored to the root (`/CLAUDE.md`) and the docs copy is tracked

## [1.2.3] - 2026-07-01

Maintenance release shipping the full-application audit remediation (131 findings reviewed across UI/UX, security, dependencies, best practices, and code quality — PRs #43–#50). No new features and no migration steps required.

### Security
- **Cryptographic RNG for password file overwrite**: The 3-pass secure overwrite in the setup wizard now uses a cryptographic random number generator instead of `System.Random`
- **Log sanitization hardening**: Added redaction for GitHub fine-grained tokens (`github_pat_...`) in both PowerShell and bash logging libraries, and fixed API key pattern ordering so `sk-ant-` / `sk-proj-` keys are fully redacted instead of partially matched by the generic `sk-` pattern
- **SSH key format validation**: `setup_remote_connection.sh` now validates public key format before adding it to `authorized_keys`
- **Quoted usernames in docker exec**: `launch_claude.ps1` and `launch_vibe_kanban.ps1` quote the container username in all `docker exec` commands
- **Removed unused pipx** from the Docker image (smaller attack surface)
- Added `.secrets/` to `.gitignore`

### Fixed
- **`update-container-tools` environment variable handling**: `Get-EnvVar` returned the wrong value when a variable was set to an empty string (PowerShell coerces `$null` defaults to `""`)
- **Interactive configure menu recursion**: `configure_tools.sh` interactive menu converted from recursion to a loop, preventing stack growth on long sessions
- **ANSI color codes written to log files** by `auto_update.sh` are now stripped
- **Exception messages not interpolated** in setup wizard error logging (single-quote string bug)
- **`run_tests.ps1` variable used before definition** when reporting user manual path
- **Fix-LineEndings file list** updated to match actual embedded scripts (removed deleted `claude_wrapper.sh`, added missing scripts)
- **Build metadata**: .exe version info now shows the real project name and version instead of "Your Company" / 2.0.0.0

### Changed
- **Shared module extraction (DRY)**: Duplicate logic across launcher scripts and the setup wizard consolidated into `docker_helpers.ps1`, `setup_utils.ps1`, `env_utils.ps1`, and `log_utils.ps1`; bash scripts now share colors/print helpers via `lib/logging.sh`
- **Removed obsolete `claude_wrapper.sh`**: the Claude native installer is on PATH, making the wrapper dead code
- **Container idle process**: `sleep infinity` replaces `tail -f /dev/null` for proper signal handling
- **Codex model configurable** via `CODEX_MODEL` environment variable instead of a hardcoded model string
- **CI**: added bash test suites to CI, added shellcheck (docker/*.sh) and hadolint (Dockerfile) linting, pinned ps2exe to v1.0.17 in the release workflow
- **CI back on GitHub-hosted runners**: the self-hosted runner introduced in PR #43 was deregistered after the repo went idle (GitHub removes runners offline 14+ days), leaving CI permanently queued; GitHub-hosted runners are free for public repos and avoid the fork-PR code-execution risk of self-hosted runners

### Added
- **Bash structural regression test suite** (`tests/test_bash_fixes.sh`, 38 assertions) guarding all audit fixes against regression, plus ~30 new Pester tests covering the extracted PowerShell modules

### Removed
- Internal audit and validation working documents (`AUDIT_REPORT.md`, `docker/VALIDATION_COMPLETE.md`, `docker/NPM_PERMISSION_FIX.md`, `docs/validation_report.md`) — point-in-time artifacts now captured by this changelog and the git history

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
