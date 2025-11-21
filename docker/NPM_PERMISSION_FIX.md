# NPM Permission Issues - Fixed

## Problem Summary

The installation process was failing because npm global packages were being installed with `sudo`, which caused permission conflicts:

1. Installation scripts ran as the user but used `sudo npm install -g`
2. This tried to write to `/usr/local/lib/node_modules` (root-owned directory)
3. npm would create files owned by root, causing EACCES errors
4. The installation marker file was never created, causing infinite wait loops
5. Users couldn't install npm packages without sudo

## Root Cause

The scripts used `sudo npm install -g` commands which:
- Install packages to system directories (`/usr/local/lib/node_modules`)
- Create permission conflicts between root and user ownership
- Prevent users from installing packages without sudo
- Break npm's normal permission model in containerized environments

## Solution Implemented

### 1. Configure npm to use user-local directory (entrypoint.sh:31-33)

```bash
# Configure npm to use user-local directory for global packages
su - "$USER_NAME" -c "mkdir -p /home/$USER_NAME/.npm-global"
su - "$USER_NAME" -c "npm config set prefix '/home/$USER_NAME/.npm-global'"
```

This configures npm to install "global" packages in `~/.npm-global` instead of `/usr/local`.

### 2. Add npm PATH to .profile for login shells (entrypoint.sh:103-127)

```bash
# Create .profile to set PATH for login shells (used by 'su -')
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
```

The `su - "$USER_NAME"` command creates a login shell, which sources `.profile` but not `.bashrc`.

### 3. Add npm PATH to .bashrc for interactive shells (entrypoint.sh:57)

```bash
# Add npm global and local bin to PATH
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
```

Ensures the npm bin directory is in PATH for interactive shell sessions.

### 4. Remove ALL `sudo` from npm commands

Changed in **install_cli_tools.sh**:
- Line 105: `sudo npm install -g @anthropic-ai/claude-code@latest` → `npm install -g ...`
- Line 117: `sudo npm install -g @google/gemini-cli@latest` → `npm install -g ...`
- Line 163: `sudo npm install -g @openai/codex@latest` → `npm install -g ...`
- Line 198: `sudo npm install -g continue@latest` → `npm install -g ...`
- Line 217: `sudo npm install -g tabnine-cli@latest` → `npm install -g ...`
- Line 298: `sudo npm install -g tldr` → `npm install -g ...`
- Line 353: `sudo npm update -g` → `npm update -g`

Changed in **auto_update.sh**:
- Line 91: `sudo npm update -g` → `npm update -g`

## Files Modified

1. **docker/entrypoint.sh**
   - Added npm prefix configuration
   - Created .profile with PATH configuration
   - Ensured PATH is added to both new and existing .bashrc files

2. **docker/install_cli_tools.sh**
   - Removed `sudo` from all 7 npm install/update commands

3. **docker/auto_update.sh**
   - Removed `sudo` from npm update command

## Verification

A verification script has been created: `verify_npm_fixes.sh`

Run it inside the container to verify all fixes are working:

```bash
docker exec -u caide ai-cli bash /workspace/verify_npm_fixes.sh
```

The script checks:
1. ✓ npm prefix configuration
2. ✓ .npm-global directory exists
3. ✓ PATH in .bashrc
4. ✓ PATH in .profile
5. ✓ Current PATH includes npm-global
6. ✓ Can install npm packages without sudo
7. ✓ Correct directory ownership
8. ✓ Installation marker file
9. ✓ Claude CLI installation
10. ✓ GitHub CLI installation

## Testing Instructions

1. **Rebuild the Docker image:**
   ```bash
   docker compose build --no-cache
   ```

2. **Start fresh container:**
   ```bash
   docker compose down
   docker compose up -d
   ```

3. **Monitor installation progress:**
   ```bash
   docker logs -f ai-cli
   ```

4. **Verify inside container:**
   ```bash
   docker exec -u caide ai-cli bash
   # Inside container:
   npm config get prefix  # Should show /home/caide/.npm-global
   which claude           # Should show /home/caide/.npm-global/bin/claude
   npm install -g cowsay  # Should work without sudo
   ```

## Expected Results

After these fixes:
- ✅ Installation completes successfully in 3-5 minutes
- ✅ Marker file `/home/caide/.cli_tools_installed` is created
- ✅ Claude CLI is installed and accessible
- ✅ GitHub CLI is installed
- ✅ Users can install npm packages without sudo
- ✅ No EACCES permission errors

## Technical Details

### Why .profile instead of .bashrc?

The entrypoint script runs the installation with:
```bash
su - "$USER_NAME" -c "/usr/local/bin/install_cli_tools.sh"
```

The `su -` command creates a **login shell**, which:
- Sources `.profile` (or `.bash_profile`) but NOT `.bashrc`
- Needs PATH set in `.profile` for the installation script to find npm packages

Interactive shells source `.bashrc`, so we update both files to cover all scenarios.

### npm prefix configuration

```bash
npm config set prefix '/home/$USER_NAME/.npm-global'
```

This is stored in `~/.npmrc` and tells npm to install "global" packages to the user directory instead of the system directory. This is the recommended approach for:
- Docker containers
- Multi-user systems
- Non-root installations

### Permission model

Before fix:
```
/usr/local/lib/node_modules/  (owned by root)
├── package1/ (owned by root) ← EACCES error for normal user
└── package2/ (owned by root)
```

After fix:
```
~/.npm-global/  (owned by user)
├── bin/
│   ├── claude
│   ├── gh
│   └── tldr
└── lib/node_modules/
    ├── @anthropic-ai/claude-code/
    └── other-packages/
```

## Additional Notes

- The marker file is created even on partial failure (via trap in install script)
- Installation continues even if individual tools fail
- Logging captures errors for troubleshooting
- System tools (apt packages) still use sudo appropriately
- AWS, Azure, Google Cloud CLIs use their installer scripts with sudo (correct)
