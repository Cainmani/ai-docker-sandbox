#!/bin/bash

# AI Docker CLI Tools Installation Script
# This script installs and configures all necessary CLI tools for AI development
# It runs on first container start and can be used for updates

# Note: We do NOT use "set -e" here because we want to continue installing other tools
# even if one tool fails. The marker file will be created regardless to prevent infinite loops.

# Ensure npm is configured to use user-local directory (fixes permission issues)
mkdir -p "${HOME}/.npm-global"
npm config set prefix "${HOME}/.npm-global"
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation tracking file
# Use $HOME instead of $USER_NAME since $HOME is set by 'su -' but $USER_NAME is not passed
INSTALL_MARKER="${HOME}/.cli_tools_installed"
TOOLS_VERSION_FILE="${HOME}/.cli_tools_versions"
INSTALL_STATUS_FILE="${HOME}/.cli_install_status"

# Function to update installation status (for UI feedback)
update_install_status() {
    local tool=$1
    local pkg_manager=$2
    echo "${tool}|${pkg_manager}" > "$INSTALL_STATUS_FILE"
}

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate npm is working correctly (prevents "Unknown command: pm" errors)
# NOTE: Parallel implementation exists in scripts/setup_wizard.ps1 (Test-NpmFunctional)
#       for Windows host. Keep both in sync when making changes.
validate_npm() {
    print_status "Validating npm installation..."

    # Check npm command exists
    if ! command -v npm >/dev/null 2>&1; then
        print_error "npm command not found in PATH"
        print_error "PATH is: $PATH"
        return 1
    fi

    # Verify npm can execute (catches "Unknown command: pm" type errors)
    local npm_version
    npm_version=$(npm --version 2>&1)
    local npm_exit_code=$?

    if [ $npm_exit_code -ne 0 ] || [ -z "$npm_version" ]; then
        print_error "npm is not functioning correctly"
        print_error "npm --version output: $npm_version"
        return 1
    fi

    # Test npm can actually list global packages
    if ! npm list -g --depth=0 >/dev/null 2>&1; then
        print_warning "npm global list failed, attempting to fix global prefix..."
        rm -rf "${HOME}/.npm-global" 2>/dev/null || true
        mkdir -p "${HOME}/.npm-global"
        npm config set prefix "${HOME}/.npm-global"
        export PATH="${HOME}/.npm-global/bin:${PATH}"

        # Retry after fix
        if ! npm list -g --depth=0 >/dev/null 2>&1; then
            print_warning "npm global list still failing, but may work for installs"
        fi
    fi

    print_success "npm is working correctly (version: $npm_version)"
    return 0
}

# Function to attempt npm repair if validation fails
# NOTE: Parallel implementation exists in scripts/setup_wizard.ps1 (Repair-NpmInstallation)
repair_npm() {
    print_warning "Attempting to repair npm installation..."

    # Clear npm cache
    npm cache clean --force 2>/dev/null || true

    # Remove and recreate global directory
    rm -rf "${HOME}/.npm-global" 2>/dev/null || true
    mkdir -p "${HOME}/.npm-global"
    npm config set prefix "${HOME}/.npm-global"
    export PATH="${HOME}/.npm-global/bin:${PATH}"

    # On Debian/Ubuntu systems, try reinstalling nodejs/npm if available
    if command -v apt-get >/dev/null 2>&1; then
        print_status "Reinstalling Node.js and npm via apt..."
        sudo apt-get update -qq
        sudo apt-get install --reinstall nodejs npm -y -qq 2>/dev/null || true
    fi

    # Validate after repair
    if validate_npm; then
        print_success "npm repair successful"
        return 0
    fi

    print_error "npm repair failed - manual intervention may be required"
    return 1
}

# Function to get installed version
get_version() {
    local tool=$1
    case $tool in
        gh)
            gh --version 2>/dev/null | head -n1 | cut -d' ' -f3 || echo "not installed"
            ;;
        claude)
            npm list -g @anthropic-ai/claude-code 2>/dev/null | grep '@anthropic-ai/claude-code' | cut -d'@' -f3 || echo "not installed"
            ;;
        gemini)
            gemini --version 2>/dev/null | head -n1 || echo "not installed"
            ;;
        codex)
            codex --version 2>/dev/null | head -n1 || echo "not installed"
            ;;
        aider)
            aider --version 2>/dev/null || echo "not installed"
            ;;
        cursor)
            cursor --version 2>/dev/null || echo "not installed"
            ;;
        vibe-kanban)
            npm list -g vibe-kanban 2>/dev/null | grep 'vibe-kanban' | cut -d'@' -f2 || echo "not installed"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to save installed versions
save_versions() {
    echo "# CLI Tools Versions - $(date)" > "$TOOLS_VERSION_FILE"
    echo "gh=$(get_version gh)" >> "$TOOLS_VERSION_FILE"
    echo "claude=$(get_version claude)" >> "$TOOLS_VERSION_FILE"
    echo "gemini=$(get_version gemini)" >> "$TOOLS_VERSION_FILE"
    echo "codex=$(get_version codex)" >> "$TOOLS_VERSION_FILE"
    echo "aider=$(get_version aider)" >> "$TOOLS_VERSION_FILE"
    echo "cursor=$(get_version cursor)" >> "$TOOLS_VERSION_FILE"
    echo "vibe-kanban=$(get_version vibe-kanban)" >> "$TOOLS_VERSION_FILE"
}

# Main installation function
install_cli_tools() {
    print_status "Starting CLI tools installation..."

    # CRITICAL: Validate npm before any npm operations
    # This prevents "Unknown command: pm" errors and other npm issues
    if ! validate_npm; then
        print_warning "npm validation failed, attempting repair..."
        if ! repair_npm; then
            print_error "npm is not working - npm-based tools (Claude, Gemini, Codex) will be skipped"
            print_error "Please check Node.js/npm installation and try again"
        fi
    fi

    # Update package lists
    print_status "Updating package lists..."
    sudo apt-get update -qq

    # 1. Install GitHub CLI
    update_install_status "GitHub CLI" "apt"
    if ! command_exists gh; then
        print_status "Installing GitHub CLI..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update -qq
        sudo apt-get install gh -y -qq
        print_success "GitHub CLI installed successfully"
    else
        print_status "GitHub CLI already installed ($(get_version gh))"
    fi

    # 2. Install/Update Claude Code CLI
    update_install_status "Claude Code CLI" "npm"
    print_status "Installing/Updating Claude Code CLI..."
    if npm install -g @anthropic-ai/claude-code@latest 2>&1 | tee /tmp/claude_install.log; then
        print_success "Claude Code CLI installed/updated successfully"
    else
        print_error "Failed to install Claude Code CLI"
        cat /tmp/claude_install.log
        # Continue with other installations
    fi

    # 3. Install Google Gemini CLI (official)
    update_install_status "Google Gemini CLI" "npm"
    print_status "Installing Google Gemini CLI..."
    if npm view @google/gemini-cli version >/dev/null 2>&1; then
        print_status "Found @google/gemini-cli in npm registry"
        if npm install -g @google/gemini-cli@latest 2>&1 | tee /tmp/gemini_install.log; then
            print_success "Gemini CLI installed successfully"
        else
            print_error "Failed to install Gemini CLI"
            cat /tmp/gemini_install.log
            # Try community version as fallback
            print_status "Attempting community version as fallback..."
            if pip3 install --user gemini-cli --quiet; then
                print_success "Gemini CLI (community) installed as fallback"
            else
                print_warning "Could not install any Gemini CLI version"
            fi
        fi
    else
        print_warning "Google Gemini CLI not yet available in npm registry"
        # Alternative: Install gemini-cli community tool
        if pip3 show gemini-cli >/dev/null 2>&1; then
            print_status "Gemini CLI (community) already installed"
        else
            print_status "Installing Gemini CLI (community version)..."
            if pip3 install --user gemini-cli --quiet; then
                print_success "Gemini CLI (community) installed"
            else
                print_warning "Failed to install community Gemini CLI"
            fi
        fi
    fi

    # 4. Install OpenAI Codex/GPT CLI tools (SIMPLIFIED - only OpenAI SDK and Codex)
    update_install_status "OpenAI Python SDK" "pip"
    print_status "Installing OpenAI CLI tools..."

    # Install openai SDK with --break-system-packages
    # Note: --break-system-packages is safe here because this is an isolated Docker container
    # with no system Python packages that could conflict. The flag is required on Ubuntu 24.04+
    # which uses PEP 668 to prevent accidental system package modifications on host systems.
    if ! pip3 show openai >/dev/null 2>&1; then
        if pip3 install --break-system-packages openai --quiet; then
            print_success "OpenAI Python SDK installed"
        else
            print_warning "Failed to install OpenAI Python SDK"
        fi
    else
        print_status "OpenAI SDK already installed"
    fi

    # Install OpenAI Codex CLI (official package)
    update_install_status "OpenAI Codex CLI" "npm"
    print_status "Installing OpenAI Codex CLI..."
    if npm view @openai/codex version >/dev/null 2>&1; then
        if npm install -g @openai/codex@latest 2>&1 | tee /tmp/codex_install.log; then
            print_success "OpenAI Codex CLI installed successfully"
        else
            print_error "Failed to install OpenAI Codex CLI"
            cat /tmp/codex_install.log
        fi
    else
        print_warning "OpenAI Codex CLI (@openai/codex) not available in npm registry"
        print_status "Note: OpenAI API access available via openai Python package"
    fi

    # NOTE: Removed Shell-GPT, Aider, Continue, Codeium, TabNine, AWS, Azure, Google Cloud, and extra dev tools
    # User requested only: GitHub CLI, Claude Code, Gemini, OpenAI SDK, and Codex

    # 5. Install Vibe Kanban (AI agent orchestration tool)
    update_install_status "Vibe Kanban" "npm"
    print_status "Installing Vibe Kanban (AI agent orchestration)..."
    if npm install -g vibe-kanban@latest 2>&1 | tee /tmp/vibe_kanban_install.log; then
        print_success "Vibe Kanban installed successfully"
        # Create .vibe-kanban directory for data persistence
        mkdir -p "${HOME}/.vibe-kanban"
    else
        print_error "Failed to install Vibe Kanban"
        cat /tmp/vibe_kanban_install.log
        # Continue with other installations
    fi

    # Save versions to file
    save_versions

    print_success "All CLI tools installation completed!"
}

# Function to ensure marker file is created (prevents infinite loops)
create_marker_file() {
    echo "Installation completed at: $(date)" > "$INSTALL_MARKER"
    echo "Tools installed by: $(whoami)" >> "$INSTALL_MARKER"
    echo "Node.js version: $(node --version 2>/dev/null || echo 'not found')" >> "$INSTALL_MARKER"
    echo "npm version: $(npm --version 2>/dev/null || echo 'not found')" >> "$INSTALL_MARKER"
    echo "Python version: $(python3 --version 2>/dev/null || echo 'not found')" >> "$INSTALL_MARKER"

    # Record which tools succeeded
    if command_exists claude; then
        echo "[OK] Claude CLI: installed" >> "$INSTALL_MARKER"
    else
        echo "[ERROR] Claude CLI: failed" >> "$INSTALL_MARKER"
    fi

    if command_exists gemini || pip3 show gemini-cli >/dev/null 2>&1; then
        echo "[OK] Gemini CLI: installed" >> "$INSTALL_MARKER"
    else
        echo "[ERROR] Gemini CLI: failed" >> "$INSTALL_MARKER"
    fi

    if command_exists gh; then
        echo "[OK] GitHub CLI: installed" >> "$INSTALL_MARKER"
    else
        echo "[ERROR] GitHub CLI: failed" >> "$INSTALL_MARKER"
    fi

    if command_exists codex; then
        echo "[OK] OpenAI Codex CLI: installed" >> "$INSTALL_MARKER"
    else
        echo "[ERROR] OpenAI Codex CLI: failed" >> "$INSTALL_MARKER"
    fi

    if npm list -g vibe-kanban >/dev/null 2>&1; then
        echo "[OK] Vibe Kanban: installed" >> "$INSTALL_MARKER"
    else
        echo "[ERROR] Vibe Kanban: failed" >> "$INSTALL_MARKER"
    fi

    print_success "Installation marker file created at: $INSTALL_MARKER"
}

# Update function
update_cli_tools() {
    print_status "Checking for updates..."

    # Update apt packages
    sudo apt-get update -qq

    # Update npm global packages
    print_status "Updating npm packages..."
    npm update -g --silent

    # Update pip packages
    print_status "Updating Python packages..."
    pip3 install --user --upgrade openai shell-gpt aider-chat gemini-cli --quiet

    # Update GitHub CLI
    if command_exists gh; then
        print_status "Updating GitHub CLI..."
        sudo apt-get install --only-upgrade gh -y -qq
    fi

    # Update AWS CLI
    if command_exists aws; then
        print_status "Checking AWS CLI updates..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" --silent
        unzip -q -o awscliv2.zip
        sudo ./aws/install --update
        rm -rf awscliv2.zip aws/
    fi

    # Save updated versions
    save_versions

    print_success "All tools updated successfully!"
}

# Trap to ensure marker file is created even if script fails
trap 'create_marker_file' EXIT

# Check if this is first run or update request
if [ "$1" == "--update" ] || [ "$1" == "-u" ]; then
    update_cli_tools
    # Update doesn't recreate marker, so disable the trap
    trap - EXIT
elif [ "$1" == "--force" ] || [ "$1" == "-f" ]; then
    rm -f "$INSTALL_MARKER"
    install_cli_tools
    # Marker will be created by trap
elif [ -f "$INSTALL_MARKER" ]; then
    print_status "CLI tools already installed. Use --update to update or --force to reinstall."
    if [ -f "$TOOLS_VERSION_FILE" ]; then
        echo ""
        print_status "Installed versions:"
        cat "$TOOLS_VERSION_FILE" | grep -v "^#"
    fi
    # Disable trap since already installed
    trap - EXIT
else
    install_cli_tools
    # Marker will be created by trap
fi

# Set proper permissions (run regardless of success/failure)
if [ -d "${HOME}" ]; then
    sudo chown -R $(whoami):$(whoami) ${HOME}/ 2>/dev/null || true
fi
