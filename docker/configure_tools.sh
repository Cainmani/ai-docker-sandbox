#!/bin/bash

# CLI Tools Configuration Helper
# This script helps users configure and sign into various AI CLI tools

# Ensure npm is configured to use user-local directory (fixes permission issues)
mkdir -p "${HOME}/.npm-global"
npm config set prefix "${HOME}/.npm-global"
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration file
# Use $HOME instead of USER_NAME since this runs as the user
CONFIG_FILE="${HOME}/.cli_tools_config"

# Function to print colored headers
print_header() {
    echo ""
    echo -e "${CYAN}================================================================================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}================================================================================================================================${NC}"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a tool is configured
is_configured() {
    local tool=$1
    case $tool in
        claude)
            # Check for ANTHROPIC_API_KEY environment variable
            if [ -n "$ANTHROPIC_API_KEY" ]; then
                return 0
            fi
            # Check for Claude config files (OAuth authentication creates files in ~/.claude/)
            if [ -f "${HOME}/.claude/config.json" ] || \
               [ -f "${HOME}/.claude/settings.json" ] || \
               [ -f "${HOME}/.claude/.credentials.json" ] || \
               [ -f "${HOME}/.claude/credentials.json" ]; then
                return 0
            fi
            ;;
        gh)
            if gh auth status >/dev/null 2>&1; then
                return 0
            fi
            ;;
        openai)
            if [ ! -z "$OPENAI_API_KEY" ] || [ -f "${HOME}/.config/openai/api_key" ]; then
                return 0
            fi
            ;;
        gemini)
            if [ ! -z "$GEMINI_API_KEY" ] || [ -f "${HOME}/.config/gemini/api_key" ]; then
                return 0
            fi
            ;;
        aws)
            if [ -f "${HOME}/.aws/credentials" ]; then
                return 0
            fi
            ;;
        azure)
            if az account show >/dev/null 2>&1; then
                return 0
            fi
            ;;
        gcloud)
            if gcloud auth list 2>/dev/null | grep -q ACTIVE; then
                return 0
            fi
            ;;
        codeium)
            if [ -f "${HOME}/.codeium/config.json" ]; then
                return 0
            fi
            ;;
        codex)
            # Codex can use OAuth (auth.json) for subscription, or OPENAI_API_KEY for API credits
            if [ -f "${HOME}/.codex/auth.json" ]; then
                return 0  # Subscription auth (preferred)
            elif [ ! -z "$OPENAI_API_KEY" ] || [ -f "${HOME}/.config/openai/api_key" ]; then
                return 0  # API key fallback
            fi
            ;;
    esac
    return 1
}

# Function to configure Claude Code
configure_claude() {
    print_header "Configure Claude Code CLI"

    if is_configured claude; then
        print_success "Claude Code is already configured"
        echo "To reconfigure, run: claude auth logout && claude auth login"
    else
        print_status "Claude Code requires authentication"
        echo ""
        echo "To get started:"
        echo "1. Run: claude auth login"
        echo "2. Follow the browser authentication flow"
        echo "3. Your credentials will be saved in ~/.claude/"
        echo ""
        read -p "Press Enter to configure Claude now, or Ctrl+C to skip..."
        claude auth login
    fi
}

# Function to configure GitHub CLI
configure_github() {
    print_header "Configure GitHub CLI"

    if is_configured gh; then
        print_success "GitHub CLI is already authenticated"
        gh auth status
    else
        print_status "GitHub CLI requires authentication"
        echo ""
        echo "Choose authentication method:"
        echo "1. Web browser (recommended)"
        echo "2. Authentication token"
        echo ""
        read -p "Select option (1 or 2): " auth_method

        case $auth_method in
            1)
                gh auth login --web
                ;;
            2)
                echo "Generate a token at: https://github.com/settings/tokens"
                echo "Required scopes: repo, read:org, workflow"
                gh auth login
                ;;
            *)
                print_warning "Invalid option, skipping GitHub CLI configuration"
                ;;
        esac
    fi
}

# Function to configure OpenAI/GPT
configure_openai() {
    print_header "Configure OpenAI/GPT Tools"

    if is_configured openai; then
        print_success "OpenAI API is already configured"
    else
        print_status "OpenAI tools require an API key"
        echo ""
        echo "Get your API key from: https://platform.openai.com/api-keys"
        echo ""
        read -sp "Enter your OpenAI API key (input hidden): " api_key
        echo ""

        if [ ! -z "$api_key" ]; then
            # Save to config file
            mkdir -p "${HOME}/.config/openai"
            echo "$api_key" > "${HOME}/.config/openai/api_key"
            chmod 600 "${HOME}/.config/openai/api_key"

            # Add to bashrc
            if ! grep -q "OPENAI_API_KEY" "${HOME}/.bashrc"; then
                echo "" >> "${HOME}/.bashrc"
                echo "# OpenAI API Configuration" >> "${HOME}/.bashrc"
                echo "export OPENAI_API_KEY='$api_key'" >> "${HOME}/.bashrc"
            fi

            # Configure shell-gpt
            mkdir -p "${HOME}/.config/shell_gpt"
            cat > "${HOME}/.config/shell_gpt/.sgptrc" << EOF
DEFAULT_MODEL=gpt-4
OPENAI_API_KEY=$api_key
CHAT_CACHE_PATH=/tmp/sgpt_cache
CHAT_CACHE_LENGTH=100
REQUEST_TIMEOUT=60
DEFAULT_COLOR=magenta
EOF
            chmod 600 "${HOME}/.config/shell_gpt/.sgptrc"

            export OPENAI_API_KEY="$api_key"
            print_success "OpenAI API configured successfully"
            echo "You can now use: sgpt, aider, and other OpenAI-based tools"
        else
            print_warning "No API key provided, skipping OpenAI configuration"
        fi
    fi
}

# Function to configure Google Gemini
configure_gemini() {
    print_header "Configure Google Gemini"

    if is_configured gemini; then
        print_success "Gemini API is already configured"
    else
        print_status "Gemini requires an API key"
        echo ""
        echo "Get your API key from: https://makersuite.google.com/app/apikey"
        echo ""
        read -sp "Enter your Gemini API key (input hidden): " api_key
        echo ""

        if [ ! -z "$api_key" ]; then
            # Save to config file
            mkdir -p "${HOME}/.config/gemini"
            echo "$api_key" > "${HOME}/.config/gemini/api_key"
            chmod 600 "${HOME}/.config/gemini/api_key"

            # Add to bashrc
            if ! grep -q "GEMINI_API_KEY" "${HOME}/.bashrc"; then
                echo "" >> "${HOME}/.bashrc"
                echo "# Gemini API Configuration" >> "${HOME}/.bashrc"
                echo "export GEMINI_API_KEY='$api_key'" >> "${HOME}/.bashrc"
            fi

            export GEMINI_API_KEY="$api_key"
            print_success "Gemini API configured successfully"
        else
            print_warning "No API key provided, skipping Gemini configuration"
        fi
    fi
}

# Function to configure AWS CLI
configure_aws() {
    print_header "Configure AWS CLI"

    if is_configured aws; then
        print_success "AWS CLI is already configured"
        aws configure list
    else
        print_status "AWS CLI requires credentials"
        echo ""
        echo "You'll need:"
        echo "- AWS Access Key ID"
        echo "- AWS Secret Access Key"
        echo "- Default region (e.g., us-east-1)"
        echo ""
        read -p "Press Enter to configure AWS CLI, or Ctrl+C to skip..."
        aws configure
    fi
}

# Function to configure Azure CLI
configure_azure() {
    print_header "Configure Azure CLI"

    if is_configured azure; then
        print_success "Azure CLI is already authenticated"
        az account show
    else
        print_status "Azure CLI requires authentication"
        echo ""
        echo "Choose authentication method:"
        echo "1. Web browser (recommended)"
        echo "2. Device code"
        echo "3. Service principal"
        echo ""
        read -p "Select option (1, 2, or 3): " auth_method

        case $auth_method in
            1)
                az login
                ;;
            2)
                az login --use-device-code
                ;;
            3)
                echo "You'll need: tenant ID, app ID, and password/certificate"
                read -p "Press Enter to continue..."
                az login --service-principal
                ;;
            *)
                print_warning "Invalid option, skipping Azure CLI configuration"
                ;;
        esac
    fi
}

# Function to configure Google Cloud CLI
configure_gcloud() {
    print_header "Configure Google Cloud CLI"

    if is_configured gcloud; then
        print_success "Google Cloud CLI is already authenticated"
        gcloud auth list
    else
        print_status "Google Cloud CLI requires authentication"
        echo ""
        read -p "Press Enter to authenticate with Google Cloud, or Ctrl+C to skip..."
        gcloud auth login
        gcloud config set project $(gcloud projects list --limit=1 --format="value(projectId)")
    fi
}

# Function to configure Codeium
configure_codeium() {
    print_header "Configure Codeium"

    if is_configured codeium; then
        print_success "Codeium is already configured"
    else
        print_status "Codeium requires authentication"
        echo ""
        echo "To get started:"
        echo "1. Run: codeium auth"
        echo "2. Follow the browser authentication flow"
        echo ""
        read -p "Press Enter to configure Codeium now, or Ctrl+C to skip..."
        codeium auth
    fi
}

# Function to configure OpenAI Codex CLI
configure_codex() {
    print_header "Configure OpenAI Codex CLI"

    # Ensure ~/.codex directory exists
    mkdir -p "${HOME}/.codex"

    # Create or update config.toml to use modern Responses API
    # The deprecated "chat" wire_api causes connection errors and will be removed Feb 2026
    local config_file="${HOME}/.codex/config.toml"
    if [ ! -f "$config_file" ]; then
        print_status "Creating default Codex config.toml..."
        cat > "$config_file" << 'TOML'
# Codex CLI Configuration
# See: https://developers.openai.com/codex/config-reference/

# Model settings
model = "gpt-5.2-codex"
model_provider = "openai"

# Safety settings
approval_policy = "on-request"
sandbox_mode = "workspace-write"

# Environment variables to forward to shell
[shell_environment_policy]
include_only = ["PATH", "HOME", "USER", "TERM"]

# Features
[features]
shell_tool = true
web_search_request = true
TOML
        print_success "Created config.toml with modern Responses API"
    elif grep -q 'wire_api.*=.*"chat"' "$config_file" 2>/dev/null; then
        # Migrate deprecated chat API to responses API
        print_warning "Detected deprecated wire_api = \"chat\" in config.toml"
        print_status "Updating to wire_api = \"responses\"..."
        sed -i 's/wire_api.*=.*"chat"/wire_api = "responses"/g' "$config_file"
        print_success "Updated config.toml to use modern Responses API"
    fi

    # Check if already authenticated via OAuth (auth.json exists)
    if [ -f "${HOME}/.codex/auth.json" ]; then
        print_success "Codex CLI is authenticated (using subscription login)"
        echo ""
        echo "Test with: codex --help"
        return 0
    fi

    # Check if API key is configured as fallback
    if [ -n "$OPENAI_API_KEY" ] || [ -f "${HOME}/.config/openai/api_key" ]; then
        print_success "Codex CLI can use OPENAI_API_KEY (API credits)"
        print_warning "Note: API key uses pay-per-use credits, not your subscription."
        echo ""
        echo "To use your ChatGPT Plus/Pro subscription instead, see Option 1 below."
        echo ""
    fi

    print_status "Codex CLI Authentication Options"
    echo ""
    print_warning "KNOWN ISSUE: Browser-based OAuth does not work inside Docker containers."
    echo "See: https://github.com/openai/codex/issues/2798"
    echo ""
    echo -e "${CYAN}=== OPTION 1: Use Your Subscription (Recommended) ===${NC}"
    echo ""
    echo "To use your ChatGPT Plus/Pro subscription (no API credits needed):"
    echo ""
    echo "  1. On your Windows host (outside Docker), install Codex:"
    echo "     npm install -g @openai/codex"
    echo ""
    echo "  2. Run 'codex' on Windows and complete the browser login"
    echo ""
    echo -e "  3. ${GREEN}AUTO-SYNC: Next time you 'Launch AI Workspace', your auth${NC}"
    echo -e "     ${GREEN}will be automatically copied into the container!${NC}"
    echo ""
    echo "     (Manual copy if needed: docker cp \"\$env:USERPROFILE\\.codex\\auth.json\" ai-cli:/home/\$USER/.codex/)"
    echo ""
    echo -e "${CYAN}=== OPTION 2: Use API Key (Pay-per-use Credits) ===${NC}"
    echo ""
    echo "If you prefer to use API credits instead of your subscription:"
    echo "  - Get your API key from: https://platform.openai.com/api-keys"
    echo "  - Run: configure-tools --openai"
    echo ""
    echo -e "${YELLOW}Note: API key billing is separate from your ChatGPT subscription.${NC}"
    echo ""
}

# Function to show configuration status
show_status() {
    print_header "CLI Tools Configuration Status"
    echo ""

    tools=(
        "claude:Claude Code CLI"
        "gh:GitHub CLI"
        "openai:OpenAI/GPT Tools"
        "codex:OpenAI Codex CLI"
        "gemini:Google Gemini"
        "aws:AWS CLI"
        "azure:Azure CLI"
        "gcloud:Google Cloud CLI"
        "codeium:Codeium"
    )

    for tool_info in "${tools[@]}"; do
        IFS=':' read -r tool name <<< "$tool_info"
        if is_configured "$tool"; then
            echo -e "${GREEN}[OK]${NC} $name - Configured"
        else
            echo -e "${RED}[ERROR]${NC} $name - Not configured"
        fi
    done

    echo ""
}

# Function for interactive configuration
interactive_configure() {
    clear
    print_header "AI CLI Tools Configuration Wizard"
    echo ""
    echo "This wizard will help you configure various AI CLI tools."
    echo "You can skip any tool and configure it later."
    echo ""

    show_status

    echo "Select tools to configure:"
    echo ""
    echo "1. Claude Code CLI"
    echo "2. GitHub CLI"
    echo "3. OpenAI/GPT Tools (Python SDK)"
    echo "4. OpenAI Codex CLI"
    echo "5. Google Gemini"
    echo "6. AWS CLI"
    echo "7. Azure CLI"
    echo "8. Google Cloud CLI"
    echo "9. Codeium"
    echo "A. Configure All"
    echo "0. Exit"
    echo ""

    read -p "Enter your choice (0-9, A): " choice

    case $choice in
        1) configure_claude; interactive_configure ;;
        2) configure_github; interactive_configure ;;
        3) configure_openai; interactive_configure ;;
        4) configure_codex; interactive_configure ;;
        5) configure_gemini; interactive_configure ;;
        6) configure_aws; interactive_configure ;;
        7) configure_azure; interactive_configure ;;
        8) configure_gcloud; interactive_configure ;;
        9) configure_codeium; interactive_configure ;;
        [Aa])
            configure_claude
            configure_github
            configure_openai
            configure_codex
            configure_gemini
            configure_aws
            configure_azure
            configure_gcloud
            configure_codeium
            show_status
            ;;
        0)
            echo "Configuration complete!"
            show_status
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            sleep 2
            interactive_configure
            ;;
    esac
}

# Main execution
case "$1" in
    --status|-s)
        show_status
        ;;
    --claude)
        configure_claude
        ;;
    --github|--gh)
        configure_github
        ;;
    --openai|--gpt)
        configure_openai
        ;;
    --gemini)
        configure_gemini
        ;;
    --aws)
        configure_aws
        ;;
    --azure)
        configure_azure
        ;;
    --gcloud)
        configure_gcloud
        ;;
    --codeium)
        configure_codeium
        ;;
    --codex)
        configure_codex
        ;;
    --all)
        configure_claude
        configure_github
        configure_openai
        configure_codex
        configure_gemini
        configure_aws
        configure_azure
        configure_gcloud
        configure_codeium
        show_status
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --status, -s     Show configuration status"
        echo "  --claude         Configure Claude Code CLI"
        echo "  --github, --gh   Configure GitHub CLI"
        echo "  --openai, --gpt  Configure OpenAI/GPT tools (Python SDK)"
        echo "  --codex          Configure OpenAI Codex CLI"
        echo "  --gemini         Configure Google Gemini"
        echo "  --aws            Configure AWS CLI"
        echo "  --azure          Configure Azure CLI"
        echo "  --gcloud         Configure Google Cloud CLI"
        echo "  --codeium        Configure Codeium"
        echo "  --all            Configure all tools"
        echo "  --help, -h       Show this help message"
        echo ""
        echo "Without options, runs interactive configuration wizard"
        ;;
    *)
        interactive_configure
        ;;
esac