#!/bin/bash

# AI Docker CLI Tools Installation Script
# This script installs and configures all necessary CLI tools for AI development
# It runs on first container start and can be used for updates

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation tracking file
INSTALL_MARKER="/home/${USER_NAME}/.cli_tools_installed"
TOOLS_VERSION_FILE="/home/${USER_NAME}/.cli_tools_versions"

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
}

# Main installation function
install_cli_tools() {
    print_status "Starting CLI tools installation..."

    # Update package lists
    print_status "Updating package lists..."
    sudo apt-get update -qq

    # 1. Install GitHub CLI
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
    print_status "Installing/Updating Claude Code CLI..."
    sudo npm install -g @anthropic-ai/claude-code@latest --silent
    print_success "Claude Code CLI installed/updated successfully"

    # 3. Install Google Gemini CLI (if available)
    # Note: As of now, Google Gemini doesn't have an official CLI, but we'll prepare for it
    print_status "Checking for Google Gemini CLI..."
    if npm view @google/gemini-cli >/dev/null 2>&1; then
        sudo npm install -g @google/gemini-cli@latest --silent
        print_success "Gemini CLI installed successfully"
    else
        print_warning "Google Gemini CLI not yet available in npm registry"
        # Alternative: Install gemini-cli community tool
        if pip3 show gemini-cli >/dev/null 2>&1; then
            print_status "Gemini CLI (community) already installed"
        else
            print_status "Installing Gemini CLI (community version)..."
            pip3 install --user gemini-cli --quiet
            print_success "Gemini CLI (community) installed"
        fi
    fi

    # 4. Install OpenAI Codex/GPT CLI tools
    print_status "Installing OpenAI CLI tools..."

    # Install openai CLI
    if ! pip3 show openai >/dev/null 2>&1; then
        pip3 install --user openai --quiet
        print_success "OpenAI Python SDK installed"
    else
        print_status "OpenAI SDK already installed"
    fi

    # Install shell-gpt (sgpt) - a popular GPT CLI tool
    if ! command_exists sgpt; then
        print_status "Installing Shell-GPT..."
        pip3 install --user shell-gpt --quiet
        print_success "Shell-GPT installed successfully"
    else
        print_status "Shell-GPT already installed"
    fi

    # 5. Install Aider (AI pair programming tool)
    if ! command_exists aider; then
        print_status "Installing Aider (AI pair programming tool)..."
        pip3 install --user aider-chat --quiet
        print_success "Aider installed successfully"
    else
        print_status "Aider already installed"
    fi

    # 6. Install Continue (AI code assistant)
    print_status "Checking for Continue CLI..."
    if npm view continue >/dev/null 2>&1; then
        sudo npm install -g continue@latest --silent
        print_success "Continue CLI installed"
    else
        print_warning "Continue CLI not available in npm registry"
    fi

    # 7. Install Codeium CLI
    if ! command_exists codeium; then
        print_status "Installing Codeium CLI..."
        curl -Ls https://github.com/Exafunction/codeium/releases/latest/download/codeium_linux_x64.tar.gz | sudo tar -xz -C /usr/local/bin/
        sudo chmod +x /usr/local/bin/codeium
        print_success "Codeium CLI installed successfully"
    else
        print_status "Codeium already installed"
    fi

    # 8. Install TabNine CLI (if available)
    print_status "Checking for TabNine CLI..."
    if npm view tabnine-cli >/dev/null 2>&1; then
        sudo npm install -g tabnine-cli@latest --silent
        print_success "TabNine CLI installed"
    else
        print_warning "TabNine CLI not available in npm registry"
    fi

    # 9. Install AWS CLI (useful for AWS AI services)
    if ! command_exists aws; then
        print_status "Installing AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" --silent
        unzip -q awscliv2.zip
        sudo ./aws/install --update
        rm -rf awscliv2.zip aws/
        print_success "AWS CLI installed successfully"
    else
        print_status "AWS CLI already installed"
    fi

    # 10. Install Azure CLI (for Azure AI services)
    if ! command_exists az; then
        print_status "Installing Azure CLI..."
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        print_success "Azure CLI installed successfully"
    else
        print_status "Azure CLI already installed"
    fi

    # 11. Install gcloud CLI (for Google Cloud AI services)
    if ! command_exists gcloud; then
        print_status "Installing Google Cloud CLI..."
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
        curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
        sudo apt-get update -qq && sudo apt-get install google-cloud-cli -y -qq
        print_success "Google Cloud CLI installed successfully"
    else
        print_status "Google Cloud CLI already installed"
    fi

    # 12. Install useful development tools
    print_status "Installing additional development tools..."

    # jq for JSON processing
    if ! command_exists jq; then
        sudo apt-get install jq -y -qq
        print_success "jq installed"
    fi

    # httpie for API testing
    if ! command_exists http; then
        sudo apt-get install httpie -y -qq
        print_success "HTTPie installed"
    fi

    # bat - better cat with syntax highlighting
    if ! command_exists bat; then
        sudo apt-get install bat -y -qq
        sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
        print_success "bat installed"
    fi

    # fzf - fuzzy finder
    if ! command_exists fzf; then
        sudo apt-get install fzf -y -qq
        print_success "fzf installed"
    fi

    # ripgrep - faster grep
    if ! command_exists rg; then
        sudo apt-get install ripgrep -y -qq
        print_success "ripgrep installed"
    fi

    # fd - better find
    if ! command_exists fd; then
        sudo apt-get install fd-find -y -qq
        sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
        print_success "fd installed"
    fi

    # tldr - simplified man pages
    if ! command_exists tldr; then
        sudo npm install -g tldr --silent
        print_success "tldr installed"
    fi

    # Save versions to file
    save_versions

    # Create marker file
    echo "Installation completed at: $(date)" > "$INSTALL_MARKER"
    echo "Tools installed by: $(whoami)" >> "$INSTALL_MARKER"

    print_success "All CLI tools installation completed!"
}

# Update function
update_cli_tools() {
    print_status "Checking for updates..."

    # Update apt packages
    sudo apt-get update -qq

    # Update npm global packages
    print_status "Updating npm packages..."
    sudo npm update -g --silent

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

# Check if this is first run or update request
if [ "$1" == "--update" ] || [ "$1" == "-u" ]; then
    update_cli_tools
elif [ "$1" == "--force" ] || [ "$1" == "-f" ]; then
    rm -f "$INSTALL_MARKER"
    install_cli_tools
elif [ -f "$INSTALL_MARKER" ]; then
    print_status "CLI tools already installed. Use --update to update or --force to reinstall."
    if [ -f "$TOOLS_VERSION_FILE" ]; then
        echo ""
        print_status "Installed versions:"
        cat "$TOOLS_VERSION_FILE" | grep -v "^#"
    fi
else
    install_cli_tools
fi

# Set proper permissions
chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/