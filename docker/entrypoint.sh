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

# Route helper-module logging through the entrypoint logger, then source the
# shared helpers (failure-safe migrations, Codex config migration, managed
# .bashrc block, install-status parsing).
eh_log() { entrypoint_log "$1" "$2"; }
if [ -f "/usr/local/lib/entrypoint_helpers.sh" ]; then
    source "/usr/local/lib/entrypoint_helpers.sh"
fi

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
        tr -d '\n\r' < "$secret_file"
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

# Optional corporate CA. The host file is mounted explicitly by the documented
# CA override; only the in-container path is accepted here. Never bake private
# trust material into the image.
if [ -n "${CUSTOM_CA_CERT:-}" ]; then
  case "$CUSTOM_CA_CERT" in
    /usr/local/share/ca-certificates/*.crt)
      if [ -r "$CUSTOM_CA_CERT" ]; then
        entrypoint_log "INFO" "Installing configured corporate CA certificate"
        update-ca-certificates >/dev/null
        export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-$CUSTOM_CA_CERT}"
        export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
        export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
      else
        entrypoint_log "ERROR" "CUSTOM_CA_CERT is configured but unreadable"
        exit 1
      fi
      ;;
    *)
      entrypoint_log "ERROR" "CUSTOM_CA_CERT must point inside /usr/local/share/ca-certificates"
      exit 1
      ;;
  esac
fi

# Persist proxy/custom-CA trust settings for login shells (su -, SSH mobile
# access) and cron. The container env from compose only reaches PID 1; login
# shells and cron reset it, so tools run there (install_cli_tools.sh,
# auto_update.sh, configure-tools) would otherwise lose proxy/CA config.
if type write_proxy_ca_profile >/dev/null 2>&1; then
  write_proxy_ca_profile /etc/profile.d || true
fi

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

# Give user ownership of workspace.
# /workspace is typically a bind mount of a Windows folder (e.g. C:\AI_Work), where every file
# operation is a Windows<->WSL round trip and ownership is dictated by Docker's mount options,
# not per-file inodes. A blocking recursive chown over a large workspace stalled here for 15+
# minutes, and the CLI tools installer (which runs later in this script) never started. So:
# chown the mount point synchronously, skip the recursion when chown has no effect (Windows-
# backed mount), and otherwise run it in the background so startup never blocks on it.
entrypoint_log "INFO" "Setting ownership of /workspace to $USER_NAME"
if ! chown "$USER_NAME:$USER_NAME" /workspace 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    entrypoint_log "WARN" "Could not change ownership of /workspace (may not exist or permission denied)"
elif [ "$(stat -c %U /workspace 2>/dev/null)" != "$USER_NAME" ]; then
    entrypoint_log "INFO" "/workspace ownership is controlled by the host mount - skipping recursive chown"
else
    (
        chown -R "$USER_NAME:$USER_NAME" /workspace 2>/dev/null || true
        entrypoint_log "INFO" "Background recursive chown of /workspace finished"
    ) &
    entrypoint_log "INFO" "Recursive chown of /workspace continuing in background"
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
# Failure-aware migration: original file is kept working if the copy fails.
if ! safe_migrate_file "$CLAUDE_ROOT_JSON" "$CLAUDE_ROOT_JSON_VOLUME"; then
    entrypoint_log "WARN" "~/.claude.json migration failed - keeping the existing file in place"
fi
if [ ! -f "$CLAUDE_ROOT_JSON_VOLUME" ]; then
    # First run: create minimal file so symlink target exists
    echo '{"hasCompletedOnboarding":false}' > "$CLAUDE_ROOT_JSON_VOLUME"
fi
# (Re)create symlink (handles rebuilds where container layer is fresh), but
# never clobber a real file that a failed migration preserved.
if [ ! -f "$CLAUDE_ROOT_JSON" ] || [ -L "$CLAUDE_ROOT_JSON" ]; then
    ln -sf "$CLAUDE_ROOT_JSON_VOLUME" "$CLAUDE_ROOT_JSON"
    chown -h "$USER_NAME:$USER_NAME" "$CLAUDE_ROOT_JSON"
fi
chown "$USER_NAME:$USER_NAME" "$CLAUDE_ROOT_JSON_VOLUME"

# Persist tool auth configs across container rebuilds via symlinks into tool-auth volume
entrypoint_log "INFO" "Setting up tool-auth persistence"
TOOL_AUTH_DIR="/home/$USER_NAME/.tool-auth"
mkdir -p "$TOOL_AUTH_DIR"

# Create subdirs and symlink each tool's config path
for tool_dir in gh openai gemini codex opencode opencode-data; do
    mkdir -p "$TOOL_AUTH_DIR/$tool_dir"
done

# Symlink ~/.config/<tool> directories. safe_migrate_dir verifies the copy
# before removing the source: on failure the original directory (and its
# credentials) stays in place and in use, and no broken symlink is created.
mkdir -p "/home/$USER_NAME/.config"
for tool_dir in gh openai gemini opencode; do
    config_path="/home/$USER_NAME/.config/$tool_dir"
    volume_path="$TOOL_AUTH_DIR/$tool_dir"
    if ! safe_migrate_dir "$config_path" "$volume_path"; then
        entrypoint_log "WARN" "Migration of $config_path failed - continuing with the original directory"
    fi
done

# OpenCode keeps credentials (auth.json) in its XDG data dir, not ~/.config
mkdir -p "/home/$USER_NAME/.local/share"
OPENCODE_DATA="/home/$USER_NAME/.local/share/opencode"
if ! safe_migrate_dir "$OPENCODE_DATA" "$TOOL_AUTH_DIR/opencode-data"; then
    entrypoint_log "WARN" "Migration of $OPENCODE_DATA failed - continuing with the original directory"
fi

# Symlink ~/.codex separately (not under ~/.config)
CODEX_CONFIG="/home/$USER_NAME/.codex"
CODEX_VOLUME="$TOOL_AUTH_DIR/codex"
if ! safe_migrate_dir "$CODEX_CONFIG" "$CODEX_VOLUME"; then
    entrypoint_log "WARN" "Migration of $CODEX_CONFIG failed - continuing with the original directory"
fi

# One-time Codex config migration: deprecated wire_api = "chat" broke Codex
# connections after updates. Idempotent, backs up config.toml first, and only
# rewrites the wire_api value. (configure-tools --codex reuses the same helper.)
codex_config_toml="$CODEX_VOLUME/config.toml"
[ -f "$codex_config_toml" ] || codex_config_toml="$CODEX_CONFIG/config.toml"
if migrate_codex_wire_api "$codex_config_toml"; then
    entrypoint_log "INFO" "Codex config.toml migrated to wire_api = \"responses\""
fi

chown -R "$USER_NAME:$USER_NAME" "$TOOL_AUTH_DIR"
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config"
chown -h "$USER_NAME:$USER_NAME" "$CODEX_CONFIG" 2>/dev/null || true
chown -h "$USER_NAME:$USER_NAME" "$OPENCODE_DATA" 2>/dev/null || true
chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.local" "/home/$USER_NAME/.local/share" 2>/dev/null || true
entrypoint_log "INFO" "Tool-auth persistence setup complete"

# Ensure the AI router data volume exists with correct ownership. 9router and OmniRoute each
# keep their SQLite DB + linked-provider credentials under their own subdir (DATA_DIR is set to
# these by the launch wrappers), so both persist across container rebuilds without clashing.
entrypoint_log "INFO" "Setting up AI router data persistence"
ROUTER_DATA_DIR="/home/$USER_NAME/.router-data"
mkdir -p "$ROUTER_DATA_DIR/9router" "$ROUTER_DATA_DIR/omniroute"
chown -R "$USER_NAME:$USER_NAME" "$ROUTER_DATA_DIR"

# Configure npm to use user-local directory for global packages.
# su_preserving_env keeps proxy/CA vars alive across the login-shell reset; if the
# helper library failed to load, fall back to a plain su so startup still works.
if type su_preserving_env >/dev/null 2>&1; then
  su_run() { su_preserving_env "$USER_NAME" "$1"; }
else
  su_run() { su - "$USER_NAME" -c "$1"; }
fi
su_run "mkdir -p /home/$USER_NAME/.npm-global"
su_run "npm config set prefix '/home/$USER_NAME/.npm-global'"

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
# If tools are still installing (entrypoint hasn't finished), wait with a spinner
if [ ! -f "$HOME/.cli_tools_installed" ] && pgrep -f "install_cli_tools" >/dev/null 2>&1; then
  echo ""
  echo "  Tools are still installing, please wait..."
  _spinner='|/-\'
  _i=0
  while [ ! -f "$HOME/.cli_tools_installed" ] && pgrep -f "install_cli_tools" >/dev/null 2>&1; do
    printf "\r  Installing... %s " "${_spinner:$((_i % 4)):1}"
    _i=$((_i + 1))
    sleep 0.5
  done
  printf "\r                    \r"
fi
if [ -f "$HOME/.cli_tools_installed" ] && grep -q '^STATUS=partial' "$HOME/.cli_tools_installed" 2>/dev/null; then
  echo ""
  echo "  WARNING: CLI tools installation is INCOMPLETE."
  echo "  Failed tools: $(sed -n 's/^FAILED_TOOLS=//p' "$HOME/.cli_tools_installed")"
  echo "  Working tools remain available. Repair with: install_cli_tools.sh --repair"
  echo ""
elif [ -f "$HOME/.cli_tools_installed" ]; then
  echo ""
  echo "+==============================================================+"
  echo "|          AI CLI Tools Environment Ready!                    |"
  echo "+--------------------------------------------------------------+"
  echo "| Available AI Tools:                                         |"
  echo "|   * claude       - Claude Code CLI                          |"
  echo "|   * gh           - GitHub CLI                               |"
  echo "|   * gemini       - Google Gemini CLI                        |"
  echo "|   * codex        - OpenAI Codex CLI                         |"
  echo "|   * opencode     - OpenCode AI coding agent (TUI)           |"
  echo "|   * python3      - OpenAI Python SDK (import openai)        |"
  echo "|   * 9router      - Unified AI router (dashboard :20128)     |"
  echo "|   * omniroute    - Unified AI router (alt. to 9router)      |"
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

# Ensure the AI router dashboards (9router / OmniRoute) bind to 0.0.0.0 so they are reachable
# from the Windows host. Both are Next.js apps that bind to localhost (127.0.0.1) inside the
# container by default, which Docker's published port cannot reach. The wrappers call the real
# npm-installed binaries, so normal updates (npm update -g ...) apply unchanged.
#
# The wrapper logic lives in /usr/local/lib/router_utils.sh: PID-file + start-time process
# ownership (never a broad pkill), TERM -> KILL escalation, and ss-based waiting for the shared
# port to actually be released before the next router binds (a missing probe is an error, never
# "port is free"). install_managed_block installs a VERSIONED managed block into ~/.bashrc,
# replacing any known legacy generated block atomically without touching user-authored content.
entrypoint_log "INFO" "Installing managed AI router wrapper block in .bashrc"
install_managed_block "/home/$USER_NAME/.bashrc"
chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.bashrc"

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

# Suppress Ubuntu's first-login sudo hint ('To run a command as administrator (user "root"),
# use "sudo <command>". See "man sudo_root" for details.'). /etc/bash.bashrc prints it whenever
# a sudo-group user logs in and ~/.sudo_as_admin_successful doesn't exist - which is every
# rebuild, since the home directory is recreated. Harmless, but it reads like an error in the
# wizard console, so pre-create the flag file.
touch "/home/$USER_NAME/.sudo_as_admin_successful"
chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.sudo_as_admin_successful"

# Install CLI tools on first run (runs as the user). A previous PARTIAL install
# triggers --repair, which retries only missing/broken tools and never uninstalls
# tools that already work. Force repair remains an explicit interactive command;
# it is deliberately not accepted as a persistent container environment flag.
entrypoint_log "INFO" "Checking CLI tools installation..."
install_state=$(install_status_state "/home/$USER_NAME/.cli_tools_installed")
if [ "$install_state" = "partial" ]; then
  entrypoint_log "WARN" "Previous installation was partial - running install_cli_tools.sh --repair"
  if ! su_run "/usr/local/bin/install_cli_tools.sh --repair" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
      entrypoint_log "WARN" "Repair completed with warnings - check install.log for details"
  fi
else
  entrypoint_log "INFO" "Running CLI tools installation..."
  if ! su_run "/usr/local/bin/install_cli_tools.sh" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
      entrypoint_log "WARN" "Installation completed with warnings - check install.log for details"
  fi
fi
if [ "$(install_status_state "/home/$USER_NAME/.cli_tools_installed")" = "partial" ]; then
  entrypoint_log "WARN" "CLI tools installation is PARTIAL - failed tools: $(install_status_get "/home/$USER_NAME/.cli_tools_installed" "FAILED_TOOLS")"
fi

# Setup and start the scheduled updater. Failures remain non-fatal because
# interactive updates are still available, but the helper logs an actionable
# warning and behavioral tests cover registration and daemon liveness.
setup_auto_update_cron "$USER_NAME" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" || true
ensure_cron_daemon_running 2>&1 | tee -a "${LOG_FILE:-/dev/null}" || true

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

# Readiness is written last and atomically. The Compose healthcheck uses this
# marker plus the structured install status instead of merely checking that the
# keepalive process exists.
READY_FILE="/run/ai-docker-ready"
READY_TMP="${READY_FILE}.tmp.$$"
install_state=$(install_status_state "/home/$USER_NAME/.cli_tools_installed")
case "$install_state" in
  ok|legacy) ;;
  *)
    entrypoint_log "ERROR" "Entrypoint initialization is not ready (install status: $install_state)"
    rm -f "$READY_TMP" "$READY_FILE"
    exit 1
    ;;
esac
printf 'ENTRYPOINT=ok\nINSTALL_STATUS=%s\n' "$install_state" > "$READY_TMP"
mv "$READY_TMP" "$READY_FILE"
entrypoint_log "INFO" "Entrypoint initialization complete (install status: $install_state)"

# Keep container running
exec sleep infinity
