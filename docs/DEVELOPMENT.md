# Development Guide

How to build, test, and release AI Docker CLI Manager.

For architecture details (embedded-file build system, Docker volumes, auth persistence, PowerShell gotchas), see [CLAUDE.md](CLAUDE.md) — it is the maintained source of truth for how the system works. This guide covers the contributor workflow.

---

## Repository Layout

```
ai-docker-sandbox/
├── scripts/                  # Windows-side PowerShell
│   ├── AI_Docker_Complete.ps1    # Main app template (files embedded as Base64 at build)
│   ├── AI_Docker_Launcher.ps1    # Lightweight launcher variant
│   ├── setup_wizard.ps1          # WinForms first-time setup wizard
│   ├── launch_claude.ps1         # Daily launcher (docker exec terminal)
│   ├── launch_vibe_kanban.ps1    # Vibe Kanban web UI launcher
│   ├── wsl_config.ps1            # WSL RAM/CPU detection
│   ├── docker_helpers.ps1        # Shared: Find-Docker, DockerOk
│   ├── setup_utils.ps1           # Shared: line endings, password file, npm repair
│   ├── env_utils.ps1             # Shared: .env parsing
│   ├── log_utils.ps1             # Shared: sanitized logging
│   └── build/build_complete_exe.ps1  # Builds the .exe (ps2exe)
├── docker/                   # Container-side bash + Docker config
│   ├── Dockerfile, docker-compose.yml
│   ├── entrypoint.sh             # Container init (user, volumes, symlinks)
│   ├── install_cli_tools.sh      # Installs AI CLI tools on first start
│   ├── configure_tools.sh        # Interactive tool auth/config wizard
│   ├── auto_update.sh            # Weekly cron updates
│   └── lib/logging.sh            # Shared logging with secret sanitization
├── tests/                    # Pester (.ps1) and bash test suites
└── docs/                     # User and developer documentation
```

## Building the .exe

Building requires Windows (ps2exe compiles to a .NET Framework executable).

```powershell
cd scripts\build
powershell -ExecutionPolicy Bypass -File build_complete_exe.ps1
# or double-click BUILD_NOW.bat
```

The build script Base64-encodes every file in its `$filesToEmbed` list into the `AI_Docker_Complete.ps1` template, then compiles with ps2exe (pinned to v1.0.17). At runtime the .exe extracts everything to `%LOCALAPPDATA%\AI-Docker-CLI\docker-files\`.

**Adding a new embedded file** requires touching several places — follow the checklist in [CLAUDE.md](CLAUDE.md#build-system).

In CI, the same build runs on `windows-latest` when a `v*.*.*` tag is pushed (`.github/workflows/release.yml`).

## Testing

### PowerShell (Pester)

```powershell
# Run everything
powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1

# Or a single suite
Invoke-Pester tests/SetupUtils.Tests.ps1
```

Suites: `WSLConfig`, `DockerHelpers`, `SetupUtils`, `EnvUtils`, `LogUtils`. Windows-only behavior (ACLs, Docker discovery) is skipped on Linux runners.

### Bash

```bash
bash tests/test_bash_fixes.sh              # structural regression assertions
bash tests/test_auth_persistence.sh        # auth volume/symlink behavior
bash tests/test_vibe_kanban_integration.sh # vibe kanban wiring
```

All bash suites run without Docker — they assert on script structure and use temp-dir mocks.

### CI

`.github/workflows/ci.yml` runs on every push/PR to main: PowerShell syntax checks, Pester tests, all bash test suites, Dockerfile validation, shellcheck and hadolint linting (non-blocking), and a pinned-version check.

## Shell Scripts & Line Endings

Windows CRLF endings break bash (`/bin/bash^M: bad interpreter`). Defenses, in order:

1. `.gitattributes` — `*.sh text eol=lf`, `*.ps1 text eol=crlf`
2. `scripts/fix_line_endings.ps1` — standalone converter (see its `$files` list)
3. `Fix-LineEndings` in `setup_utils.ps1` — runs automatically during setup pre-flight

All shell scripts use `set -euo pipefail` — use `${VAR:-}` / `${1:-}` for anything optional. Verify LF endings with `file <script>.sh` after editing.

## Conventions

- **Container name** `ai-cli` is hardcoded throughout — update all references if changing.
- **Logging**: never log raw values; use the sanitizing helpers (`log_utils.ps1` / `docker/lib/logging.sh`). They redact usernames, API keys, and tokens.
- **MessageBox text**: ASCII only — emoji and `•` render as garbage in WinForms.
- **Exit codes**: setup wizard exits 1 on cancel/failure; launchers check `ExitCode -eq 0` before claiming success.
- **Git author email**: commits must use the personal noreply email — see [CLAUDE.md](CLAUDE.md#git-configuration).

## Release Process

1. Complete the version bump checklist in [CLAUDE.md](CLAUDE.md#version-bump-checklist)
2. Add a `CHANGELOG.md` section and open a PR to main
3. After merge, tag and push:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. `release.yml` builds the .exe on `windows-latest`, generates a SHA256 checksum, and publishes the GitHub release automatically

## Developer Mode (live script editing)

Mount container scripts from the host instead of rebuilding:

```bash
# In docker/.env:
DEV_MODE=1

docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

Scripts are mounted read-only; for local development only.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `bad interpreter: /bin/bash^M` | Run `fix_line_endings.ps1`, then Force Rebuild |
| Container exits immediately | `docker logs ai-cli`; check entrypoint.sh has LF endings |
| Script changes not picked up | Docker cached the COPY layer — use Force Rebuild (`--no-cache`) |
| `claude: command not found` | Check `~/.local/bin/claude` exists in the container; re-run `install_cli_tools.sh` |
| Auth lost after rebuild | Verify `claude-config` and `tool-auth` volumes are mounted (see docker-compose.yml) |
