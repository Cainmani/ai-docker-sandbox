#!/usr/bin/env bash
set -euo pipefail

# Source logging library (if available)
if [ -f "/usr/local/lib/logging.sh" ]; then
    source "/usr/local/lib/logging.sh"
    LOG_FILE=$(init_logging "ENTRYPOINT" "entrypoint")
fi

# Helper function for logging (works with or without logging library)
entrypoint_log() {
    local level="$1"
    local message="$2"
    if [ -n "${LOG_FILE:-}" ]; then
        log_message "ENTRYPOINT" "$level" "$message" "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [ENTRYPOINT] $message"
    fi
}

# =============================================================================
# SECURITY: Docker Secrets Password Handling
# =============================================================================
# Password is read from Docker Secret (tmpfs) at /run/secrets/user_password
# This is more secure than environment variables because:
# 1. Secrets are stored in memory (tmpfs), not on disk
# 2. Secrets are not visible in 'docker inspect' output
# 3. Secrets are not exposed in /proc/*/environ
# =============================================================================

# Function to read password from Docker Secret
get_password_from_secret() {
    local secret_file="/run/secrets/user_password"
    if [ -f "$secret_file" ]; then
        # Read password, trim whitespace
        cat "$secret_file" | tr -d '\n\r'
        return 0
    fi
    return 1
}

# Function to clean up sensitive environment variables after use
cleanup_credentials() {
    entrypoint_log "INFO" "Cleaning up credential environment variables..."
    # Unset any password-related environment variables that might have been set
    unset USER_PASSWORD_PLAIN 2>/dev/null || true
    unset USER_PASSWORD_HASH 2>/dev/null || true
    unset PASSWORD 2>/dev/null || true
    entrypoint_log "INFO" "Credential cleanup complete"
}

# Required: USER_NAME from environment (.env or compose)
: "${USER_NAME:?Set USER_NAME env}"

# Get password from Docker Secret (preferred) or fall back to environment variables
USER_PASSWORD=""
if USER_PASSWORD=$(get_password_from_secret); then
    entrypoint_log "INFO" "Password loaded from Docker Secret (secure method)"
else
    # Fallback to environment variables for backwards compatibility
    if [ -n "${USER_PASSWORD_PLAIN:-}" ]; then
        USER_PASSWORD="$USER_PASSWORD_PLAIN"
        entrypoint_log "WARN" "Using password from environment variable (less secure - consider using Docker Secrets)"
    elif [ -n "${USER_PASSWORD_HASH:-}" ]; then
        # Special handling for pre-hashed passwords
        USER_PASSWORD="HASH:$USER_PASSWORD_HASH"
        entrypoint_log "WARN" "Using pre-hashed password from environment variable"
    fi
fi

# Create user if missing
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  # Password is ONLY required when creating a new user
  # After initial setup, the password file is replaced with "SETUP_COMPLETE" placeholder
  # This allows container restarts without needing the original password
  if [ -z "$USER_PASSWORD" ] || [ "$USER_PASSWORD" = "SETUP_COMPLETE" ]; then
      entrypoint_log "ERROR" "No valid password provided for new user creation."
      entrypoint_log "ERROR" "Use Docker Secret at /run/secrets/user_password or set USER_PASSWORD_PLAIN env"
      exit 1
  fi

  entrypoint_log "INFO" "Creating user: $USER_NAME"
  useradd -m -s /bin/bash "$USER_NAME"

  # Set password
  entrypoint_log "INFO" "Setting up password for user: $USER_NAME"
  if [[ "$USER_PASSWORD" == HASH:* ]]; then
    # Use pre-hashed password (SHA-512 format: $6$salt$hash)
    local_hash="${USER_PASSWORD#HASH:}"
    echo "$USER_NAME:$local_hash" | chpasswd -e
    entrypoint_log "INFO" "Password set using pre-hashed value"
  else
    # Hash the plain text password
    echo "$USER_NAME:$USER_PASSWORD" | chpasswd
    entrypoint_log "INFO" "Password set successfully"
  fi

  usermod -aG sudo "$USER_NAME"
  entrypoint_log "INFO" "User added to sudo group"

  # Allow passwordless sudo for this user
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER_NAME"
  chmod 0440 "/etc/sudoers.d/$USER_NAME"
  entrypoint_log "INFO" "Passwordless sudo configured for user"
else
  entrypoint_log "INFO" "User $USER_NAME already exists, skipping creation"
fi

# SECURITY: Clean up password variables immediately after use
unset USER_PASSWORD
cleanup_credentials

# Give user ownership of workspace
entrypoint_log "INFO" "Setting ownership of /workspace to $USER_NAME"
if ! chown -R "$USER_NAME:$USER_NAME" /workspace 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    entrypoint_log "WARN" "Could not change ownership of /workspace (may not exist or permission denied)"
fi

# CRITICAL: Ensure user's home directory has correct ownership
# This includes the .claude directory which is a Docker volume
entrypoint_log "INFO" "Setting ownership of /home/$USER_NAME to $USER_NAME"
if ! chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    entrypoint_log "WARN" "Could not change ownership of /home/$USER_NAME"
fi

# Ensure .claude directory exists with correct permissions
entrypoint_log "INFO" "Ensuring .claude directory exists with correct permissions"
mkdir -p "/home/$USER_NAME/.claude"
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.claude"
chmod 755 "/home/$USER_NAME/.claude"

# Persist ~/.claude.json across container rebuilds via symlink into claude-config volume
# This file stores hasCompletedOnboarding; without it Claude re-prompts setup
entrypoint_log "INFO" "Setting up ~/.claude.json persistence"
CLAUDE_ROOT_JSON="/home/$USER_NAME/.claude.json"
CLAUDE_ROOT_JSON_VOLUME="/home/$USER_NAME/.claude/_claude_root.json"
if [ -f "$CLAUDE_ROOT_JSON" ] && [ ! -L "$CLAUDE_ROOT_JSON" ]; then
    # Real file exists (pre-persistence migration): move into volume
    entrypoint_log "INFO" "Migrating existing ~/.claude.json into claude-config volume"
    mv "$CLAUDE_ROOT_JSON" "$CLAUDE_ROOT_JSON_VOLUME"
fi
if [ ! -f "$CLAUDE_ROOT_JSON_VOLUME" ]; then
    # First run: create minimal file so symlink target exists
    echo '{"hasCompletedOnboarding":false}' > "$CLAUDE_ROOT_JSON_VOLUME"
fi
# (Re)create symlink (handles rebuilds where container layer is fresh)
ln -sf "$CLAUDE_ROOT_JSON_VOLUME" "$CLAUDE_ROOT_JSON"
chown -h "$USER_NAME:$USER_NAME" "$CLAUDE_ROOT_JSON"
chown "$USER_NAME:$USER_NAME" "$CLAUDE_ROOT_JSON_VOLUME"

# Persist tool auth configs across container rebuilds via symlinks into tool-auth volume
entrypoint_log "INFO" "Setting up tool-auth persistence"
TOOL_AUTH_DIR="/home/$USER_NAME/.tool-auth"
mkdir -p "$TOOL_AUTH_DIR"

# Create subdirs and symlink each tool's config path
for tool_dir in gh openai gemini shell_gpt codex; do
    mkdir -p "$TOOL_AUTH_DIR/$tool_dir"
done

# Symlink ~/.config/<tool> directories
for tool_dir in gh openai gemini shell_gpt; do
    config_path="/home/$USER_NAME/.config/$tool_dir"
    volume_path="$TOOL_AUTH_DIR/$tool_dir"
    if [ -d "$config_path" ] && [ ! -L "$config_path" ]; then
        # Real directory exists (pre-persistence migration): copy contents into volume
        entrypoint_log "INFO" "Migrating $config_path into tool-auth volume"
        cp -a "$config_path"/. "$volume_path"/ 2>/dev/null || true
        rm -rf "$config_path"
    fi
    # Ensure parent exists and create symlink
    mkdir -p "/home/$USER_NAME/.config"
    ln -sfn "$volume_path" "$config_path"
done

# Symlink ~/.codex separately (not under ~/.config)
CODEX_CONFIG="/home/$USER_NAME/.codex"
CODEX_VOLUME="$TOOL_AUTH_DIR/codex"
if [ -d "$CODEX_CONFIG" ] && [ ! -L "$CODEX_CONFIG" ]; then
    entrypoint_log "INFO" "Migrating $CODEX_CONFIG into tool-auth volume"
    cp -a "$CODEX_CONFIG"/. "$CODEX_VOLUME"/ 2>/dev/null || true
    rm -rf "$CODEX_CONFIG"
fi
ln -sfn "$CODEX_VOLUME" "$CODEX_CONFIG"

chown -R "$USER_NAME:$USER_NAME" "$TOOL_AUTH_DIR"
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config"
chown -h "$USER_NAME:$USER_NAME" "$CODEX_CONFIG"
entrypoint_log "INFO" "Tool-auth persistence setup complete"

# Configure npm to use user-local directory for global packages
su - "$USER_NAME" -c "mkdir -p /home/$USER_NAME/.npm-global"
su - "$USER_NAME" -c "npm config set prefix '/home/$USER_NAME/.npm-global'"

# Create .bashrc with helpful configuration if it doesn't exist
if [ ! -f "/home/$USER_NAME/.bashrc" ]; then
  cat > "/home/$USER_NAME/.bashrc" << 'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Set up the prompt
PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@ai-cli\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Enable color support
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# Add npm global and local bin to PATH (Claude native installer uses ~/.local/bin)
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

# CLI tools aliases
# Note: These commands update container CLI tools only, not the Windows launcher app
alias update-container-tools='/usr/local/bin/auto_update.sh'
alias update-tools='/usr/local/bin/auto_update.sh'  # Legacy alias for compatibility
alias check-container-updates='/usr/local/bin/auto_update.sh --check'
alias check-updates='/usr/local/bin/auto_update.sh --check'  # Legacy alias for compatibility
alias configure-tools='/usr/local/bin/configure_tools.sh'
alias config-status='/usr/local/bin/configure_tools.sh --status'

# Show available CLI tools on login
# Note: $USER is set by bash at login time to the current username
if [ -f "$HOME/.cli_tools_installed" ]; then
  echo ""
  echo "+==============================================================+"
  echo "|          AI CLI Tools Environment Ready!                    |"
  echo "+--------------------------------------------------------------+"
  echo "| Available AI Tools:                                         |"
  echo "|   * claude       - Claude Code CLI                          |"
  echo "|   * gh           - GitHub CLI                               |"
  echo "|   * gemini       - Google Gemini CLI                        |"
  echo "|   * codex        - OpenAI Codex CLI                         |"
  echo "|   * python3      - OpenAI Python SDK (import openai)        |"
  echo "|                                                             |"
  echo "| Management Commands:                                        |"
  echo "|   * configure-tools         - Set up API keys/authentication|"
  echo "|   * config-status           - Check configuration status    |"
  echo "|   * update-container-tools  - Update CLI tools in container |"
  echo "|   * setup-remote-connection - Connect from phone/tablet     |"
  echo "+--------------------------------------------------------------+"
  echo "| NOTE: These commands update container tools only.           |"
  echo "|       To update the launcher app, download from GitHub.     |"
  echo "+==============================================================+"
  echo ""
  echo "First time? Run 'configure-tools' to set up your API keys!"
  echo "Phone access? Run 'setup-remote-connection' for guided setup!"
  echo ""
fi

# Load persisted API keys (survive container rebuilds)
if [ -f "${HOME}/.config/openai/api_key" ]; then
    export OPENAI_API_KEY="$(cat "${HOME}/.config/openai/api_key")"
fi

# Auto-change to workspace directory on login
cd /workspace 2>/dev/null || true
EOF
  chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.bashrc"
else
  # .bashrc already exists, ensure PATH includes npm global and local bin
  if ! grep -q "\.local/bin" "/home/$USER_NAME/.bashrc"; then
    echo "" >> "/home/$USER_NAME/.bashrc"
    echo "# Add npm global and local bin to PATH (Claude native installer uses ~/.local/bin)" >> "/home/$USER_NAME/.bashrc"
    echo 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> "/home/$USER_NAME/.bashrc"
    chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.bashrc"
  fi
fi

# Create .profile to set PATH for login shells (used by 'su -')
if [ ! -f "/home/$USER_NAME/.profile" ]; then
  cat > "/home/$USER_NAME/.profile" << 'EOF'
# ~/.profile: executed by the command interpreter for login shells.

# Add npm global and local bin to PATH (Claude native installer uses ~/.local/bin)
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

# If running bash, source .bashrc
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
EOF
  chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.profile"
else
  # .profile already exists, ensure PATH includes npm global and local bin
  if ! grep -q "\.local/bin" "/home/$USER_NAME/.profile"; then
    echo "" >> "/home/$USER_NAME/.profile"
    echo "# Add npm global and local bin to PATH (Claude native installer uses ~/.local/bin)" >> "/home/$USER_NAME/.profile"
    echo 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> "/home/$USER_NAME/.profile"
    chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.profile"
  fi
fi

# Install CLI tools on first run (runs as the user)
# If FORCE_CLI_REINSTALL is set, force reinstallation even if marker file exists
entrypoint_log "INFO" "Checking CLI tools installation..."
if [ "${FORCE_CLI_REINSTALL:-}" = "1" ]; then
  entrypoint_log "INFO" "Force reinstall requested - running install_cli_tools.sh --force"
  if ! su - "$USER_NAME" -c "/usr/local/bin/install_cli_tools.sh --force" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
      entrypoint_log "WARN" "Force installation completed with warnings - check install.log for details"
  fi
else
  entrypoint_log "INFO" "Running CLI tools installation..."
  if ! su - "$USER_NAME" -c "/usr/local/bin/install_cli_tools.sh" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
      entrypoint_log "WARN" "Installation completed with warnings - check install.log for details"
  fi
fi

# Setup auto-update cron job (weekly on Sunday at 2 AM)
if ! crontab -u "$USER_NAME" -l 2>/dev/null | grep -q "auto_update.sh"; then
  entrypoint_log "INFO" "Setting up auto-update cron job (weekly on Sunday at 2 AM)..."
  if (crontab -u "$USER_NAME" -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/auto_update.sh >/dev/null 2>&1") | crontab -u "$USER_NAME" - 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
      entrypoint_log "INFO" "Auto-update cron job configured successfully"
  else
      entrypoint_log "WARN" "Failed to setup auto-update cron job"
  fi
else
  entrypoint_log "INFO" "Auto-update cron job already configured, skipping"
fi

entrypoint_log "INFO" "Entrypoint initialization complete"

# Mobile Access Setup (optional - enabled via ENABLE_MOBILE_ACCESS=1)
if [ "${ENABLE_MOBILE_ACCESS:-0}" = "1" ]; then
    entrypoint_log "INFO" "Mobile access enabled - starting SSH/Mosh/tmux setup..."
    if /usr/local/bin/setup_mobile_access.sh "$USER_NAME" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        entrypoint_log "INFO" "Mobile access setup completed successfully"
    else
        entrypoint_log "WARN" "Mobile access setup completed with warnings"
    fi
else
    entrypoint_log "DEBUG" "Mobile access not enabled (set ENABLE_MOBILE_ACCESS=1 to enable)"
fi

# Keep container running
exec tail -f /dev/null
