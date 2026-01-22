# Work In Progress - Claude Code Native Installer Migration

**Date:** 2026-01-22
**Branch:** `fix/claude-native-installer`
**Issue:** #26 - [Migration]: Update Claude Code installation from npm to native installer
**Status:** Testing in progress

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

## Changes Made

### 1. `docker/install_cli_tools.sh`
- Replaced npm installation with native curl installer
- Added migration logic to detect existing npm installations
- Migrates npm users to native installer automatically
- Removes old npm package after successful migration
- Falls back to npm if native install fails
- Updated `get_version()` to use `claude --version`
- Added `~/.claude/bin` to PATH

### 2. `docker/auto_update.sh`
- Added note that Claude auto-updates in background
- Logs Claude version for visibility during updates
- Added `~/.claude/bin` to PATH

### 3. `docker/entrypoint.sh`
- Updated `.bashrc` template to include `~/.claude/bin` in PATH
- Updated `.profile` template to include `~/.claude/bin` in PATH
- Updated existing file update logic to check for `.claude/bin`

## Testing Completed

- [x] Shell script syntax validation (all pass)
- [x] Install URL reachability check (redirects to GCS correctly)
- [x] npm detection logic test (correctly identifies `.npm-global` path)

## Testing In Progress

- [ ] **Force Rebuild test** - User running First Time Setup with Force Rebuild
  - Should detect existing npm installation
  - Should install native version
  - Should remove old npm package
  - Should result in `which claude` showing `~/.claude/bin/claude`

## Expected Output During Rebuild

```
[INFO] Detected Claude Code installed via npm (deprecated)
[INFO] Migrating to native installer for auto-update support...
[INFO] Installing Claude Code CLI via native installer...
[SUCCESS] Claude Code CLI installed successfully via native installer
[INFO] Removing old npm installation...
[SUCCESS] Migration from npm to native installer complete
```

## Verification Commands (After Rebuild)

```bash
# Check Claude binary location (should be native, not npm)
which claude
# Expected: /home/<user>/.claude/bin/claude

# Check version works
claude --version

# Verify npm package is removed
npm list -g @anthropic-ai/claude-code
# Expected: empty/not found
```

## Next Steps

1. Complete Force Rebuild test
2. Verify migration worked correctly
3. Create PR for the changes
4. Review and merge

## Related PRs

- PR #24 (open) - DEV_MODE feature - unrelated, left open for future testing

## Commit History

```
229c968 fix: Migrate Claude Code from npm to native installer
```

## References

- [Claude Code Getting Started](https://code.claude.com/docs/en/getting-started)
- [Claude Code Setup](https://code.claude.com/docs/en/setup)
- Issue #26: https://github.com/Cainmani/ai-docker-cli-setup/issues/26
