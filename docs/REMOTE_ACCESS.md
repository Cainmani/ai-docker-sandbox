# Remote Access Guide - Mobile Phone Access to Claude Code

This guide explains how to access your AI Docker CLI environment from mobile devices (Android/iPhone) using SSH, Mosh, and tmux.

## Table of Contents
1. [Overview](#overview)
2. [Why Mosh?](#why-mosh)
3. [Prerequisites](#prerequisites)
4. [Enabling Mobile Access](#enabling-mobile-access)
5. [Setting Up SSH Keys](#setting-up-ssh-keys)
6. [Connecting from Mobile](#connecting-from-mobile)
7. [Using tmux](#using-tmux)
8. [Security Best Practices](#security-best-practices)
9. [Recommended Apps](#recommended-apps)
10. [Troubleshooting](#troubleshooting)

---

## Overview

Mobile access allows you to use Claude Code from your phone or tablet, even when switching between WiFi and cellular networks. The setup uses:

- **SSH** - Secure authentication (port 2222)
- **Mosh** - Mobile shell that survives network changes (UDP ports 60001-60005)
- **tmux** - Terminal multiplexer for session persistence (Mosh has no scrollback)

> **Important**: This is an opt-in feature. It is disabled by default for security.

---

## Why Mosh?

Mosh (Mobile Shell) provides significant advantages over SSH for mobile connections:

| Feature | SSH | Mosh |
|---------|-----|------|
| Survives WiFi → cellular switch | No | Yes |
| Survives laptop sleep | No | Yes |
| Handles packet loss | Poor | Excellent |
| Instant keystroke feedback | No | Yes (predictive echo) |
| UDP-based | No (TCP) | Yes |

On a 29% packet loss link, Mosh reduces response time from 16.8s to 0.33s (50x improvement).

Mosh uses SSH for initial authentication, then switches to an encrypted UDP connection that can roam between networks.

---

## Prerequisites

### Required
- Docker container running (ai-cli)
- VPN access to your Docker host (if not on local network)

### Recommended VPN Options
Any VPN that provides access to your Docker host will work. Popular options include:

- **Tailscale** - Easy setup, free tier available, works on all platforms
- **WireGuard** - Fast, lightweight, open-source
- **ZeroTier** - Similar to Tailscale, self-hostable
- **OpenVPN** - Traditional option, widely supported

> **Why VPN?** Without a VPN, you'd need to expose SSH/Mosh ports directly to the internet, which is not recommended. A VPN provides secure, encrypted access to your home/office network.

### Mobile Terminal App
You need a terminal app that supports Mosh:
- **iOS**: Blink Shell (best), Termius
- **Android**: Termius, Termux + mosh package

---

## Enabling Mobile Access

### Step 1: Configure Environment Variables

Add these lines to your `.env` file (in `%LOCALAPPDATA%\AI-Docker-CLI\`):

```bash
# Enable mobile access
ENABLE_MOBILE_ACCESS=1

# Optional: customize ports (defaults shown)
SSH_PORT=2222
MOSH_PORT_START=60001
MOSH_PORT_END=60005
```

### Step 2: Rebuild the Container

After modifying the `.env` file, you need to restart the container:

1. Open AI_Docker_Manager.exe
2. Click "First Time Setup"
3. Select "Force Rebuild" if offered

Or manually:
```bash
docker-compose down
docker-compose up -d
```

### Step 3: Verify Services Are Running

Connect to the container and check:
```bash
docker exec -it ai-cli bash

# Check SSH is running
ps aux | grep sshd

# Check SSH port
netstat -tlnp | grep 2222
```

---

## Setting Up SSH Keys

SSH keys are required - password authentication is disabled for security.

### Using the `add-ssh-key` Command (Recommended)

The container includes a simple `add-ssh-key` command that makes managing SSH keys easy:

```bash
# Add a key (paste the full public key):
add-ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... my-phone"

# List all authorized keys:
add-ssh-key --list

# Remove a key by number:
add-ssh-key --remove 1

# Show help:
add-ssh-key --help
```

### Step-by-Step: Adding Your Phone's SSH Key

#### 1. Generate a Key on Your Phone

**Termius (iOS/Android) - Recommended for Beginners:**
1. Open Termius app
2. Go to **Keychain** (bottom menu)
3. Tap the **+** button
4. Choose **Generate New Key**
5. Select **ED25519** (most secure)
6. Give it a name like "my-iphone"
7. Tap **Create**
8. Tap on the key, then tap **Export Public Key**
9. Copy the key text

**Blink Shell (iOS):**
```bash
ssh-keygen -t ed25519 -C "my-iphone"
cat ~/.ssh/id_ed25519.pub
```

**Termux (Android):**
```bash
ssh-keygen -t ed25519 -C "my-android"
cat ~/.ssh/id_ed25519.pub
```

#### 2. Add the Key to the Container

From your PC, open a terminal in the container:
```bash
docker exec -it ai-cli bash
```

Then run:
```bash
add-ssh-key "paste-your-public-key-here"
```

You should see:
```
SUCCESS: SSH key added!

  Type:    ssh-ed25519
  Comment: my-iphone

You can now connect from your device using:
  mosh --ssh="ssh -p 2222" username@<your-host-ip>
```

#### 3. Verify Your Key Was Added

```bash
add-ssh-key --list
```

Output:
```
Authorized SSH Keys:

  [1] ssh-ed25519 AAAAC3Nza...xxxxx my-iphone

Total: 1 key(s)
```

### Manual Method (Alternative)

If you prefer to edit the file directly:

1. Copy your public key (the `.pub` file content)
2. Connect to the container from your PC:
   ```bash
   docker exec -it ai-cli bash
   ```
3. Add the key to authorized_keys:
   ```bash
   echo "YOUR_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
   ```

Or directly from outside the container:
```bash
docker exec ai-cli bash -c 'echo "YOUR_PUBLIC_KEY_HERE" >> /home/YOUR_USERNAME/.ssh/authorized_keys'
```

### Verify Key Was Added
```bash
add-ssh-key --list
# or manually:
cat ~/.ssh/authorized_keys
```

---

## Connecting from Mobile

### Step 1: Ensure VPN is Connected

Connect to your VPN (Tailscale, WireGuard, etc.) to access your Docker host.

### Step 2: Get Your Docker Host IP

Find the IP address of your Docker host:
- **Tailscale**: Check the Tailscale app for your machine's IP (e.g., `100.x.x.x`)
- **Local network**: Your machine's local IP (e.g., `192.168.1.x`)

### Step 3: Connect via Mosh

```bash
mosh --ssh="ssh -p 2222" username@docker-host-ip
```

Replace:
- `username` with your container username
- `docker-host-ip` with your Docker host's IP address

#### Example
```bash
mosh --ssh="ssh -p 2222" john@100.64.0.1
```

### Step 4: Start a tmux Session

Once connected, start tmux (required because Mosh has no scrollback):
```bash
# Create a new session named 'mobile'
tmux new -s mobile

# Or attach to existing session
tmux attach -t mobile
```

### Step 5: Use Claude Code
```bash
claude
```

---

## Using tmux

tmux is essential because Mosh doesn't support scrollback - you need tmux to scroll through Claude's output.

### Quick Reference

| Action | Keys |
|--------|------|
| Prefix key | `Ctrl+A` (not Ctrl+B) |
| Detach from session | `Ctrl+A` then `d` |
| New window | `Ctrl+A` then `c` |
| Next window | `Ctrl+A` then `n` |
| Previous window | `Ctrl+A` then `p` |
| Split horizontally | `Ctrl+A` then `-` |
| Split vertically | `Ctrl+A` then `|` |
| Navigate panes | `Ctrl+A` then arrow keys |
| Enter scroll mode | `Ctrl+A` then `[` |
| Exit scroll mode | `q` |
| Reload config | `Ctrl+A` then `r` |

### Session Management

```bash
# List sessions
tmux ls

# Create named session
tmux new -s work

# Attach to session
tmux attach -t work

# Kill session
tmux kill-session -t work
```

### Scrolling Through Output

1. Press `Ctrl+A` then `[` to enter copy mode
2. Use arrow keys or Page Up/Down to scroll
3. Press `q` to exit copy mode

### Why tmux is Required

Mosh uses a unique approach: it maintains a synchronized screen state between client and server. This means:
- **Pro**: Instant response even on high-latency connections
- **Con**: No scrollback buffer - what's off-screen is gone

tmux provides the scrollback buffer that Mosh lacks, making it essential for reviewing Claude's output.

---

## Security Best Practices

### 1. Always Use a VPN
Never expose SSH/Mosh ports directly to the internet. Use a VPN like Tailscale, WireGuard, or ZeroTier.

### 2. SSH Keys Only
Password authentication is disabled by default. Always use SSH keys.

### 3. Non-Standard Ports
The default SSH port is 2222 (not 22), which reduces exposure to automated scanning.

### 4. Limit User Access
The SSH configuration only allows your container user to connect - root login is disabled.

### 5. Monitor Access Logs
```bash
# View SSH logs
docker exec ai-cli cat /var/log/auth.log | grep sshd
```

### 6. Rotate Keys Periodically
If you suspect a key is compromised, remove it and generate a new one:
```bash
# Remove all authorized keys
docker exec ai-cli truncate -s 0 /home/username/.ssh/authorized_keys

# Add your new key
docker exec ai-cli bash -c 'echo "NEW_KEY" >> /home/username/.ssh/authorized_keys'
```

---

## Recommended Apps

### iOS

| App | Price | Notes |
|-----|-------|-------|
| **Blink Shell** | $19.99 | Best Mosh support, native Tailscale integration, keyboard customization |
| **Termius** | Free/Pro | Cross-platform sync, good Mosh support |

### Android

| App | Price | Notes |
|-----|-------|-------|
| **Termius** | Free/Pro | Cross-platform, Mosh support, sync across devices |
| **Termux + mosh** | Free | Power users, full Linux environment |

### Installing Mosh in Termux (Android)
```bash
pkg install mosh
```

---

## Troubleshooting

### "Connection refused" on port 2222

**Cause**: SSH daemon not running or wrong port.

**Solution**:
```bash
# Check if SSH is running
docker exec ai-cli ps aux | grep sshd

# Check which port SSH is listening on
docker exec ai-cli netstat -tlnp | grep ssh

# Restart SSH
docker exec ai-cli /usr/sbin/sshd
```

### "Permission denied (publickey)"

**Cause**: SSH key not in authorized_keys or wrong permissions.

**Solution**:
```bash
# Check authorized_keys
docker exec ai-cli cat /home/USERNAME/.ssh/authorized_keys

# Fix permissions
docker exec ai-cli chmod 700 /home/USERNAME/.ssh
docker exec ai-cli chmod 600 /home/USERNAME/.ssh/authorized_keys
```

### Mosh timeout / UDP blocked

**Cause**: Firewall blocking UDP ports 60001-60005.

**Solution**:
1. Check your router/firewall allows UDP 60001-60005
2. Check Docker host firewall:
   ```bash
   # Linux
   sudo ufw allow 60001:60005/udp

   # Windows Defender Firewall - run as admin
   netsh advfirewall firewall add rule name="Mosh" dir=in action=allow protocol=UDP localport=60001-60005
   ```

### "mosh-server not found" in container

**Cause**: Mosh package not installed.

**Solution**: Rebuild the container with mobile access enabled:
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### tmux: "sessions should be nested with care"

**Cause**: Trying to start tmux inside tmux.

**Solution**: You're already in tmux! Check with `echo $TMUX` - if it shows a path, you're in tmux.

### Connection drops when switching networks

**Cause**: Not using Mosh (using plain SSH instead).

**Solution**: Make sure you're connecting with Mosh:
```bash
# Wrong (plain SSH - will drop)
ssh -p 2222 user@host

# Right (Mosh - survives network changes)
mosh --ssh="ssh -p 2222" user@host
```

### Can't scroll in Mosh

**Cause**: Mosh has no scrollback - this is by design.

**Solution**: Use tmux for scrollback:
1. Press `Ctrl+A` then `[` to enter copy mode
2. Scroll with arrow keys or Page Up/Down
3. Press `q` to exit

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_MOBILE_ACCESS` | `0` | Set to `1` to enable SSH/Mosh/tmux |
| `SSH_PORT` | `2222` | SSH server port (TCP) |
| `MOSH_PORT_START` | `60001` | First Mosh port (UDP) |
| `MOSH_PORT_END` | `60005` | Last Mosh port (UDP, allows 5 concurrent connections) |

---

## Quick Setup Checklist

- [ ] Add `ENABLE_MOBILE_ACCESS=1` to `.env` file
- [ ] Rebuild/restart container
- [ ] Generate SSH key on mobile device
- [ ] Add public key to container's `~/.ssh/authorized_keys`
- [ ] Connect VPN (Tailscale, WireGuard, etc.)
- [ ] Install Mosh-capable terminal app
- [ ] Connect: `mosh --ssh="ssh -p 2222" user@host`
- [ ] Start tmux: `tmux new -s mobile`
- [ ] Run `claude` and enjoy mobile coding!

---

## Additional Resources

- [Mosh Official Documentation](https://mosh.org/)
- [tmux Cheat Sheet](https://tmuxcheatsheet.com/)
- [Tailscale Quickstart](https://tailscale.com/kb/1017/install/)
- [Blink Shell Documentation](https://docs.blink.sh/)

---

*For general troubleshooting, see [USER_MANUAL.md](USER_MANUAL.md). For logging information, see [LOGGING.md](LOGGING.md).*
