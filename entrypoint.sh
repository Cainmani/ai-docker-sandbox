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


# Keep container running
exec tail -f /dev/null
