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
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}$1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "\n${GREEN}▶ STEP $1:${NC} ${BOLD}$2${NC}\n"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_cmd() {
    echo -e "    ${CYAN}$1${NC}"
}

# Check Tailscale status
check_tailscale() {
    if ! command -v tailscale &> /dev/null; then
        return 1
    fi
    if tailscale status &> /dev/null; then
        return 0
    fi
    return 1
}

# Get Tailscale info
get_tailscale_info() {
    local ts_ip=$(tailscale ip -4 2>/dev/null || echo "")
    local ts_hostname=$(tailscale status --self --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | cut -d'"' -f4 | sed 's/\.$//' 2>/dev/null || echo "")
    echo "$ts_ip|$ts_hostname"
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

    # Step 1: Check/Setup Tailscale on container
    print_step "1" "Container Tailscale Status"

    if check_tailscale; then
        local info=$(get_tailscale_info)
        local ts_ip=$(echo "$info" | cut -d'|' -f1)
        local ts_hostname=$(echo "$info" | cut -d'|' -f2)

        print_success "Tailscale is connected!"
        echo ""
        echo -e "  IP Address: ${GREEN}$ts_ip${NC}"
        if [ -n "$ts_hostname" ]; then
            echo -e "  Hostname:   ${GREEN}$ts_hostname${NC}"
        fi
    else
        print_warning "Tailscale is not connected in this container."
        echo ""
        print_info "Run this command to connect:"
        print_cmd "sudo tailscale up"
        echo ""
        print_info "You'll get a URL to authenticate - open it in your browser."
        echo ""
        read -p "  Press Enter after you've connected Tailscale..."

        if check_tailscale; then
            print_success "Tailscale connected!"
        else
            print_error "Tailscale still not connected. Please run 'sudo tailscale up' first."
            exit 1
        fi
    fi

    # Step 2: Tailscale on phone
    print_step "2" "Install Tailscale on Your Phone"

    echo -e "  Download Tailscale on your phone:"
    echo ""
    echo -e "  ${BOLD}iPhone:${NC}  Search 'Tailscale' in App Store"
    echo -e "  ${BOLD}Android:${NC} Search 'Tailscale' in Play Store"
    echo ""
    print_info "Sign in with the SAME account you used for this container."
    print_info "Your phone will join the same private network."
    echo ""

    read -p "  Press Enter when Tailscale is installed on your phone..."

    # Step 3: Add SSH key
    print_step "3" "Add Your Phone's SSH Key"

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
        print_warning "No key entered - skipping. You can add it later with 'add-ssh-key'"
    else
        echo ""
        if /usr/local/bin/add_ssh_key.sh "$ssh_key"; then
            print_success "SSH key added!"
        else
            print_error "Failed to add key. You can try again with 'add-ssh-key \"your-key\"'"
        fi
    fi

    # Step 4: Show connection info
    print_step "4" "Connect from Your Phone"

    local info=$(get_tailscale_info)
    local ts_ip=$(echo "$info" | cut -d'|' -f1)
    local ts_hostname=$(echo "$info" | cut -d'|' -f2)
    local username=$(whoami)

    echo -e "  ${BOLD}Your connection details:${NC}"
    echo ""
    if [ -n "$ts_hostname" ]; then
        echo -e "  Hostname: ${GREEN}$ts_hostname${NC}"
    fi
    echo -e "  Tailscale IP: ${GREEN}$ts_ip${NC}"
    echo -e "  Username: ${GREEN}$username${NC}"
    echo -e "  Port: ${GREEN}2222${NC}"
    echo ""

    echo -e "  ${BOLD}Connect using (from your phone):${NC}"
    echo ""
    if [ -n "$ts_hostname" ]; then
        print_cmd "ssh -p 2222 $username@$ts_hostname"
        echo ""
        echo -e "  Or with Mosh (better for mobile):"
        print_cmd "mosh --ssh=\"ssh -p 2222\" $username@$ts_hostname"
    else
        print_cmd "ssh -p 2222 $username@$ts_ip"
        echo ""
        echo -e "  Or with Mosh (better for mobile):"
        print_cmd "mosh --ssh=\"ssh -p 2222\" $username@$ts_ip"
    fi
    echo ""

    echo -e "  ${BOLD}In Termius app:${NC}"
    echo ""
    echo -e "  1. Create new Host"
    if [ -n "$ts_hostname" ]; then
        echo -e "  2. Address: ${CYAN}$ts_hostname${NC}"
    else
        echo -e "  2. Address: ${CYAN}$ts_ip${NC}"
    fi
    echo -e "  3. Port: ${CYAN}2222${NC}"
    echo -e "  4. Username: ${CYAN}$username${NC}"
    echo -e "  5. Authentication: Use your SSH key"
    echo ""

    print_header "Setup Complete!"

    echo -e "  You can now connect from your phone using Tailscale."
    echo -e "  Your connection is encrypted end-to-end and never"
    echo -e "  exposed to the public internet."
    echo ""
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo -e "    ${CYAN}add-ssh-key \"key\"${NC}  - Add another SSH key"
    echo -e "    ${CYAN}add-ssh-key --list${NC} - List all keys"
    echo -e "    ${CYAN}tailscale status${NC}   - Check Tailscale connection"
    echo ""
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
