#!/bin/bash
set -euo pipefail
# Only the standalone disposable pilot opts into this SSH server.
[ "${ENABLE_DESKTOP_PILOT:-0}" = 1 ] || exit 0
[ "${USER_NAME:-}" = pilot ] || { echo 'Desktop pilot requires the disposable pilot user.' >&2; exit 2; }
key=/run/pilot-key.pub
[ -r "$key" ] && ssh-keygen -lf "$key" >/dev/null || { echo 'Provide a valid pilot SSH public key.' >&2; exit 2; }
install -d -m 700 -o pilot -g pilot /home/pilot/.ssh
install -m 600 -o pilot -g pilot "$key" /home/pilot/.ssh/authorized_keys
mkdir -p /run/sshd
ssh-keygen -A
cat > /etc/ssh/sshd_config.pilot <<'CONFIG'
Port 2222
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers pilot
AuthorizedKeysFile .ssh/authorized_keys
AllowAgentForwarding no
# Desktop may tunnel to its remote server. Only local forwarding to the
# container loopback is permitted; no reverse tunnels or arbitrary destinations.
AllowTcpForwarding local
PermitOpen localhost:* 127.0.0.1:* [::1]:*
GatewayPorts no
X11Forwarding no
PermitTunnel no
UsePAM yes
Subsystem sftp /usr/lib/openssh/sftp-server
CONFIG
/usr/sbin/sshd -t -f /etc/ssh/sshd_config.pilot
/usr/sbin/sshd -f /etc/ssh/sshd_config.pilot
