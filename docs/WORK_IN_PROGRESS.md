# Work In Progress - Claude Code Native Installer Migration

**Date:** 2026-01-22
**Branch:** `fix/claude-native-installer`
**Issue:** #26 - [Migration]: Update Claude Code installation from npm to native installer
**Status:** Testing Round 2

## Background

Claude Code has officially deprecated npm installation in favor of a native installer. The announcement:
> "Claude Code has switched from npm to native installer. Run `claude install` or see https://docs.anthropic.com/en/docs/claude-code/getting-started for more options."

**Key differences:**
| Aspect | npm (deprecated) | Native Installer |
|--------|-----------------|------------------|
| Install command | `npm install -g @anthropic-ai/claude-code` | `curl -fsSL https://claude.ai/install.sh \| bash` |
| Auto-updates | No | Yes (background) |
| Node.js required | Yes | No |
| Binary location | `~/.npm-global/bin/claude` | `~/.claude/bin/claude` |

## Files Modified

### 1. `docker/install_cli_tools.sh`
- Replaced npm installation with native curl installer
- Added robust detection logic that verifies Claude **actually works** (not just exists)
- Detects ANY npm installation path: `.npm-global`, `/usr/local/`, `node_modules`
- Added `cleanup_old_installations()` function for `--force` flag
- Cleanup removes: npm packages, system wrappers, entire `~/.claude` directory
- Updated `get_version()` to use `claude --version`
- Added `~/.claude/bin` to PATH

### 2. `docker/auto_update.sh`
- Added note that Claude auto-updates in background
- Logs Claude version for visibility during updates
- Added `~/.claude/bin` to PATH

### 3. `docker/entrypoint.sh`
- Updated `.bashrc` template to include `~/.claude/bin` in PATH
- Updated `.profile` template to include `~/.claude/bin` in PATH

### 4. `docker/configure_tools.sh`
- Added `~/.claude/bin` to PATH
- `is_configured claude` now verifies binary works BEFORE checking config files

## Testing Round 1 - FAILED

**Issue discovered:** Script detected Claude as "already installed via native installer" when it was actually a broken system-wide npm installation.

**Root cause:**
1. `/usr/local/bin/claude` existed (broken wrapper from previous `sudo npm install`)
2. Detection logic only checked for `.npm-global` path, missing `/usr/local/` installations
3. `command_exists` returned true for broken symlink/wrapper
4. Script skipped installation entirely
5. `config-status` returned "Configured" because config files existed (even though binary was broken)

## Fixes Applied for Round 2

1. Detection now checks if Claude **actually works** (executes `claude --version`)
2. Detection checks for ANY npm path: `.npm-global`, `/usr/local/`, `node_modules`
3. Broken installations trigger fresh native install
4. Script removes broken `/usr/local/bin/claude` wrappers
5. `config-status` now verifies Claude binary works before checking config
6. **`--force` now runs comprehensive cleanup before install:**
   - `npm uninstall -g @anthropic-ai/claude-code`
   - `sudo rm -f /usr/local/bin/claude`
   - `rm -rf ~/.claude` (entire directory - auth doesn't carry over anyway)
   - Removes other npm CLI packages (Gemini, Codex, vibe-kanban)
   - `npm cache clean --force`
7. Marker file now verifies Claude works, not just exists

## Testing Round 2 - IN PROGRESS

User running Force Rebuild to test fixes.

**Expected behavior:**
1. Cleanup runs first, removing all old installations
2. Native installer runs: `curl -fsSL https://claude.ai/install.sh | bash`
3. Claude binary installed at `~/.claude/bin/claude`
4. User needs to re-authenticate with `claude` command

**Expected log output:**
```
[INFO] Cleaning up old CLI installations...
[INFO] Removing old Claude Code installations...
[INFO] Removing ~/.claude directory (you will need to re-authenticate)...
[INFO] Removing old npm CLI packages...
[SUCCESS] Cleanup complete
...
[INFO] Installing Claude Code CLI via native installer...
[SUCCESS] Claude Code CLI installed successfully via native installer
```

**Verification after rebuild:**
```bash
which claude
# Expected: /home/<user>/.claude/bin/claude

claude --version
# Expected: Shows version

config-status
# Expected: Claude shows as "Not configured" until you run 'claude' and authenticate
```

## Commit History

```
a3e7cbe fix: Improve Claude detection and add comprehensive cleanup for --force
b09fda1 docs: Add work in progress context for Claude native installer migration
229c968 fix: Migrate Claude Code from npm to native installer
```

## If Test Passes - Next Steps

1. Create PR for the branch
2. Review changes
3. Merge to main
4. Remove this WIP document

## If Test Fails - Debug Steps

1. Check which claude binary is being found: `which claude`
2. Check if it works: `claude --version`
3. Check PATH: `echo $PATH`
4. Check for leftover files: `ls -la ~/.claude/ /usr/local/bin/claude 2>/dev/null`
5. Check install log in terminal output for errors

## References

- [Claude Code Getting Started](https://code.claude.com/docs/en/getting-started)
- [Claude Code Setup](https://code.claude.com/docs/en/setup)
- Issue #26: https://github.com/Cainmani/ai-docker-cli-setup/issues/26
- Branch: https://github.com/Cainmani/ai-docker-cli-setup/tree/fix/claude-native-installer
