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
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER_NAME
  chmod 0440 /etc/sudoers.d/$USER_NAME
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

# Keep container running
exec tail -f /dev/null
