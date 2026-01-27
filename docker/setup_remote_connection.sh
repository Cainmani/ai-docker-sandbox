#!/usr/bin/env bash
# setup-remote-connection - Tailscale-based remote access wizard
# Secure remote access without exposing ports to the internet

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "  ${BOLD}$1${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
}

print_step() {
    echo -e "\n${GREEN}>> STEP $1:${NC} ${BOLD}$2${NC}\n"
}

print_info() {
    echo -e "  ${BLUE}[i]${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "  ${RED}[X]${NC} $1"
}

print_cmd() {
    echo -e "    ${CYAN}$1${NC}"
}

# Main wizard
main() {
    clear
    print_header "Remote Connection Setup"

    echo -e "  This wizard helps you connect to your AI workspace from your"
    echo -e "  phone or tablet using ${BOLD}Tailscale${NC} - a secure private network."
    echo ""
    echo -e "  ${BOLD}Why Tailscale?${NC}"
    print_info "No ports exposed to the internet (secure)"
    print_info "Works from anywhere - home, coffee shop, mobile data"
    print_info "No IP addresses to remember - use simple hostnames"
    print_info "Free for personal use"
    echo ""

    read -p "  Press Enter to continue..."

    # Step 1: Tailscale on Windows
    print_step "1" "Install Tailscale on Windows"

    echo -e "  ${BOLD}Do you have Tailscale installed on your Windows PC?${NC}"
    echo ""
    echo -e "  If not, download it from:"
    echo ""
    echo -e "    ${CYAN}https://tailscale.com/download${NC}"
    echo ""
    print_info "Install it, sign in, and make sure it's connected."
    print_info "You'll see the Tailscale icon in your system tray."
    echo ""

    read -p "  Press Enter when Tailscale is running on Windows..."

    # Step 2: Tailscale on phone
    print_step "2" "Install Tailscale on Your Phone"

    echo -e "  Download Tailscale on your phone:"
    echo ""
    echo -e "  ${BOLD}iPhone:${NC}  Search 'Tailscale' in App Store"
    echo -e "  ${BOLD}Android:${NC} Search 'Tailscale' in Play Store"
    echo ""
    print_info "Sign in with the SAME account you used on Windows."
    print_info "Both devices will join your private Tailscale network."
    echo ""

    read -p "  Press Enter when Tailscale is installed on your phone..."

    # Step 3: Get Windows Tailscale IP
    print_step "3" "Get Your Windows Tailscale Address"

    echo -e "  On your Windows PC, find your Tailscale address:"
    echo ""
    echo -e "  ${BOLD}Option A - From Tailscale app:${NC}"
    print_info "Click Tailscale icon in system tray"
    print_info "Your address looks like: 100.x.x.x or pc-name.tailnet-name.ts.net"
    echo ""
    echo -e "  ${BOLD}Option B - From PowerShell:${NC}"
    print_cmd "tailscale ip"
    echo ""

    read -p "  Enter your Windows Tailscale IP or hostname: " windows_ts_address

    if [ -z "$windows_ts_address" ]; then
        print_warning "No address entered - you can add it later when connecting."
        windows_ts_address="<your-windows-tailscale-address>"
    fi

    # Step 4: Add SSH key
    print_step "4" "Add Your Phone's SSH Key"

    echo -e "  ${BOLD}On your phone's terminal app (Termius, Blink Shell, etc.):${NC}"
    echo ""
    echo -e "  a) Generate an SSH key (if you haven't already):"
    print_cmd "ssh-keygen -t ed25519 -C \"my-phone\""
    echo ""
    echo -e "  b) Display your public key:"
    print_cmd "cat ~/.ssh/id_ed25519.pub"
    echo ""
    echo -e "  c) Copy the entire line (starts with 'ssh-ed25519')"
    echo ""

    read -p "  Paste your SSH public key here: " ssh_key

    if [ -z "$ssh_key" ]; then
        print_warning "No key entered - you can add it later with: add-ssh-key \"your-key\""
    else
        echo ""
        if /usr/local/bin/add-ssh-key "$ssh_key" 2>/dev/null || echo "$ssh_key" >> ~/.ssh/authorized_keys 2>/dev/null; then
            print_success "SSH key added!"
        else
            print_warning "Could not add key automatically. Try: add-ssh-key \"your-key\""
        fi
    fi

    # Step 5: Show connection info
    print_step "5" "Connect from Your Phone!"

    local username=$(whoami)

    print_header "Your Connection Details"

    echo -e "  ${BOLD}Windows Tailscale Address:${NC} ${GREEN}$windows_ts_address${NC}"
    echo -e "  ${BOLD}Username:${NC} ${GREEN}$username${NC}"
    echo -e "  ${BOLD}Port:${NC} ${GREEN}2222${NC}"
    echo ""

    echo -e "  ${BOLD}Connect from your phone terminal:${NC}"
    echo ""
    print_cmd "ssh -p 2222 $username@$windows_ts_address"
    echo ""
    echo -e "  ${BOLD}Or with Mosh (better for mobile):${NC}"
    echo ""
    print_cmd "mosh --ssh=\"ssh -p 2222\" $username@$windows_ts_address"
    echo ""

    echo -e "  ${BOLD}In Termius app:${NC}"
    echo ""
    echo "  1. Tap + to create new Host"
    echo -e "  2. Hostname: ${CYAN}$windows_ts_address${NC}"
    echo -e "  3. Port: ${CYAN}2222${NC}"
    echo -e "  4. Username: ${CYAN}$username${NC}"
    echo "  5. Use SSH Key authentication"
    echo ""

    print_header "Setup Complete!"

    echo -e "  Your connection is secured by Tailscale's encryption."
    echo -e "  No ports are exposed to the public internet."
    echo ""
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo -e "    ${CYAN}add-ssh-key \"key\"${NC}   - Add another SSH key"
    echo -e "    ${CYAN}add-ssh-key --list${NC}  - List all keys"
    echo ""
}

# Run
main "$@"
