# Changelog

All notable changes to AI Docker CLI Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Production-level logging system with centralized log file
- Live terminal display during Docker build and CLI tools installation
- Status feedback indicators in launcher UI
- Force rebuild checkbox now visible before build starts
- Early startup logging for debugging wizard initialization
- Console window visible (minimized) during setup for progress visibility

### Changed
- Improved setup wizard flow - users can now toggle Force Rebuild before build starts
- Enhanced error handling with UI state reset on failures

### Fixed
- Fixed issue where setup wizard showed no feedback during initialization
- Fixed Force Rebuild checkbox not being usable (build started automatically)

## [1.0.0] - 2025-01-XX

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

### Security
- Secure password hashing for Ubuntu user
- Docker isolation prevents AI access to host system files
- Credentials stored securely in container

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 1.0.0 | 2025-01-XX | Initial public release |

[Unreleased]: https://github.com/Cainmani/ai-docker-cli-setup/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Cainmani/ai-docker-cli-setup/releases/tag/v1.0.0
