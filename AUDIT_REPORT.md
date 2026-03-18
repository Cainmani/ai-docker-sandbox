# Application Audit Report — AI Docker CLI Manager v1.2.2

## Audit Date: 2026-02-10

---

## Executive Summary

This comprehensive audit reviewed the entire AI Docker CLI Manager application across 5 dimensions: UI/UX, Security, Updates & Dependencies, Best Practices, and Code Quality. A total of **131 findings** were identified across **58 files**.

### Severity Distribution

| Severity | Count | Description |
|----------|-------|-------------|
| **High** | 24 | Issues that pose significant risk or degrade core functionality |
| **Medium** | 58 | Issues that should be addressed in planned development cycles |
| **Low** | 32 | Minor issues or improvements with limited impact |
| **Info** | 17 | Observations and suggestions for consideration |
| **Total** | **131** | |

### Overall Health Score: **6.5 / 10**

**Key Strengths:**
- Well-structured Docker Secrets mechanism for password management
- Comprehensive logging library with credential sanitization
- Polished Matrix-themed UI with consistent visual identity
- Functional auto-update system with granular tool management
- Good CI/CD foundation with syntax validation and release automation

**Critical Concerns:**
- **Supply-chain risk:** 4 instances of `curl | sh` without integrity verification (SEC-002/003/004, DEP-003/004)
- **SSH hardening gaps:** Missing cipher/MAC/KEX restrictions on exposed SSH port (SEC-008)
- **GitHub Actions unpinned:** All CI/CD actions use floating tags, vulnerable to tag-reassignment attacks (DEP-005/006/007)
- **Code duplication:** Significant DRY violations across PowerShell and shell scripts (CQ-002/003/004/005)
- **Monolithic wizard:** 2,373-line single file handling UI, Docker, WSL, and security concerns (CQ-001)
- **Dead code:** Removed tools still referenced in update/configure functions (CQ-006/007/008)

### Findings by Dimension

| Dimension | High | Medium | Low | Info | Total |
|-----------|------|--------|-----|------|-------|
| UI/UX | 3 | 9 | 8 | 5 | 25 |
| Security | 5 | 14 | 6 | 1 | 26 |
| Updates & Dependencies | 6 | 8 | 3 | 3 | 20 |
| Best Practices | 4 | 12 | 7 | 7 | 30 |
| Code Quality | 6 | 15 | 8 | 1 | 30 |

---

## 1. UI/UX Findings

| ID | Severity | File:Line | Finding | Recommendation |
|---|---|---|---|---|
| UX-001 | High | `setup_wizard.ps1:1530-1533` | Username/password validation only checks for empty/whitespace. No minimum length, no prohibited character validation (e.g., spaces, special shell chars in username could break `docker exec -u`), and no maximum length enforcement. | Add validation: username must be 1-32 chars, alphanumeric + underscore only (Linux username rules). Password minimum 4 chars. Show inline error labels rather than modal `Show-Error` popups. |
| UX-002 | High | `setup_wizard.ps1:1575` | Folder selection error message says `'choose a parent folder'` -- lowercase, terse, and lacks guidance. Other error messages in the app use complete sentences with context. | Change to `'Please select a parent directory using the Browse button or type a valid path.'` to match the tone and helpfulness of other messages. |
| UX-003 | High | `setup_wizard.ps1:1504-1509` | Back button navigates unconditionally to the previous page. On pages 5 (Build) and 7 (CLI Install), going back mid-operation could leave the build or installation in a broken state. The build process is still running when the user navigates away. | Disable the Back button during active build/install operations (pages 5 and 7). Re-enable only after the operation completes or fails. |
| UX-004 | Medium | `setup_wizard.ps1:888-889` | The wizard form uses `FormBorderStyle = 'FixedDialog'` and `MaximizeBox = $false`, which prevents resizing. The form is 950x700 -- on smaller displays (e.g., 1366x768 laptops at 125% scaling), the form may be partially off-screen or clip navigation buttons at the bottom. | Either allow vertical resizing or add `AutoScroll = $true` to the form. Test at 125% and 150% DPI scaling. Consider reducing minimum height or making the layout responsive. |
| UX-005 | Medium | `setup_wizard.ps1:74-78` | MatrixAccent `(0,180,50)` on MatrixDarkGreen `(0,20,0)` yields approximately 5.9:1 contrast ratio -- used for description text on radio buttons (lines 1082, 1097, 1112) at 9pt font, which fails WCAG AAA for small text. | Lighten MatrixAccent to at least `(0,210,60)` to improve readability of the secondary description text, or increase those labels to 10pt. |
| UX-006 | Medium | `setup_wizard.ps1:80-118` | No keyboard navigation support is configured. Radio buttons, checkboxes, and buttons do not have explicit `TabIndex` values set. The `AcceptButton` and `CancelButton` properties of the form are not set. | Set `$form.AcceptButton = $btnNext` and `$form.CancelButton = $btnCancel`. Assign explicit `TabIndex` values to all interactive controls in page order. |
| UX-007 | Medium | `AI_Docker_Launcher.ps1:180` / `AI_Docker_Complete.ps1:338` | Both launcher forms use `FormBorderStyle = 'FixedDialog'` with no recognizable window icon. User may lose the minimized window behind other windows. | Explicitly set `$form.MinimizeBox = $true` and add a recognizable `$form.Icon` for the taskbar. |
| UX-008 | Medium | `launch_claude.ps1:159` | When Docker Desktop is not running, a `ShowMsg` dialog shows "Starting Docker Desktop now..." with an OK button. After dismissal, the script silently waits up to 120 seconds with no visible progress indicator. | Replace the modal message box with a WinForms dialog that has a progress bar or spinner and a Cancel button. |
| UX-009 | Medium | `launch_vibe_kanban.ps1:214` | When Vibe Kanban is not installed, `ShowMsg` says "Installing... Please wait." This is a modal OK dialog the user must dismiss before installation begins. The `npm install` then runs synchronously with no visible progress. | Replace the pre-install notification with a non-modal progress dialog showing a spinner during npm install. |
| UX-010 | Medium | `launch_vibe_kanban.ps1:286-304` | When waiting for the Vibe Kanban server to start (up to 90 seconds), there is no user-visible feedback. The script runs headlessly with `WindowStyle Hidden`. | Show a small "Starting Vibe Kanban..." notification window during the wait period with a cancel button. |
| UX-011 | Medium | `AI_Docker_Launcher.ps1:128-132` / `AI_Docker_Complete.ps1:151-155` | Matrix theme colors are defined independently in every file with identical values. If a color is changed in one file, it creates visual inconsistency. | Extract shared theme values into a single shared module or dot-source file. |
| UX-012 | Medium | `setup_wizard.ps1:2223-2227` | On the final "Finish" page, `$form.Close()` is called before `$form.DialogResult` is set. The `DialogResult` may not be properly returned. | Swap the order: set `$form.DialogResult` first, then call `$form.Close()`. |
| UX-013 | Low | `AI_Docker_Launcher.ps1:82` / `AI_Docker_Complete.ps1:105` | App version `"1.2.2"` is hardcoded in two separate files. No single source of truth. | Move the version string to a shared config file read by both scripts. |
| UX-014 | Low | `AI_Docker_Launcher.ps1:393-397` / `AI_Docker_Complete.ps1:567-569` | DEV MODE is activated by holding Shift while clicking "First Time Setup." Appropriately hidden from end users. | Consider adding documentation in DEVELOPMENT.md. No user-facing change needed. |
| UX-015 | Low | `setup_wizard.ps1:900-903` | The Back/Next/Cancel buttons are positioned at fixed coordinates (Y=580). At high DPI settings, these controls could overlap with page content. | Use anchoring (`$btnNext.Anchor = 'Bottom,Right'`) to keep buttons docked relative to the form bottom edge. |
| UX-016 | Low | `setup_wizard.ps1:1386` | On the last page (page 8), the Back button is still enabled. There is nothing actionable to go back to on the completion page. | Disable or hide the Back button on the final page, leaving only "Finish". |
| UX-017 | Low | `setup_wizard.ps1:1469-1484` | Cancel confirmation is only shown on pages 5-7 (build/install pages). On pages 1-4, canceling immediately closes without confirmation, losing any entered credentials and workspace path. | Show cancel confirmation on any page where the user has entered data. |
| UX-018 | Low | `setup_wizard.ps1:956-963` | Username/password textboxes are 400px wide on a 950px form. The remaining 530px right side is blank, wasting space that could show password requirements. | Use the right side to display password requirements or a strength indicator. |
| UX-019 | Low | `AI_Docker_Launcher.ps1:443-449` | Shift+click check exists on "Launch AI Workspace" button but not on the Vibe Kanban button, creating inconsistency. | Add the same Shift-key check to both buttons for consistency. |
| UX-020 | Low | `AI_Docker_Complete.ps1:442-443` | Vibe Kanban description differs between `AI_Docker_Complete.ps1` and `AI_Docker_Launcher.ps1:285`. | Unify the description text across both files. |
| UX-021 | Info | `setup_wizard.ps1:890` | `$form.TopMost = $true` then disabled on `Shown` event. Standard WinForms pattern for wizard launches. | Acceptable as-is. |
| UX-022 | Info | `AI_Docker_Launcher.ps1:697-716` / `AI_Docker_Complete.ps1:982-1001` | Update check runs synchronously on startup. If GitHub API is slow, UI blocks for up to 5 seconds. | Run update check asynchronously after the form is shown, or show the form first. |
| UX-023 | Info | `setup_wizard.ps1:1353-1376` | The "Done" page lists all available commands but does not reflect what was actually installed. If an installation failed, the page still says everything is ready. | Add dynamic status indicators reflecting actual installation results. |
| UX-024 | Info | `launch_claude.ps1:242` | Docker exec command includes `-u $userName` with no quoting. If username contains spaces, the command would fail. | Wrap `$userName` in quotes in the docker command. |
| UX-025 | Info | `setup_wizard.ps1:979-982` | Workspace path textbox is editable but only validated on Next click. No real-time feedback for typed paths. | Add a `TextChanged` event handler that validates the path in real-time with a green/red indicator. |

---

## 2. Security Findings

| ID | Severity | File:Line | Finding | Recommendation |
|---|---|---|---|---|
| SEC-001 | ~~Medium~~ **Resolved** | `docker/Dockerfile:2` | ~~Floating base image tag `ubuntu:24.04` is used.~~ **Fixed in v1.3.0:** Pinned to SHA256 digest. | ~~Pin to a specific SHA256 digest.~~ Done. |
| SEC-002 | High | `docker/Dockerfile:47` | Tailscale installation uses unauthenticated curl-pipe-shell: `curl -fsSL https://tailscale.com/install.sh \| sh`. If CDN or DNS is compromised, arbitrary code runs as root during build. | Download the script first, verify its checksum or GPG signature, then execute. Alternatively, use Tailscale's official APT repository with signed packages. |
| SEC-003 | High | `docker/Dockerfile:50` | NodeSource installation uses curl-pipe-shell: `curl -fsSL https://deb.nodesource.com/setup_20.x \| bash -`. Same supply-chain risk as SEC-002. | Use the NodeSource APT repository with GPG key verification, or use the official Node.js Docker image as a build stage. |
| SEC-004 | High | `docker/install_cli_tools.sh:374` | Claude Code CLI installation uses curl-pipe-shell at runtime: `curl -fsSL https://claude.ai/install.sh \| bash`. This runs inside the container on each first startup, making it a persistent supply-chain risk. | Download the installer, verify its integrity before execution. Consider including the Claude CLI in the Docker image at build time with a pinned version. |
| SEC-005 | Medium | `docker/Dockerfile:56` | `pip install --break-system-packages` bypasses PEP 668 protections. The `pipx` installed on the same line is never used for tool isolation. | Use `pipx` (already installed) for all Python CLI tool installations instead of `pip install --break-system-packages`. |
| SEC-006 | Medium | `docker/install_cli_tools.sh:434` | `pip_install_with_retry "openai"` installs without version pinning or hash verification. A compromised PyPI package could execute arbitrary code. | Pin package versions and use `--require-hashes` with a requirements file. |
| SEC-007 | Medium | `docker/install_cli_tools.sh:101,399,449,464` | All npm packages (`@google/gemini-cli@latest`, `@openai/codex@latest`, `vibe-kanban@latest`) are installed with `@latest` and no integrity verification. | Pin exact versions in a package.json with a lockfile. Integrate `npm audit` as a post-install check. |
| SEC-008 | High | `docker/setup_mobile_access.sh:68-101` | SSH daemon configuration is missing cryptographic hardening directives. No `Ciphers`, `MACs`, `KexAlgorithms`, or `HostKeyAlgorithms` directives, meaning sshd accepts its full default algorithm set including potentially weak ones. | Add explicit directives: `KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org`, `Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com`, `MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com`. |
| SEC-009 | Medium | `docker/setup_mobile_access.sh:88-89` | `AllowTcpForwarding yes` and `AllowAgentForwarding yes` are enabled, allowing SSH users to create arbitrary TCP tunnels through the container to the host network. | Set `AllowTcpForwarding no` and `AllowAgentForwarding no` unless explicitly required. If needed, use `AllowTcpForwarding local`. |
| SEC-010 | Medium | `docker/fail2ban-jail.local:6,9,13` | fail2ban configured with `bantime = 600` (10 min), `findtime = 600`, `maxretry = 5`. An attacker can make 720 attempts/day with only brief interruptions. | Increase `bantime` to 3600+ (1 hour). Reduce `maxretry` to 3. Enable progressive banning (`bantime.increment = true`). Add `recidive` jail for repeat offenders. |
| SEC-011 | Medium | `docker/docker-compose.yml:25-27` | SSH port 2222 and Mosh UDP ports 60001-60005 are always mapped to the host regardless of `ENABLE_MOBILE_ACCESS` setting. Conditional enablement only occurs inside the container. | Use Docker Compose profiles so SSH/Mosh ports are only exposed when `ENABLE_MOBILE_ACCESS=1`. |
| SEC-012 | Medium | `docker/docker-compose.yml:29` | The workspace volume mount `${WORKSPACE_PATH}:/workspace` gives the container read-write access to the entire user-specified directory with no restriction on what `WORKSPACE_PATH` can be. | Validate `WORKSPACE_PATH` in the setup wizard to ensure it points to a dedicated subdirectory. Consider mounting as read-only where write access is not needed. |
| SEC-013 | Low | `docker/entrypoint.sh:102` | Passwordless sudo is configured: `echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL"`. Any process running as the user can escalate to root without authentication. | Restrict passwordless sudo to only the specific commands that require it rather than blanket `NOPASSWD:ALL`. |
| SEC-014 | Medium | `scripts/setup_wizard.ps1:708,1544` | Password is stored as plaintext `[string]` in the PowerShell `$state` hashtable. .NET strings are immutable and remain in memory until garbage collected. | Use `[System.Security.SecureString]` for password handling. Extract plaintext only at the moment of writing to the secrets file, then immediately clear and call `[GC]::Collect()`. |
| SEC-015 | Low | `scripts/setup_wizard.ps1:797-798` | Secure password overwrite uses `System.Random` instead of a cryptographically secure RNG. `System.Random` is predictable. | Use `[System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)` instead. |
| SEC-016 | Low | `docker/docker-compose.yml:8` | `USER_NAME` passed as a plain environment variable, visible in `docker inspect`. | Informational. Consider passing via Docker secrets if username is considered sensitive. |
| SEC-017 | ~~Medium~~ **Resolved** | `docker/configure_tools.sh` | ~~OpenAI API key written to `.sgptrc` in plaintext.~~ **Fixed in v1.3.0:** Shell-GPT config block removed (tool no longer installed). | ~~Consider a dedicated secrets manager.~~ Dead code removed. |
| SEC-018 | Medium | `docker/configure_tools.sh:257` | `export OPENAI_API_KEY="$api_key"` sets the key as a persistent environment variable, visible via `/proc/PID/environ`. | Source the key from file only when needed rather than exporting persistently. Use a wrapper script that reads the key ephemerally per-invocation. |
| SEC-019 | Low | `docker/lib/logging.sh:63` | GitHub token sanitization regex `gh[pousr]_[a-zA-Z0-9]{36,}` does not cover fine-grained tokens (`github_pat_` prefix). | Add pattern for `github_pat_[a-zA-Z0-9]{22,}`. Also consider patterns for GitLab (`glpat-`), npm (`npm_`), and Slack tokens. |
| SEC-020 | Low | `docker/lib/logging.sh:56-57` | OpenAI key sanitization: generic `sk-` regex could match Anthropic `sk-ant-` tokens before the specific pattern on line 60 is checked. Order matters. | Reorder to check most specific patterns first (`sk-ant-`, `sk-proj-`), then fallback to generic `sk-`. Use word-boundary assertions. |
| SEC-021 | Medium | `.github/workflows/release.yml:70` | `softprops/action-gh-release@v1` is a third-party action pinned only to a major version tag. Mutable and could be replaced with malicious code. Has `contents: write` permissions. | Pin to a specific commit SHA. Use Dependabot to monitor for updates. Apply same to `actions/checkout@v4`. |
| SEC-022 | Low | `.github/workflows/ci.yml:1-80` | CI workflow does not declare explicit `permissions`. Default `GITHUB_TOKEN` permissions depend on repository settings. | Add explicit `permissions: contents: read` at the workflow level to enforce least-privilege. |
| SEC-023 | Medium | `docker/docker-compose.yml:1-51` | No `network_mode` or custom network configuration. Container uses Docker's default bridge network with unrestricted outbound access. | Define a custom Docker network. Consider `internal: true` for networks that don't need internet, or implement egress rules. |
| SEC-024 | High | `docker/install_cli_tools.sh:302` | GitHub CLI GPG key fetched via curl and piped directly to `dd` as root. Compromised URL could inject a malicious GPG key, enabling backdoored APT packages. | Download the GPG key to a temp file, verify its fingerprint against the known GitHub CLI signing key, then install. |
| SEC-025 | Info | `.env:1-2` | Root `.env` file is tracked in git with `USER_NAME=testuser`. While no secrets currently present, its git-tracked status could lead to accidental secret leakage. | Add `.env` to root `.gitignore` and provide a `.env.example` template instead. |
| SEC-026 | Medium | `docker/entrypoint.sh:56-69` | Fallback password mechanism (`USER_PASSWORD_PLAIN` env var) undermines Docker Secrets approach. Password visible in `docker inspect`, process environment, and container logs. | Remove the env var fallback entirely, or log an explicit security warning and require `ALLOW_INSECURE_PASSWORD=1` opt-in. |

---

## 3. Updates & Dependencies Findings

| ID | Severity | File:Line | Finding | Recommendation |
|---|---|---|---|---|
| DEP-001 | ~~Medium~~ **Resolved** | `docker/Dockerfile:2` | ~~Base image `ubuntu:24.04` uses a mutable tag.~~ **Fixed in v1.3.0:** Pinned to SHA256 digest. | ~~Pin to a specific digest.~~ Done. |
| DEP-002 | High | `docker/Dockerfile:50` | Node.js 20.x (Juno) enters End-of-Life on **April 30, 2026** — fewer than 3 months away. After EOL, no security patches will be issued. | Migrate to Node.js 22.x LTS (Jod), supported until April 2027. Update to `setup_22.x`. |
| DEP-003 | High | `docker/Dockerfile:47` | Tailscale installed by piping a remote script directly into `sh` with no integrity verification. Supply-chain risk with full root privileges. | Download script first, verify checksum or GPG signature. Alternatively, use Tailscale's official APT repository with key pinning. |
| DEP-004 | High | `docker/Dockerfile:50` | NodeSource setup script piped directly into `bash`. NodeSource is **no longer the recommended installation method** for Node.js. | Use the official Node.js binary tarball with SHA256 verification, or `fnm`/`nvm` for user-scoped installs. |
| DEP-005 | High | `.github/workflows/release.yml:17` | `actions/checkout@v4` uses a floating major-version tag. Vulnerable to tag-reassignment attacks (cf. `tj-actions/changed-files` incident). | Pin to full commit SHA, e.g., `actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11`. |
| DEP-006 | High | `.github/workflows/release.yml:70` | `softprops/action-gh-release@v1` uses a floating tag. Has write access to repository contents and handles release artifacts including `.exe` files. | Pin to full commit SHA. Review action source periodically. |
| DEP-007 | High | `.github/workflows/ci.yml:14` | `actions/checkout@v4` in CI also uses a floating tag, same risk as DEP-005. | Pin to full commit SHA. |
| DEP-008 | Medium | `docker/install_cli_tools.sh:101` | npm packages installed with `@latest` or no version constraint. No `package-lock.json`. Version drift risk across installs. | Create `package.json` with exact versions and `package-lock.json`. Use `npm ci` for deterministic installs. |
| DEP-009 | Medium | `docker/install_cli_tools.sh:434` | pip packages installed with no version pinning and no `requirements.txt`. `--break-system-packages` used. | Create `requirements.txt` with pinned versions. Use `pip install -r requirements.txt`. |
| DEP-010 | Medium | `docker/install_cli_tools.sh:374` | Claude Code CLI installed by piping remote script into bash. Third instance of curl-pipe-shell. No integrity verification. | Download script, verify integrity, then execute. Document expected hash. |
| DEP-011 | Medium | `docker/auto_update.sh:1-273` | Auto-update script has no rollback capability. If `npm update -g` or `pip3 install --upgrade` introduces a breaking change, there is no revert mechanism. | Record current versions before updating. Implement a `--rollback` command. Consider Docker image tagging for recovery. |
| DEP-012 | Low | `docker/auto_update.sh:170` | `sudo apt-get upgrade -y -qq gh` passes `gh` as argument but `apt-get upgrade` does not accept package names — `gh` is silently ignored and ALL packages get upgraded. | Use `sudo apt-get install --only-upgrade gh -y -qq` to upgrade only `gh`. |
| DEP-013 | Medium | `docker/install_cli_tools.sh:521-548` | `update_cli_tools()` references removed packages: `shell-gpt`, `aider-chat`, `gemini-cli` and AWS CLI. Install function was cleaned up but update function still references removed tools. | Remove stale pip package references and AWS CLI update block to match current tool set. |
| DEP-014 | Medium | `.github/workflows/release.yml:29-31` | `ps2exe` installed via `Install-Module` with no version constraint. Supply-chain attack could inject malicious code into the compiled `.exe`. | Pin to specific version: `Install-Module -Name ps2exe -RequiredVersion X.Y.Z`. |
| DEP-015 | Low | `scripts/AI_Docker_Launcher.ps1:82` | `$script:AppVersion = "1.2.2"` hardcoded. CHANGELOG comparison table missing 1.2.2 entry. `[Unreleased]` link still points to `v1.2.1...HEAD`. | Update CHANGELOG version history and unreleased comparison link. |
| DEP-016 | Low | `scripts/AI_Docker_Launcher.ps1:87-126` | Update checker uses `[Version]::TryParse` which fails silently for semver pre-release tags (e.g., `v1.3.0-beta.1`), causing updates to be skipped. | Add explicit handling for pre-release suffixes. Log a warning when `TryParse` fails. |
| DEP-017 | Info | `docker/Dockerfile:56` | `pipx` is installed but never used. All pip packages use `pip3 install` directly. | Either remove pipx to reduce image size, or migrate to `pipx install` for proper isolation. |
| DEP-018 | Info | `docker/docker-compose.yml:1-51` | No Compose file format version specified. Older Docker Compose V1 may not parse correctly. | Add `version: '3.8'` for backward compatibility, or document minimum Docker Compose version. |
| DEP-019 | Medium | `.github/workflows/ci.yml:38-52` | Dockerfile validation fallback only checks for `FROM` instruction. No linting with `hadolint`. | Add `hadolint` to CI: `docker run --rm -i hadolint/hadolint < docker/Dockerfile`. |
| DEP-020 | Medium | `docker/Dockerfile:7-39` | System packages via `apt-get install` are not version-pinned. Combined with `rm -rf /var/lib/apt/lists/*`, exact versions are unrecoverable after build. | Pin critical packages or add a build step that records installed package versions to a manifest file. |

---

## 4. Best Practices Findings

| ID | Severity | File:Line | Finding | Recommendation |
|---|---|---|---|---|
| BP-001 | High | `docker/install_cli_tools.sh:1` | Missing `set -euo pipefail`. Uses `#!/bin/bash` without strict mode. While intentionally omitting `set -e` (documented), `set -u` and `set -o pipefail` are independently valuable and safe. | Add `set -uo pipefail` at top; use `\|\| true` on commands expected to fail. |
| BP-002 | High | `docker/auto_update.sh:1` | Missing `set -euo pipefail`. Same rationale as BP-001. | Add `set -uo pipefail` at top. |
| BP-003 | High | `docker/configure_tools.sh:1` | Missing `set -euo pipefail`. No strict mode and no comment explaining why. | Add `set -uo pipefail` at minimum. |
| BP-004 | High | `docker/Dockerfile:47` | Piping curl output directly to `sh` without integrity verification across multiple locations (Dockerfile:47, Dockerfile:50, install_cli_tools.sh:374). | Download scripts first, verify checksums, then execute. |
| BP-005 | ~~Medium~~ **Resolved** | `docker/Dockerfile:2` | ~~Unpinned base image `ubuntu:24.04`.~~ **Fixed in v1.3.0:** Pinned to SHA256 digest. | ~~Pin to specific SHA256 digest.~~ Done. |
| BP-006 | Medium | `docker/Dockerfile:7-39` | Single monolithic `RUN apt-get install` layer installs 20+ packages. Impossible to cache stable base layer separately. Includes convenience tools (`nano`, `vim`, `tree`) that bloat the image. | Split into stable base layer and volatile layer. Consider multi-stage build. |
| BP-007 | Medium | `docker/docker-compose.yml:1-51` | No health check defined for the `ai` service. Docker Compose has no way to determine if the container is healthy. | Add `healthcheck` directive (e.g., `test: ["CMD", "pgrep", "-f", "tail"], interval: 30s`). |
| BP-008 | Medium | `docker/docker-compose.yml:1-51` | No resource limits (`deploy.resources.limits`). Container can consume unbounded CPU and memory. | Add resource limits (e.g., `memory: 4G`, `cpus: '4.0'`). |
| BP-009 | Medium | `docker/docker-compose.yml:25-27` | SSH/Mosh ports always published regardless of `ENABLE_MOBILE_ACCESS` setting. | Use separate Compose override files or profiles. |
| BP-010 | Medium | `docker/install_cli_tools.sh:626` | Unquoted variable expansion: `sudo chown -R $(whoami):$(whoami) ${HOME}/`. | Quote: `sudo chown -R "$(whoami)":"$(whoami)" "${HOME}/"`. |
| BP-011 | ~~Medium~~ **Resolved** | `docker/install_cli_tools.sh` | ~~`update_cli_tools()` references removed tools.~~ **Fixed in v1.3.0:** Removed aider/cursor dead code from get_version and save_versions. | ~~Remove stale tool references.~~ Done. |
| BP-012 | Medium | `docker/configure_tools.sh:104,109,137` | Using `[ ! -z "$VAR" ]` instead of `[ -n "$VAR" ]`. Double negation, shellcheck SC2236. | Replace with `[ -n "$VAR" ]`. |
| BP-013 | ~~Medium~~ **Resolved** | `docker/configure_tools.sh` | ~~Shell-GPT config block still present for removed tool.~~ **Fixed in v1.3.0:** Removed shell-gpt config block and sgpt reference. | ~~Remove unused configuration functions.~~ Done (shell-gpt portion). |
| BP-014 | Medium | `docker/auto_update.sh:87,97,108,153` | Using `[ ! -z "$VAR" ]` instead of `[ -n "$VAR" ]` in multiple locations. | Replace all with `[ -n "$VAR" ]`. |
| BP-015 | Medium | `docker/auto_update.sh:187,211` | Unquoted `$(whoami)` in `chown` calls. | Quote: `chown "$(whoami)":"$(whoami)" "$LOG_FILE"`. |
| BP-016 | Medium | `docker/lib/logging.sh:1` | Missing `set -euo pipefail`. Exported functions don't include color variables, which will be undefined in subshells. | Document sourcing requirements. Either export color variables or move them to exported functions. |
| BP-017 | Low | `scripts/AI_Docker_Launcher.ps1:1-720` | No `Set-StrictMode -Version Latest` or `$ErrorActionPreference = 'Stop'`. | Add strict mode and error action preference at script top. |
| BP-018 | Low | `scripts/AI_Docker_Complete.ps1:1-1006` | No `Set-StrictMode` or `$ErrorActionPreference`. Also, `Sanitize-LogMessage` and `Check-ForUpdates` use non-approved PowerShell verbs. | Use approved verbs and add strict mode declarations. |
| BP-019 | Low | `scripts/setup_wizard.ps1:38` | Multiple functions use non-approved verbs: `Fix-LineEndings`, `Docker-Running`, `Run-Process-UI`, `Parse-WSLConfig`. | Rename to `Repair-LineEndings`, `Test-DockerRunning`, `Invoke-ProcessUI`, `Read-WSLConfig`. |
| BP-020 | Low | `.github/workflows/ci.yml:22` | CI only validates `scripts/*.ps1` (non-recursive). `scripts/build/*.ps1` is not validated. No shellcheck for `docker/*.sh` files. | Add recursive glob `scripts/**/*.ps1` and shellcheck step for shell scripts. |
| BP-021 | Low | `.github/workflows/ci.yml:1-80` | No caching strategy. CI runs without caching Docker layers, PowerShell modules, or build dependencies. | Add `actions/cache` for PowerShell modules and Docker layer caching. |
| BP-022 | Low | `.github/workflows/release.yml:70` | `softprops/action-gh-release@v1` — floating major version tag. | Pin to specific SHA for supply-chain safety. |
| BP-023 | Low | `.github/workflows/release.yml:37-45` | Build step runs `build_complete_exe.ps1` with `-NonInteractive` but the script uses `Read-Host` which blocks. | Ensure CI always provides `$env:GITHUB_ACTIONS` to skip the prompt. |
| BP-024 | ~~Info~~ **Resolved** | `README.md:13` | ~~Version badge hardcoded as `v1.0.0`.~~ **Fixed in v1.3.0:** Updated to v1.2.2. | ~~Update static badge.~~ Done. |
| BP-025 | ~~Info~~ **Resolved** | `README.md:110` | ~~Documentation references `sgpt` but Shell-GPT is no longer installed.~~ **Fixed in v1.3.0:** Replaced with `codex "explain this code"`. | ~~Replace with currently installed tool.~~ Done. |
| BP-026 | Info | `CONTRIBUTING.md:168` | Contributing guide says to "Add `set -e` for fail-fast behavior" but several production scripts deliberately omit it. | Update guide to reflect actual convention and recommend `set -uo pipefail`. |
| BP-027 | Info | `.gitignore:40` | `.secrets/` directory only excluded in `docker/.gitignore`, not root `.gitignore`. | Add `.secrets/` to root `.gitignore` for defense in depth. |
| BP-028 | Info | `docker/entrypoint.sh:36` | Useless use of `cat`: `cat "$secret_file" \| tr -d '\n\r'` (shellcheck SC2002). | Replace with `tr -d '\n\r' < "$secret_file"`. |
| BP-029 | Info | `scripts/build/build_complete_exe.ps1:157,159` | Build metadata: `company = "Your Company"` and `version = "2.0.0.0"` contradict actual project values. | Update metadata to match actual project details. |
| BP-030 | Info | `docker/setup_mobile_access.sh:1-184` | Inconsistent error-handling: checks `$?` manually after commands instead of using `set -e` or `if ! command; then` pattern. | Add `set -euo pipefail` and use `if ! command; then` pattern. |

---

## 5. Code Quality Findings

| ID | Severity | File:Line | Finding | Recommendation |
|---|---|---|---|---|
| CQ-001 | High | `scripts/setup_wizard.ps1` (2,373 lines) | Monolithic script violates single responsibility. Contains UI form construction, Docker orchestration, WSL config management, password security, process execution, and pre-flight checks in one flat script. | Split into at least 4 modules: `WizardUI.ps1`, `DockerOps.ps1`, `WSLConfig.ps1`, `SecurityHelpers.ps1`. Dot-source from a thin orchestrator. |
| CQ-002 | High | `launch_claude.ps1:18-30`, `launch_vibe_kanban.ps1:18-30`, `AI_Docker_Launcher.ps1:57-72` | DRY violation: `Write-AppLog` function duplicated three times with nearly identical implementations. Only the component tag differs. | Extract a shared `AppLogging.ps1` module with a component name parameter. |
| CQ-003 | High | `launch_claude.ps1:52-75`, `launch_vibe_kanban.ps1:52-75` | DRY violation: `Find-Docker` and `DockerOk` functions are copy-pasted between launcher scripts. Character-for-character identical. | Extract a shared `DockerHelpers.ps1` module. |
| CQ-004 | High | `launch_claude.ps1:127-152`, `launch_vibe_kanban.ps1:127-152` | DRY violation: `.env` file parsing logic duplicated across 3 scripts, each with its own regex-based parser. | Create a single `Read-EnvFile` function in a shared module. |
| CQ-005 | Medium | `install_cli_tools.sh:29-34`, `auto_update.sh:42-46`, `configure_tools.sh:29-35` | DRY violation: ANSI color variables and `print_status`/`print_success`/`print_error` helpers duplicated in every shell script. | Move into existing `docker/lib/logging.sh` or create `docker/lib/colors.sh`. |
| CQ-006 | ~~Medium~~ **Resolved** | `docker/install_cli_tools.sh` | ~~Dead code: references to removed tools (aider, cursor).~~ **Fixed in v1.3.0:** Removed aider/cursor from get_version and save_versions. | ~~Remove stale references.~~ Done. |
| CQ-007 | Medium | `docker/configure_tools.sh:312-416` | Dead code: ~120 lines of configure functions for tools not installed (AWS, Azure, GCloud, Codeium). | Remove unused configuration functions. |
| CQ-008 | Medium | `docker/claude_wrapper.sh:1-3` | Dead code: entire file is obsolete. Assumes Claude installed via npm at `/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js`, but Claude now uses native installer at `~/.local/bin/claude`. | Delete `claude_wrapper.sh` or update path. Verify no references remain. |
| CQ-009 | High | `install_cli_tools.sh:7-8`, `auto_update.sh:12-13`, `configure_tools.sh:1` | Inconsistent error-handling strategy. `entrypoint.sh` uses `set -euo pipefail`, but `configure_tools.sh` has neither strict mode nor a comment explaining why. | Add `set -euo pipefail` or explicit documentation to all scripts for consistent strategy. |
| CQ-010 | Medium | `setup_wizard.ps1:73-78`, `AI_Docker_Launcher.ps1:129-132` | Magic numbers: hardcoded color values scattered and duplicated across files. | Extract into shared `Theme.ps1` module. |
| CQ-011 | Medium | `setup_wizard.ps1:375-511`, `setup_wizard.ps1:515-696` | `Run-Process-UI` (136 lines) and `Run-Process-WithTerminal` (181 lines) share significant structural overlap but differ in output handling. | Extract shared process lifecycle into a base helper. Have variants call it with different output strategies. |
| CQ-012 | Low | `setup_wizard.ps1:1496` | Bug: string interpolation inside single quotes. `'[WARNING] Could not kill process: $($_.Exception.Message)'` will display the literal string instead of the exception. | Change to double quotes. |
| CQ-013 | Medium | `setup_wizard.ps1:2097` | Magic number: 300-second timeout hardcoded without named constant. Same pattern at `launch_vibe_kanban.ps1:286` (90s) and `launch_claude.ps1:164` (120s). | Define named constants (e.g., `$INSTALL_TIMEOUT_SECONDS = 300`). |
| CQ-014 | Medium | `tests/run_tests.ps1:428` | Bug: `$userManualFile` used before defined. Referenced in Phase 6 Vibe Kanban tests but assigned at line 511 in Phase 8. Test always passes vacuously. | Move `$userManualFile` assignment before line 428. |
| CQ-015 | Medium | `docker/configure_tools.sh:104,109,137` | Inconsistent null/empty check: `[ ! -z "$VAR" ]` vs `[ -n "$VAR" ]` used elsewhere. | Standardize on `[ -n "$VAR" ]` throughout. |
| CQ-016 | Medium | `docker/configure_tools.sh:573-597` | Unbounded recursion in `interactive_configure`. Invalid user choices trigger recursive self-calls. Repeated invalid inputs cause stack overflow. | Replace recursion with a `while true` loop. Use `break`/`continue`. |
| CQ-017 | Low | `docker/auto_update.sh:83-91` | ANSI color codes written to log files. Logs should contain plain text for parseability. | Strip ANSI codes when writing to files. Use colors only for terminal output. |
| CQ-018 | Medium | `setup_wizard.ps1:1856-1864` | Race condition: concurrent `.env` file modifications. Multiple scattered `Add-Content` and `Out-File` calls target `.env` with no file locking. | Consolidate all `.env` writes to use a single `Update-EnvFile` helper with read-modify-write. |
| CQ-019 | High | `setup_wizard.ps1:720,1856` | Two different `.env` files. `$script:envPath` points to `scripts/.env` while force rebuild code uses `docker/.env`. Docker Compose reads from docker directory but credentials written to scripts directory. | Unify to a single `.env` file location. Ensure Docker Compose and launcher scripts reference the same file. |
| CQ-020 | Medium | `docker/entrypoint.sh:280` | `exec tail -f /dev/null` as container keep-alive prevents proper signal handling (SIGTERM) for graceful shutdown. | Use `exec sleep infinity` (more signal-friendly) or `tini` init system for signal handling and zombie reaping. |
| CQ-021 | Low | `scripts/build/build_complete_exe.ps1:157` | Hardcoded placeholder metadata: `"Your Company"` in `Invoke-ps2exe` call. Template value never updated. | Replace with actual organization name or make configurable. |
| CQ-022 | Low | `scripts/build/build_complete_exe.ps1:159` | Version mismatch: EXE compiled with `-version "2.0.0.0"` but launcher declares `$script:AppVersion = "1.2.2"`. | Use single source of truth for version. |
| CQ-023 | Low | `install_cli_tools.sh:14-15`, `auto_update.sh:15-18`, `configure_tools.sh:7-10` | DRY violation: npm global path setup repeated verbatim across three scripts. | Extract into shared `lib/npm_setup.sh`. |
| CQ-024 | Medium | `setup_wizard.ps1:49` | Hardcoded file list in `Fix-LineEndings` omits most scripts. Lists `'entrypoint.sh', 'setup.sh', 'claude_wrapper.sh'` but misses 6+ scripts. `setup.sh` does not exist. | Use `Get-ChildItem *.sh` wildcard instead of hardcoded list. Remove non-existent `setup.sh`. |
| CQ-025 | Medium | `docker/entrypoint.sh:36` | Unnecessary use of `cat` (UUOC): `cat "$secret_file" \| tr -d '\n\r'`. | Replace with `tr -d '\n\r' < "$secret_file"`. |
| CQ-026 | Low | `docker/configure_tools.sh:458` | Magic model string: `model = "gpt-5.2-codex"` hardcoded. Will become stale as models change. | Extract as configurable variable at script top. |
| CQ-027 | Medium | `scripts/launch_claude.ps1:242` | Potential command injection via `$userName`. Interpolated directly into shell command with no validation against safe pattern. Same issue in `launch_vibe_kanban.ps1`. | Validate `$userName` against `^[a-zA-Z0-9_-]+$` before use. |
| CQ-028 | Low | `tests/run_tests.ps1` | Test coverage gap: all tests are integration/smoke tests (file existence, string matching). No unit tests for business logic functions like `Parse-WSLConfig`, `Sanitize-LogMessage`, `Fix-LineEndings`. | Add Pester-based unit tests for PowerShell functions and BATS/shunit2 tests for shell functions. |
| CQ-029 | Medium | `docker/setup_remote_connection.sh:128` | Unsanitized user input: SSH key read via `read -p` with fallback path that bypasses validation in `add_ssh_key.sh`. Direct `echo "$ssh_key" >> ~/.ssh/authorized_keys` skips format checks. | Remove the fallback `echo` append. Rely solely on `add-ssh-key` which includes format validation. |
| CQ-030 | Low | `scripts/AI_Docker_Launcher.ps1:82-84` | Configuration values embedded in code. `$script:DockerDesktopPath` assumes default install location. | Use registry lookup or `Get-Command` instead of hardcoded path. |

---

## Prioritized Action Items

### Immediate (High-Impact, Security-Critical)

1. **Pin GitHub Actions to SHA hashes** — SEC-021, DEP-005/006/007
   - Files: `.github/workflows/release.yml`, `.github/workflows/ci.yml`
   - Effort: Low | Impact: High (supply-chain defense)

2. **Eliminate curl-pipe-shell patterns** — SEC-002/003/004/024, DEP-003/004, BP-004
   - Files: `docker/Dockerfile`, `docker/install_cli_tools.sh`
   - Effort: Medium | Impact: High (supply-chain defense)

3. **Harden SSH configuration** — SEC-008, SEC-009
   - Files: `docker/setup_mobile_access.sh`
   - Effort: Low | Impact: High (exposed network service)

4. **Migrate Node.js to 22.x LTS** — DEP-002
   - Files: `docker/Dockerfile`
   - Effort: Low | Impact: High (EOL in < 3 months)

5. **Unify `.env` file paths** — CQ-019
   - Files: `scripts/setup_wizard.ps1`, launcher scripts
   - Effort: Medium | Impact: High (credential/config reliability)

### Short-term (Next Release Cycle)

6. **Add `set -uo pipefail` to shell scripts** — BP-001/002/003, CQ-009
   - Files: `install_cli_tools.sh`, `auto_update.sh`, `configure_tools.sh`, `setup_mobile_access.sh`
   - Effort: Low | Impact: Medium

7. **Remove dead code** — ~~CQ-006~~ ~~BP-011~~ ~~BP-013~~ (resolved in v1.3.0), CQ-007/008, DEP-013 remaining
   - Files: `configure_tools.sh` (AWS/Azure/GCloud), `claude_wrapper.sh`
   - Effort: Low | Impact: Medium (maintenance burden)

8. **Fix username/password validation** — UX-001, CQ-027
   - Files: `setup_wizard.ps1`, `launch_claude.ps1`, `launch_vibe_kanban.ps1`
   - Effort: Low | Impact: Medium (security + UX)

9. **Add Docker Compose health check and resource limits** — BP-007/008
   - Files: `docker/docker-compose.yml`
   - Effort: Low | Impact: Medium

10. **Strengthen fail2ban configuration** — SEC-010
    - Files: `docker/fail2ban-jail.local`
    - Effort: Low | Impact: Medium

11. **Conditionally expose SSH/Mosh ports** — SEC-011, BP-009
    - Files: `docker/docker-compose.yml`
    - Effort: Medium | Impact: Medium

12. **Pin npm/pip package versions** — SEC-006/007, DEP-008/009
    - Files: `docker/install_cli_tools.sh`
    - Effort: Medium | Impact: Medium (reproducibility + security)

### Medium-term (Planned Improvements)

13. **Extract shared PowerShell modules** — CQ-002/003/004, UX-011, CQ-010
    - Create: `scripts/lib/AppLogging.ps1`, `scripts/lib/DockerHelpers.ps1`, `scripts/lib/Theme.ps1`
    - Effort: Medium | Impact: Medium (maintainability)

14. **Refactor setup_wizard.ps1** — CQ-001, CQ-011
    - Split 2,373-line monolith into focused modules
    - Effort: High | Impact: Medium (maintainability)

15. **Add progress feedback for long operations** — UX-008/009/010
    - Files: `launch_claude.ps1`, `launch_vibe_kanban.ps1`
    - Effort: Medium | Impact: Medium (user experience)

16. **Add CI linting** — BP-020, DEP-019
    - Add shellcheck and hadolint to CI pipeline
    - Effort: Low | Impact: Medium

17. **Implement auto-update rollback** — DEP-011
    - Files: `docker/auto_update.sh`
    - Effort: High | Impact: Medium

18. **Consolidate shell script utilities** — CQ-005/023
    - Move shared code into `docker/lib/` modules
    - Effort: Medium | Impact: Low (maintainability)

### Low Priority (When Convenient)

19. **Fix PowerShell verb naming** — BP-018/019
20. **Add strict mode to PowerShell scripts** — BP-017/018
21. **Fix build metadata** — CQ-021/022, BP-029
22. ~~**Update README version badge and stale references**~~ — ~~BP-024/025~~ **Resolved in v1.3.0**
23. **Improve keyboard navigation** — UX-006
24. **Add unit test coverage** — CQ-028
25. **Fix `Fix-LineEndings` file list** — CQ-024
26. **Fix unbounded recursion in `interactive_configure`** — CQ-016
27. **Fix test variable ordering bug** — CQ-014
28. **Fix single-quote interpolation bug** — CQ-012

---

*Report generated by comprehensive static analysis of all application source files. All file paths and line numbers verified against the current codebase on the `feature/wsl-memory-config` branch (commit `0c1b895`).*
