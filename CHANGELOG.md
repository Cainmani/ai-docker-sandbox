# Changelog

All notable changes to AI Docker CLI Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-01-26

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
| 1.1.2 | 2025-01-20 | Clarify update-tools scope, dynamic package updates |
| 1.1.1 | 2025-01-20 | Remove Codex OAuth workaround, add install retry logic |
| 1.1.0 | 2025-01-17 | Vibe Kanban integration |
| 1.0.1 | 2025-12-11 | Add version display and Report Issue link |
| 1.0.0 | 2025-12-11 | Initial production release |

[Unreleased]: https://github.com/Cainmani/ai-docker-cli-setup/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/Cainmani/ai-docker-cli-setup/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/Cainmani/ai-docker-cli-setup/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Cainmani/ai-docker-cli-setup/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/Cainmani/ai-docker-cli-setup/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Cainmani/ai-docker-cli-setup/releases/tag/v1.0.0
