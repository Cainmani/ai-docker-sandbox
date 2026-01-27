#!/usr/bin/env bash
# =============================================================================
# add-ssh-key: Simple SSH key management for mobile access
# =============================================================================
# This script makes it easy to add SSH keys for mobile phone access.
# Instead of manually editing ~/.ssh/authorized_keys, users can just run:
#   add-ssh-key "ssh-ed25519 AAAAC3... my-phone"
#
# Usage:
#   add-ssh-key "ssh-ed25519 AAAAC3... comment"  # Add a key
#   add-ssh-key --list                           # List all keys
#   add-ssh-key --remove 1                       # Remove key #1
#   add-ssh-key --help                           # Show help
# =============================================================================

set -euo pipefail

# Colors for user-friendly output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# SSH authorized_keys file
AUTH_KEYS="$HOME/.ssh/authorized_keys"

# Ensure .ssh directory exists with correct permissions
ensure_ssh_dir() {
    if [ ! -d "$HOME/.ssh" ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi
    if [ ! -f "$AUTH_KEYS" ]; then
        touch "$AUTH_KEYS"
        chmod 600 "$AUTH_KEYS"
    fi
}

# Show help message
show_help() {
    echo -e "${BOLD}${CYAN}add-ssh-key${NC} - Simple SSH key management for mobile access"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo -e "  ${GREEN}add-ssh-key \"<public-key>\"${NC}    Add a new SSH public key"
    echo -e "  ${GREEN}add-ssh-key --list${NC}            List all authorized keys"
    echo -e "  ${GREEN}add-ssh-key --remove <number>${NC} Remove key by number"
    echo -e "  ${GREEN}add-ssh-key --help${NC}            Show this help message"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo ""
    echo -e "  ${YELLOW}# Add an SSH key (copy from your phone's terminal app):${NC}"
    echo -e "  add-ssh-key \"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... my-iphone\""
    echo ""
    echo -e "  ${YELLOW}# Add an RSA key:${NC}"
    echo -e "  add-ssh-key \"ssh-rsa AAAAB3NzaC1yc2E... my-android\""
    echo ""
    echo -e "  ${YELLOW}# List all keys (with numbers for removal):${NC}"
    echo -e "  add-ssh-key --list"
    echo ""
    echo -e "  ${YELLOW}# Remove key number 2:${NC}"
    echo -e "  add-ssh-key --remove 2"
    echo ""
    echo -e "${BOLD}MOBILE SETUP WORKFLOW:${NC}"
    echo ""
    echo -e "  1. On your phone (Termius, Blink Shell, etc.):"
    echo -e "     ${CYAN}ssh-keygen -t ed25519 -C \"my-phone\"${NC}"
    echo ""
    echo -e "  2. Copy your public key:"
    echo -e "     ${CYAN}cat ~/.ssh/id_ed25519.pub${NC}"
    echo ""
    echo -e "  3. In this container, run:"
    echo -e "     ${CYAN}add-ssh-key \"paste-your-public-key-here\"${NC}"
    echo ""
    echo -e "  4. Connect from your phone:"
    echo -e "     ${CYAN}mosh --ssh=\"ssh -p 2222\" $(whoami)@<your-host-ip>${NC}"
    echo ""
    echo -e "${BOLD}SUPPORTED KEY TYPES:${NC}"
    echo -e "  - ssh-ed25519 (recommended, most secure)"
    echo -e "  - ssh-rsa"
    echo -e "  - ecdsa-sha2-nistp256"
    echo -e "  - ecdsa-sha2-nistp384"
    echo -e "  - ecdsa-sha2-nistp521"
    echo ""
}

# Validate SSH key format
validate_key() {
    local key="$1"

    # Check for supported key types
    if [[ "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\ [A-Za-z0-9+/=]+ ]]; then
        return 0
    fi

    return 1
}

# Add a new SSH key
add_key() {
    local key="$1"

    # Validate key format
    if ! validate_key "$key"; then
        echo -e "${RED}ERROR:${NC} Invalid SSH key format."
        echo ""
        echo "A valid SSH public key looks like:"
        echo -e "  ${CYAN}ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxx... comment${NC}"
        echo ""
        echo "Supported key types: ssh-ed25519, ssh-rsa, ecdsa-sha2-*"
        echo ""
        echo "Make sure you're copying the PUBLIC key (.pub file), not the private key."
        return 1
    fi

    ensure_ssh_dir

    # Check for duplicates
    if grep -qF "$key" "$AUTH_KEYS" 2>/dev/null; then
        echo -e "${YELLOW}WARNING:${NC} This key is already authorized."
        return 0
    fi

    # Extract key type and comment for display
    local key_type
    local key_comment
    key_type=$(echo "$key" | awk '{print $1}')
    key_comment=$(echo "$key" | awk '{print $3}')
    if [ -z "$key_comment" ]; then
        key_comment="(no comment)"
    fi

    # Add the key
    echo "$key" >> "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"

    echo -e "${GREEN}SUCCESS:${NC} SSH key added!"
    echo ""
    echo -e "  Type:    ${CYAN}$key_type${NC}"
    echo -e "  Comment: ${CYAN}$key_comment${NC}"
    echo ""
    echo -e "You can now connect from your device using:"
    echo -e "  ${CYAN}mosh --ssh=\"ssh -p 2222\" $(whoami)@<your-host-ip>${NC}"
    echo ""
}

# List all authorized keys
list_keys() {
    ensure_ssh_dir

    if [ ! -s "$AUTH_KEYS" ]; then
        echo -e "${YELLOW}No SSH keys are currently authorized.${NC}"
        echo ""
        echo "To add a key, run:"
        echo -e "  ${CYAN}add-ssh-key \"ssh-ed25519 AAAAC3... my-device\"${NC}"
        return 0
    fi

    echo -e "${BOLD}Authorized SSH Keys:${NC}"
    echo ""

    local count=0
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        count=$((count + 1))
        local key_type
        local key_data
        local key_comment
        key_type=$(echo "$line" | awk '{print $1}')
        key_data=$(echo "$line" | awk '{print $2}')
        key_comment=$(echo "$line" | awk '{print $3}')

        # Truncate key data for display
        if [ ${#key_data} -gt 20 ]; then
            key_data="${key_data:0:10}...${key_data: -10}"
        fi

        if [ -z "$key_comment" ]; then
            key_comment="(no comment)"
        fi

        echo -e "  ${BOLD}[$count]${NC} ${CYAN}$key_type${NC} $key_data ${YELLOW}$key_comment${NC}"
    done < "$AUTH_KEYS"

    echo ""
    echo -e "Total: ${BOLD}$count${NC} key(s)"
    echo ""
    echo "To remove a key, run:"
    echo -e "  ${CYAN}add-ssh-key --remove <number>${NC}"
}

# Remove a key by number
remove_key() {
    local key_num="$1"

    # Validate number
    if ! [[ "$key_num" =~ ^[0-9]+$ ]] || [ "$key_num" -lt 1 ]; then
        echo -e "${RED}ERROR:${NC} Please specify a valid key number."
        echo ""
        echo "Run 'add-ssh-key --list' to see key numbers."
        return 1
    fi

    ensure_ssh_dir

    if [ ! -s "$AUTH_KEYS" ]; then
        echo -e "${RED}ERROR:${NC} No keys to remove."
        return 1
    fi

    # Count actual keys (non-empty, non-comment lines)
    local total_keys
    total_keys=$(grep -cv '^\s*$\|^\s*#' "$AUTH_KEYS" 2>/dev/null || echo 0)

    if [ "$key_num" -gt "$total_keys" ]; then
        echo -e "${RED}ERROR:${NC} Key #$key_num does not exist."
        echo ""
        echo "There are only $total_keys key(s). Run 'add-ssh-key --list' to see them."
        return 1
    fi

    # Get the key to be removed for confirmation
    local key_to_remove
    local line_count=0
    local actual_line=0
    while IFS= read -r line; do
        actual_line=$((actual_line + 1))
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line_count=$((line_count + 1))
        if [ "$line_count" -eq "$key_num" ]; then
            key_to_remove="$line"
            break
        fi
    done < "$AUTH_KEYS"

    local key_comment
    key_comment=$(echo "$key_to_remove" | awk '{print $3}')
    if [ -z "$key_comment" ]; then
        key_comment="(no comment)"
    fi

    # Remove the key (create temp file, exclude the line, replace original)
    local temp_file
    temp_file=$(mktemp)
    local current=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && { echo "$line" >> "$temp_file"; continue; }
        current=$((current + 1))
        if [ "$current" -ne "$key_num" ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$AUTH_KEYS"

    mv "$temp_file" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"

    echo -e "${GREEN}SUCCESS:${NC} Key #$key_num removed."
    echo -e "  Comment: ${YELLOW}$key_comment${NC}"
    echo ""
}

# Main logic
main() {
    case "${1:-}" in
        --help|-h|"")
            show_help
            ;;
        --list|-l)
            list_keys
            ;;
        --remove|-r)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}ERROR:${NC} Please specify a key number to remove."
                echo ""
                echo "Usage: add-ssh-key --remove <number>"
                echo ""
                echo "Run 'add-ssh-key --list' to see key numbers."
                exit 1
            fi
            remove_key "$2"
            ;;
        -*)
            echo -e "${RED}ERROR:${NC} Unknown option: $1"
            echo ""
            echo "Run 'add-ssh-key --help' for usage information."
            exit 1
            ;;
        *)
            add_key "$1"
            ;;
    esac
}

main "$@"
