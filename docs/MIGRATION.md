# Migration Guide

This guide covers breaking changes between versions and how to upgrade.

---

## v1.4.0 - Runtime Stabilization

### What Changed

- Install status is structured (`STATUS=ok` or `STATUS=partial`) and readiness is withheld when required tools remain broken.
- Force/repair installation and updater failures preserve the last working CLI.
- Authentication and Codex config migrations are staged, verified, rollback-safe, and idempotent.
- AI router ownership uses PID/start-time validation; switching waits for the shared port without signalling unrelated processes.
- Mobile SSH/Mosh ports moved to `docker-compose.mobile.yml`; base Compose no longer publishes them.
- Compose project/image identity is fixed, cron is actually started, and the launcher detects stale container versions.

### Safe Upgrade

1. Identify the named volumes before changing anything:
   ```powershell
   docker volume ls --filter name=ai-docker
   ```
2. Back them up if required by your policy. Do **not** delete `claude-config`, `tool-auth`, `router-data`, `vibe-kanban-data`, or `ssh-keys`.
3. Remove any stale `FORCE_CLI_REINSTALL` line from `docker/.env`. The 1.4.0 wizard also removes it automatically.
4. Run **First Time Setup** with **Force Rebuild** once. Rebuilding replaces the image/container layer, not the named volumes.
5. Open the workspace and verify:
   ```bash
   cat ~/.cli_tools_installed
   claude --version
   codex --version
   configure-tools --diagnose
   test -L ~/.codex && test -L ~/.config/gh
   grep -n 'wire_api = "responses"' ~/.codex/config.toml 2>/dev/null || true
   ```
6. Reauthenticate only when the credential file is genuinely absent/expired. A rebuild alone is not a reason to sign in again.

### Recovery

If the marker says `STATUS=partial`, run `install_cli_tools.sh --repair`. Working tools are left in place. If diagnostics report DNS/TLS failure, verify proxy/custom-CA settings before reinstalling tools. If router startup fails, inspect `ss -tlnp` and the owned PID files under `~/.router-data`; do not use broad `pkill -f` commands.

---

## v1.2.2 - Auth Persistence

### What Changed

All tool credentials now persist across container rebuilds via Docker volumes. You no longer need to re-authenticate after running Force Rebuild.

### What You Need To Do

Run "First Time Setup" with **Force Rebuild** checked to pick up the new scripts. Your existing credentials will be automatically migrated into the persistence volumes on first start.

---

## v1.1.3 - Claude Code Native Installer Migration

### What Changed

Claude Code has been migrated from npm installation (`@anthropic-ai/claude-code`) to the **official native installer** provided by Anthropic.

**Why this change?**
- The npm package is deprecated and will no longer receive updates
- The native installer is Anthropic's recommended installation method
- Better auto-update support (updates happen in the background)
- Improved performance and reliability

### What You Need To Do

**Existing users must force rebuild the container:**

1. **Open AI Docker Manager**
2. **Click "First Time Setup"** (even though you've done it before)
3. **Check the "Force Rebuild" checkbox** in the setup wizard
4. **Complete the setup** - this will reinstall Claude with the native installer
5. **Authenticate your tools** - run `configure-tools` after rebuild

> **Note:** Starting from v1.2.2, credentials persist across rebuilds. If upgrading directly to v1.2.2+, you only need to authenticate once.

### What To Expect

| Item | Status |
|------|--------|
| Claude conversation history | **Preserved** - all your Claude conversations remain |
| Claude project settings | **Preserved** - project configurations remain |
| Claude user preferences | **Preserved** - settings remain |
| **All authentications** | **One-time re-login** - persists across future rebuilds (v1.2.2+) |

### Re-Authentication

After the rebuild, authenticate your tools:

```bash
# Run the configuration wizard
configure-tools

# Or authenticate individually:
claude                    # Opens browser for Anthropic auth
gh auth login             # GitHub CLI authentication
# ... etc for other tools
```

Your Claude conversation history will be available immediately after signing in.

### Verification

After the rebuild, verify the installation:

```bash
# Check Claude is installed at the correct location
which claude
# Expected: /home/<username>/.local/bin/claude

# Check version
claude --version
# Expected: 2.x.x (Claude Code)

# Check configuration status (after re-authenticating)
config-status
# All configured tools should show [OK]
```

### Troubleshooting

#### Claude command not found

If `claude` is not found after rebuild:

```bash
# Refresh your shell
source ~/.bashrc

# Or check PATH
echo $PATH | tr ':' '\n' | grep local
# Should include: /home/<username>/.local/bin
```

#### Authentication issues

If you have trouble authenticating:

```bash
# Check credentials file exists
ls -la ~/.claude/.credentials.json

# Try re-authenticating
claude auth login
```

#### Need a completely fresh start

If you want to start completely fresh (removes all Claude data including history):

```bash
# Inside the container
rm -rf ~/.claude ~/.local/share/claude ~/.local/bin/claude

# Then reinstall
curl -fsSL https://claude.ai/install.sh | sh
```

---

## Version History

| Version | Date | Breaking Changes |
|---------|------|------------------|
| v1.4.3 | 2026-07 | None — setup wizard install-wait raised to 15 min (no rebuild needed; launcher-only fix) |
| v1.4.2 | 2026-07 | None — adds the OpenCode CLI and a self-updating launcher (force rebuild recommended to install OpenCode) |
| v1.4.1 | 2026-07 | Router/Vibe Kanban dashboards now bind to the host loopback interface only — no longer reachable from the LAN (force rebuild/recreate required; use SSH mobile access for remote use) |
| v1.4.0 | 2026-07 | Mobile SSH/Mosh ports moved to `docker-compose.mobile.yml` — base Compose no longer publishes them (force rebuild recommended; install marker is upgraded automatically) |
| v1.2.4 | 2026-07 | None — dependency refresh (force rebuild recommended to get updated AI CLI tools) |
| v1.2.3 | 2026-07 | None — audit remediation release (force rebuild recommended to pick up container script fixes) |
| v1.2.2 | 2026-02 | None — credentials now persist across rebuilds (force rebuild recommended to pick up fixes) |
| v1.1.3 | 2026-01 | Claude Code migrated to native installer (requires force rebuild + one-time re-auth) |
| v1.0.0 | 2024-12 | Initial release |
