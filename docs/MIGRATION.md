# Migration Guide

This guide covers breaking changes between versions and how to upgrade.

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
5. **Re-authenticate all tools** - run `configure-tools` after rebuild

### What To Expect

| Item | Status |
|------|--------|
| Claude conversation history | **Preserved** - all your Claude conversations remain |
| Claude project settings | **Preserved** - project configurations remain |
| Claude user preferences | **Preserved** - settings remain |
| **All authentications** | **Re-login required** - Claude, GitHub CLI, and all other tools |

### Re-Authentication

After the rebuild, you'll need to re-authenticate **all** your tools:

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
| v1.1.3 | 2026-01 | Claude Code migrated to native installer (requires force rebuild + re-auth for all tools) |
| v1.0.0 | 2024-12 | Initial release |
