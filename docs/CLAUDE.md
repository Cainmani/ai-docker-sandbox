# Claude AI Context File - AI Docker CLI Manager Project

**Last Updated:** July 11, 2026
**Project Version:** 1.4.1

---

## Project Overview

AI Docker CLI Manager is a Windows .exe that sets up a Docker container with multiple AI CLI tools pre-installed. Users run a setup wizard, which builds a Docker image, creates a container, and installs all tools automatically.

### Architecture

```
Windows (.exe)                          Docker Container (Linux)
┌─────────────────────┐                ┌──────────────────────────┐
│ AI_Docker_Complete   │  builds/runs  │ entrypoint.sh            │
│   ├─ setup_wizard    │──────────────>│   ├─ install_cli_tools   │
│   ├─ launch_claude   │  docker exec  │   ├─ configure_tools     │
│   └─ launch_vibe     │──────────────>│   └─ auto_update         │
└─────────────────────┘                └──────────────────────────┘
```

### How the .exe Works

1. `AI_Docker_Complete.ps1` is the template — all project files are Base64-embedded at build time
2. `build_complete_exe.ps1` reads files, encodes them, replaces placeholders, compiles via ps2exe
3. At runtime, the .exe extracts Docker files to `%LOCALAPPDATA%\AI-Docker-CLI\docker-files\`
4. Setup wizard runs as a separate PowerShell process from that directory

### Installed AI Tools

| Tool | Command | Install Method |
|------|---------|----------------|
| Claude Code CLI | `claude` | Native installer (`~/.local/bin/claude`) |
| GitHub CLI | `gh` | apt |
| Google Gemini CLI | `gemini` | npm (`@google/gemini-cli`) |
| OpenAI Codex CLI | `codex` | npm (`@openai/codex`) |
| OpenAI Python SDK | `python3 -c "import openai"` | pip |
| Vibe Kanban | `vibe-kanban` | npm |
| OpenCode | `opencode` | npm (`opencode-ai`) |

---

## Key Architecture Decisions

### Auth Persistence (v1.2.2)

Credentials persist across container rebuilds via Docker volumes + symlinks:

| Volume | Persists |
|--------|----------|
| `claude-config` | `~/.claude/` (OAuth creds, settings, conversations) |
| `tool-auth` | `~/.config/gh/`, `~/.config/openai/`, `~/.config/gemini/`, `~/.config/shell_gpt/`, `~/.codex/` |

`~/.claude.json` (onboarding flag) is symlinked into the `claude-config` volume.
Each tool config dir is symlinked into the `tool-auth` volume (e.g., `~/.config/gh` → `~/.tool-auth/gh`).

### Shell Script Strict Mode

All shell scripts use `set -euo pipefail`. This means:
- **Always use `${VAR:-}` for optional variables** (not `$VAR`)
- **Always use `${1:-}` for optional positional args** (not `$1`)
- Unguarded variables cause immediate script termination

### Structured Install Status

`~/.cli_tools_installed` records `STATUS=ok` or `STATUS=partial`, failed tools, timestamp, and verified versions. A partial status triggers targeted `--repair` on a later start; working tools are never removed merely because another tool failed. Legacy marker files remain readable and are upgraded after verification.

### Log Sanitization

All logging functions sanitize before writing to disk:
- **PowerShell**: `Sanitize-LogMessage` in each script (redacts Windows username, container username, API keys, tokens)
- **Shell**: `sanitize_message()` in `lib/logging.sh` (same patterns)
- Fallback logging paths also sanitize

---

## Load-Bearing Invariants

Rules a change can silently break without any test failing locally. Read before touching the areas they name.

### The EXE must run under a `Restricted` execution policy

`AI_Docker_Complete.ps1` runs inside a ps2exe host on the end user's machine, where the Windows **default** execution policy blocks loading any `.ps1` file from disk. Therefore, inside the EXE's own process:

- **Never dot-source an extracted `.ps1` file** (`. $path`). Load embedded content instead: `. ([ScriptBlock]::Create((Get-EmbeddedFileContent 'name.ps1')))`.
- **Never use PS 5.1 cmdlets that are actually `.psm1`-shipped functions** — `Get-FileHash`, `New-TemporaryFile`, `New-Guid`, `Format-Hex`, etc. Their module script can't autoload under `Restricted` policy, and the error surfaces as a blocking popup. Use .NET equivalents (the template's `Get-Sha256Hex` exists for exactly this reason). Binary cmdlets (`Invoke-WebRequest`, `Get-Content`, …) are fine.
- Child scripts are exempt — they are launched as separate processes with `-ExecutionPolicy Bypass` (keep that flag).
- CI's `exe-smoke` job launches the built EXE under `Restricted` policy to enforce this (`scripts/build/test_exe_smoke.ps1`); the release workflow runs the same gate before publishing.

### Runtime is Windows PowerShell 5.1, everywhere

The EXE embeds a 5.1 host and every child process is `powershell.exe` (never `pwsh.exe`). No PS7-only syntax (`??`, ternary) or .NET Core-only APIs — the dual 5.1/7 Pester CI matrix exists to catch this.

### Managed `~/.bashrc` block versioning

`docker/lib/entrypoint_helpers.sh` regenerates a marked block in the container user's `.bashrc` on every start. **Any change to the block's content requires bumping `MANAGED_BLOCK_VERSION`**, or existing containers keep the old block forever (same version = no-op). User-authored content outside the markers must survive byte-for-byte.

### Install marker semantics (`~/.cli_tools_installed`)

`STATUS=ok|partial` is parsed by the entrypoint: `partial` triggers `install_cli_tools.sh --repair` on the next container start, which reinstalls anything unhealthy. Consequences:

- A tool that is *deliberately* absent must be excluded from the marker's tool list, or repair will resurrect it. The AI router uninstall does this via the opt-out file `~/.router-data/routers-optout` — respect it in any new install/repair path.
- Never write `STATUS=ok` while a required tool (`claude gh codex`) is broken.

### npm version pins are literals, and the updater must not defeat them

- CI's `check-pinned-versions` job **greps `install_cli_tools.sh` for literal `name@version` strings** (e.g. `9router@0.5.18`). Keep the pins as literals in that file even when refactoring into variables.
- The weekly `auto_update.sh` runs a blanket `npm update -g`. Packages whose version must only change via a release (currently the credential-holding routers) are listed in the pin manifest `~/.npm-pinned-tools`, written by `install_cli_tools.sh` and re-applied by `auto_update.sh` after every update run. New "pinned forever" tools go in that manifest, not in ad-hoc updater logic.

### Release asset names are an API (self-update depends on them)

`Install-Update` in `AI_Docker_Complete.ps1` locates release assets **by exact name**: `AI_Docker_Manager_v<version>.exe` (fallback `AI_Docker_Manager.exe`) and the matching `<name>.sha256` file, and refuses to install anything whose checksum asset is missing or mismatched. Renaming release assets, changing the checksum file format (`<hash>  <filename>`), or dropping the `.sha256` uploads silently breaks self-update for every deployed EXE.

### Published ports bind to the host loopback interface only

`docker-compose.yml` publishes the web dashboards as `127.0.0.1:<port>:<port>`. The router dashboard stores linked AI provider credentials and has no authentication — never publish it (or new web UIs) without the `127.0.0.1` prefix. Remote/mobile access goes through the SSH ports in `docker-compose.mobile.yml`, not through dashboard ports.

### CLI routing contract

`~/.router-data/cli-routing.env` (written by `configure_tools.sh`, mode 600) exports `OPENAI_BASE_URL`/`OPENAI_API_KEY` (and optionally the Anthropic equivalents) and is sourced by the managed `.bashrc` block. Absent file = routing disabled and CLIs talk to providers directly. Anything that creates or removes it must go through the AI Router menu's logic so enable/disable stays symmetric.

---

## Build System

### Adding a New File to the .exe

When adding a new file that must be embedded in the .exe, update ALL of these:

1. **`scripts/build/build_complete_exe.ps1`** — add to `$filesToEmbed` array
2. **`scripts/AI_Docker_Complete.ps1`** — add to `$script:EmbeddedFiles` hashtable with `FILENAME_EXT_BASE64_HERE` placeholder
3. **`scripts/AI_Docker_Complete.ps1`** — if it's a script dependency (like `wsl_config.ps1`), add extraction logic where it's needed
4. **`docker/Dockerfile`** — add COPY and chmod if it goes in the container
5. **`scripts/fix_line_endings.ps1`** — add `.sh` files to the line endings fixer

### Build & Release Process

```bash
# After merging to main:
git tag v1.X.Y
git push origin v1.X.Y
# GitHub Actions builds the .exe and creates the release automatically
```

### Docker Build Cache

When shell scripts change but the Dockerfile doesn't, Docker may serve cached COPY layers. Users need **Force Rebuild** (which passes `--no-cache`) to pick up script changes.

---

## Developer Mode

Mount scripts directly from host for live editing (no rebuild needed):

```bash
# In docker/.env:
DEV_MODE=1

# Then:
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

Scripts are mounted read-only. Only for local development.

---

## File Structure

### Windows-side (PowerShell)

| File | Purpose |
|------|---------|
| `scripts/AI_Docker_Complete.ps1` | Main app template with embedded files |
| `scripts/AI_Docker_Launcher.ps1` | Lightweight launcher (no setup wizard) |
| `scripts/setup_wizard.ps1` | WinForms setup wizard |
| `scripts/wsl_config.ps1` | WSL detection functions (dot-sourced by wizard) |
| `scripts/launch_claude.ps1` | Launches Docker exec terminal |
| `scripts/launch_vibe_kanban.ps1` | Launches Vibe Kanban web UI |
| `scripts/build/build_complete_exe.ps1` | Builds the .exe from template |

### Container-side (Bash)

| File | Purpose |
|------|---------|
| `docker/entrypoint.sh` | Container init: user setup, volumes, .bashrc, tool install |
| `docker/install_cli_tools.sh` | Installs all CLI tools (runs on first start) |
| `docker/configure_tools.sh` | Interactive tool configuration wizard |
| `docker/auto_update.sh` | Weekly auto-update via cron |
| `docker/lib/logging.sh` | Centralized logging with sanitization and rotation |

### Docker Volumes

| Volume | Mount | Purpose |
|--------|-------|---------|
| `claude-config` | `~/.claude` | Claude credentials, settings, conversations |
| `tool-auth` | `~/.tool-auth` | Auth configs for gh, openai, gemini, codex, shell_gpt |
| `workspace` | `/workspace` | User's project files (bind mount to host) |
| `vibe-kanban-data` | `~/.vibe-kanban` | Vibe Kanban state |
| `ssh-keys` | `~/.ssh` | SSH keys for mobile access |

---

## PowerShell Gotchas

- **`-match`/`-notmatch` are case-insensitive** — use `-cmatch`/`-cnotmatch` for case-sensitive matching
- **`$PSScriptRoot`** — directory of the running script, NOT the working directory
- **WinForms runs in a separate process** — setup wizard is launched via `Start-Process powershell.exe`
- **Dot-sourced files must exist at `$PSScriptRoot`** — the .exe must extract dependencies alongside the script

---

## CI/CD

### GitHub Actions Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `ci.yml` | Push/PR to main | PowerShell syntax check, Pester tests (5.1 + 7), bash suites, Dockerfile validation, pinned version check, **EXE smoke test** (builds the real EXE and launches it under a `Restricted` execution policy) |
| `release.yml` | Push `v*.*.*` tag | Builds .exe on windows-latest, smoke-tests it under `Restricted` policy, creates GitHub release with checksums |

### Pester Tests

`tests/WSLConfig.Tests.ps1` — tests for `wsl_config.ps1` functions (RAM detection, CPU detection, profile recommendation, config parsing).

---

## Git Configuration

### Author Email (IMPORTANT)

Commits must use the personal GitHub noreply email so they're attributed to the correct account:

```
git config user.email "100510814+CaideSpries@users.noreply.github.com"
```

A pre-commit hook in `.git/hooks/pre-commit` enforces this — commits will be rejected if the email is wrong. If you clone fresh, the hook needs to be recreated (git hooks aren't tracked).

**Why:** The old email `Cainmani@users.noreply.github.com` attributes commits to the org account, not the personal GitHub profile.

---

## Version Bump Checklist

Before creating a release:

- [ ] `VERSION` — the single source of truth; the build script and release workflow read it (ps2exe `-version` and the EXE file name are derived automatically)
- [ ] `scripts/AI_Docker_Complete.ps1` — `$script:AppVersion = "X.Y.Z"`
- [ ] `scripts/AI_Docker_Launcher.ps1` — `$script:AppVersion = "X.Y.Z"`
- [ ] `README.md` — download badge version
- [ ] `CHANGELOG.md` — new version section
- [ ] `docs/MIGRATION.md` — version history row
- [ ] `docs/CLAUDE.md` — project version + last updated date
- [ ] Docs updated if user-facing features changed
