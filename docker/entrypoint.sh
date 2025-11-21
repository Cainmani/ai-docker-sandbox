#!/usr/bin/env bash
set -euo pipefail

# Required: USER_NAME and USER_PASSWORD come from environment (.env or compose)
: "${USER_NAME:?Set USER_NAME env}"
: "${USER_PASSWORD:?Set USER_PASSWORD env}"

# Create user if missing
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USER_NAME"
  echo "$USER_NAME:$USER_PASSWORD" | chpasswd
  usermod -aG sudo "$USER_NAME"

  # Allow passwordless sudo for this user
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER_NAME"
  chmod 0440 "/etc/sudoers.d/$USER_NAME"
fi

# Give user ownership of workspace
chown -R "$USER_NAME:$USER_NAME" /workspace 2>/dev/null || true

# CRITICAL: Ensure user's home directory has correct ownership
# This includes the .claude directory which is a Docker volume
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME" 2>/dev/null || true

# Ensure .claude directory exists with correct permissions
mkdir -p "/home/$USER_NAME/.claude"
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.claude"
chmod 755 "/home/$USER_NAME/.claude"

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

# Add npm global and local bin to PATH
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

# CLI tools aliases
alias update-tools='/usr/local/bin/auto_update.sh'
alias check-updates='/usr/local/bin/auto_update.sh --check'
alias configure-tools='/usr/local/bin/configure_tools.sh'
alias config-status='/usr/local/bin/configure_tools.sh --status'

# Show available CLI tools on login
if [ -f /home/$USER/.cli_tools_installed ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║          AI CLI Tools Environment Ready!                    ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║ Available AI Tools:                                         ║"
  echo "║   • claude       - Claude Code CLI                          ║"
  echo "║   • gh           - GitHub CLI                               ║"
  echo "║   • gemini       - Google Gemini CLI                        ║"
  echo "║   • codex        - OpenAI Codex CLI                         ║"
  echo "║   • python3      - OpenAI Python SDK (import openai)        ║"
  echo "║                                                              ║"
  echo "║ Management Commands:                                        ║"
  echo "║   • configure-tools  - Set up API keys and authentication   ║"
  echo "║   • config-status    - Check configuration status           ║"
  echo "║   • update-tools     - Update all CLI tools                 ║"
  echo "║   • check-updates    - Check for available updates          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "First time? Run 'configure-tools' to set up your API keys!"
  echo ""
fi
EOF
  chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.bashrc"
else
  # .bashrc already exists, ensure npm PATH is added
  if ! grep -q "\.npm-global/bin" "/home/$USER_NAME/.bashrc"; then
    echo "" >> "/home/$USER_NAME/.bashrc"
    echo "# Add npm global and local bin to PATH" >> "/home/$USER_NAME/.bashrc"
    echo 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> "/home/$USER_NAME/.bashrc"
    chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.bashrc"
  fi
fi

# Create .profile to set PATH for login shells (used by 'su -')
if [ ! -f "/home/$USER_NAME/.profile" ]; then
  cat > "/home/$USER_NAME/.profile" << 'EOF'
# ~/.profile: executed by the command interpreter for login shells.

# Add npm global and local bin to PATH
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
  # .profile already exists, ensure npm PATH is added
  if ! grep -q "\.npm-global/bin" "/home/$USER_NAME/.profile"; then
    echo "" >> "/home/$USER_NAME/.profile"
    echo "# Add npm global and local bin to PATH" >> "/home/$USER_NAME/.profile"
    echo 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> "/home/$USER_NAME/.profile"
    chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.profile"
  fi
fi

# Install CLI tools on first run (runs as the user)
echo "Checking CLI tools installation..."
su - "$USER_NAME" -c "/usr/local/bin/install_cli_tools.sh" || true

# Setup auto-update cron job (weekly on Sunday at 2 AM)
if ! crontab -u "$USER_NAME" -l 2>/dev/null | grep -q "auto_update.sh"; then
  echo "Setting up auto-update schedule..."
  (crontab -u "$USER_NAME" -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/auto_update.sh >/dev/null 2>&1") | crontab -u "$USER_NAME" - || true
fi

# Keep container running
exec tail -f /dev/null
