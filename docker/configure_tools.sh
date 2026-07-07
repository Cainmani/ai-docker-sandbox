#!/bin/bash

# CLI Tools Configuration Helper
# This script helps users configure and sign into various AI CLI tools
# Note: set -e is omitted so users can skip/cancel individual tool configs.
set -uo pipefail

# Ensure npm is configured to use user-local directory (fixes permission issues)
mkdir -p "${HOME}/.npm-global"
npm config set prefix "${HOME}/.npm-global"
# Include: npm global and local bin paths (Claude native installer uses ~/.local/bin)
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

# Source logging library
if [ -f "/usr/local/lib/logging.sh" ]; then
    source "/usr/local/lib/logging.sh"
    LOG_FILE=$(init_logging "CONFIGURE" "configure")
fi

# Helper function for logging (only logs if library is available)
# IMPORTANT: Never log API keys, tokens, or credentials - only log that configuration happened
config_log() {
    local level="$1"
    local message="$2"
    if [ -n "${LOG_FILE:-}" ]; then
        log_message "CONFIGURE" "$level" "$message" "$LOG_FILE"
    fi
}

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

# Function to check if a tool is configured
is_configured() {
    local tool=$1
    local install_marker="${HOME}/.cli_tools_installed"

    case $tool in
        claude)
            # First verify Claude binary actually works (catches broken installations)
            if ! claude --version >/dev/null 2>&1; then
                return 1  # Claude is broken or not installed
            fi
            # Check for ANTHROPIC_API_KEY environment variable (doesn't need rebuild check)
            if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
                return 0
            fi
            # Check for Claude OAuth credentials (persisted via claude-config volume)
            # If the token has actually expired, Claude itself will prompt for re-auth
            local creds_file="${HOME}/.claude/.credentials.json"
            if [ -f "$creds_file" ] && [ -s "$creds_file" ]; then
                return 0
            fi
            ;;
        gh)
            if gh auth status >/dev/null 2>&1; then
                return 0
            fi
            ;;
        openai)
            if [ -n "${OPENAI_API_KEY:-}" ] || [ -f "${HOME}/.config/openai/api_key" ]; then
                return 0
            fi
            ;;
        gemini)
            if [ -n "${GEMINI_API_KEY:-}" ] || [ -f "${HOME}/.config/gemini/api_key" ]; then
                return 0
            fi
            ;;
        codex)
            # Codex can use OAuth (auth.json) for subscription, or OPENAI_API_KEY for API credits
            if [ -f "${HOME}/.codex/auth.json" ]; then
                return 0  # Subscription auth (preferred)
            elif [ -n "${OPENAI_API_KEY:-}" ] || [ -f "${HOME}/.config/openai/api_key" ]; then
                return 0  # API key fallback
            fi
            ;;
        ai_router)
            # 9router / OmniRoute are configured in their web dashboard (you link each AI
            # subscription there), not via a CLI key. Treat "either installed" as ready-to-use.
            if npm list -g 9router >/dev/null 2>&1 || npm list -g omniroute >/dev/null 2>&1; then
                return 0
            fi
            ;;
    esac
    return 1
}

# Function to configure Claude Code
configure_claude() {
    print_header "Configure Claude Code CLI"
    config_log "INFO" "User initiated Claude Code CLI configuration"

    # Check if claude is installed (check PATH and common locations)
    local claude_cmd=""
    if command -v claude &> /dev/null; then
        claude_cmd="claude"
    elif [ -x "${HOME}/.local/bin/claude" ]; then
        claude_cmd="${HOME}/.local/bin/claude"
    elif [ -x "/usr/local/bin/claude" ]; then
        claude_cmd="/usr/local/bin/claude"
    fi

    if [ -z "$claude_cmd" ]; then
        print_error "Claude Code CLI is not installed"
        echo ""
        echo "Install with: curl -fsSL https://claude.ai/install.sh | sh"
        echo ""
        read -rp "Press Enter to continue..." _
        return 1
    fi

    if is_configured claude; then
        print_success "Claude Code is already configured"
        config_log "INFO" "Claude Code CLI: already configured"
        echo "To reconfigure, run: claude"
        echo ""
        read -rp "Press Enter to continue..." _
    else
        print_status "Claude Code requires authentication"
        echo ""
        echo "You'll be prompted to sign in with your Anthropic account."
        echo ""
        read -rp "Press Enter to configure Claude now, or Ctrl+C to skip..."
        config_log "INFO" "Claude Code CLI: authentication started"
        "$claude_cmd"
        config_log "INFO" "Claude Code CLI: authentication completed"
    fi
}

# Function to configure GitHub CLI
configure_github() {
    print_header "Configure GitHub CLI"
    config_log "INFO" "User initiated GitHub CLI configuration"

    if is_configured gh; then
        print_success "GitHub CLI is already authenticated"
        config_log "INFO" "GitHub CLI: already authenticated"
        gh auth status
        echo ""
        read -rp "Press Enter to continue..." _
    else
        print_status "GitHub CLI requires authentication"
        echo ""
        echo "You'll be prompted to choose your sign-in method."
        echo ""
        read -rp "Press Enter to configure GitHub now, or Ctrl+C to skip..."
        config_log "INFO" "GitHub CLI: authentication started"
        gh auth login
        config_log "INFO" "GitHub CLI: authentication completed"
    fi
}

# Function to configure OpenAI/GPT
configure_openai() {
    print_header "Configure OpenAI/GPT Tools"
    config_log "INFO" "User initiated OpenAI/GPT configuration"

    if is_configured openai; then
        print_success "OpenAI API is already configured"
        config_log "INFO" "OpenAI: already configured"
        echo ""
        read -rp "Press Enter to continue..." _
    else
        print_status "OpenAI tools require an API key"
        echo ""
        echo "Get your API key from: https://platform.openai.com/api-keys"
        echo ""
        read -rsp "Enter your OpenAI API key (input hidden): " api_key
        echo ""

        if [ -n "$api_key" ]; then
            # Save to config file (secure storage)
            mkdir -p "${HOME}/.config/openai"
            printf '%s' "$api_key" > "${HOME}/.config/openai/api_key"
            chmod 600 "${HOME}/.config/openai/api_key"

            # Add to bashrc - read from secure file instead of embedding key directly
            if ! grep -q "OPENAI_API_KEY" "${HOME}/.bashrc"; then
                cat >> "${HOME}/.bashrc" << 'BASHRC_EOF'

# OpenAI API Configuration (reads from secure config file)
if [ -f "${HOME}/.config/openai/api_key" ]; then
    export OPENAI_API_KEY="$(cat "${HOME}/.config/openai/api_key")"
fi
BASHRC_EOF
            fi

            export OPENAI_API_KEY="$api_key"
            print_success "OpenAI API configured successfully"
            config_log "INFO" "OpenAI: API key configured"
        else
            print_warning "No API key provided, skipping OpenAI configuration"
            config_log "WARN" "OpenAI: configuration skipped (no API key provided)"
        fi
    fi
}

# Function to configure Google Gemini
configure_gemini() {
    print_header "Configure Google Gemini CLI"
    config_log "INFO" "User initiated Google Gemini CLI configuration"

    # Check if gemini is installed (check PATH and common locations)
    local gemini_cmd=""
    if command -v gemini &> /dev/null; then
        gemini_cmd="gemini"
    elif [ -x "/usr/local/bin/gemini" ]; then
        gemini_cmd="/usr/local/bin/gemini"
    elif [ -x "${HOME}/.npm-global/bin/gemini" ]; then
        gemini_cmd="${HOME}/.npm-global/bin/gemini"
    elif [ -x "/usr/bin/gemini" ]; then
        gemini_cmd="/usr/bin/gemini"
    fi

    if [ -z "$gemini_cmd" ]; then
        print_error "Gemini CLI is not installed"
        echo ""
        echo "Install with: npm install -g @google/gemini-cli"
        echo ""
        read -rp "Press Enter to continue..." _
        return 1
    fi

    if is_configured gemini; then
        print_success "Gemini CLI is already configured"
        config_log "INFO" "Gemini CLI: already configured"
        echo "To reconfigure, run: gemini"
        echo ""
        read -rp "Press Enter to continue..." _
    else
        print_status "Gemini CLI requires authentication"
        echo ""
        echo "You'll be prompted to sign in with your Google account."
        echo ""
        read -rp "Press Enter to configure Gemini now, or Ctrl+C to skip..."
        config_log "INFO" "Gemini CLI: authentication started"
        "$gemini_cmd"
        config_log "INFO" "Gemini CLI: authentication completed"
    fi
}

# Function to configure OpenAI Codex CLI
configure_codex() {
    print_header "Configure OpenAI Codex CLI"
    config_log "INFO" "User initiated OpenAI Codex CLI configuration"

    # Ensure ~/.codex directory exists
    mkdir -p "${HOME}/.codex"

    # Create or update config.toml to use modern Responses API
    # The deprecated "chat" wire_api causes connection errors and will be removed Feb 2026
    local config_file="${HOME}/.codex/config.toml"
    if [ ! -f "$config_file" ]; then
        print_status "Creating default Codex config.toml..."
            local codex_model="${CODEX_MODEL:-gpt-5.2-codex}"
        cat > "$config_file" << TOML
# Codex CLI Configuration
# See: https://developers.openai.com/codex/config-reference/

# Model settings (override with CODEX_MODEL env var)
model = "$codex_model"
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

    # Check if codex is installed (check PATH and common npm locations)
    local codex_cmd=""
    if command -v codex &> /dev/null; then
        codex_cmd="codex"
    elif [ -x "/usr/local/bin/codex" ]; then
        codex_cmd="/usr/local/bin/codex"
    elif [ -x "${HOME}/.npm-global/bin/codex" ]; then
        codex_cmd="${HOME}/.npm-global/bin/codex"
    elif [ -x "/usr/bin/codex" ]; then
        codex_cmd="/usr/bin/codex"
    fi

    if [ -z "$codex_cmd" ]; then
        print_error "Codex CLI is not installed"
        echo ""
        echo "Install with: npm install -g @openai/codex"
        echo ""
        read -rp "Press Enter to continue..." _
        return 1
    fi

    if is_configured codex; then
        print_success "Codex CLI is already configured"
        config_log "INFO" "Codex CLI: already configured"
        echo "To reconfigure, run: codex"
        echo ""
        read -rp "Press Enter to continue..." _
    else
        print_status "Codex CLI requires authentication"
        echo ""
        echo "You'll be prompted to choose your sign-in method:"
        echo "  - ChatGPT subscription (Plus/Pro) - no API credits needed"
        echo "  - API key - uses pay-per-use credits"
        echo ""
        read -rp "Press Enter to configure Codex now, or Ctrl+C to skip..."
        config_log "INFO" "Codex CLI: authentication started"
        "$codex_cmd"
        config_log "INFO" "Codex CLI: authentication completed"
    fi
}

# Function to configure the AI router slot (9router / OmniRoute)
# 9router and OmniRoute are interchangeable unified-router tools that share one dashboard port,
# so only ONE runs at a time. This helper shows which (if any) is running, lets the user pick
# one, stops any other router, and starts the chosen one bound to 0.0.0.0 so the host browser
# can reach it. Subscriptions are linked inside the dashboard, not from this menu.
configure_ai_router() {
    print_header "Configure AI Router (9router / OmniRoute)"
    config_log "INFO" "User initiated AI router configuration"

    local port="${AI_ROUTER_PORT:-20128}"

    # Which routers are installed?
    local have_9router=false have_omniroute=false
    npm list -g 9router   >/dev/null 2>&1 && have_9router=true
    npm list -g omniroute >/dev/null 2>&1 && have_omniroute=true

    if [ "$have_9router" = false ] && [ "$have_omniroute" = false ]; then
        print_error "Neither 9router nor OmniRoute is installed"
        echo ""
        echo "They normally install automatically during setup - try 'update-container-tools',"
        echo "or install manually: npm install -g 9router   (or)   npm install -g omniroute"
        echo ""
        read -rp "Press Enter to continue..." _
        return 1
    fi

    print_status "9router and OmniRoute both link multiple AI subscriptions behind one"
    print_status "OpenAI-compatible endpoint. They share port $port, so only one runs at a time."
    echo ""
    echo "  Note: you sign into each AI provider in the router's web dashboard - not here."
    echo ""

    # Report which router (if any) is currently running
    local running=""
    if pgrep -f '9router'   >/dev/null 2>&1; then running="9router"; fi
    if pgrep -f 'omniroute' >/dev/null 2>&1; then running="omniroute"; fi
    if [ -n "$running" ]; then
        print_success "Currently running: $running  ->  http://localhost:$port/dashboard"
        echo ""
    fi

    # Offer only the installed routers
    echo "Which router do you want to run?"
    [ "$have_9router"   = true ] && echo "  1. 9router"
    [ "$have_omniroute" = true ] && echo "  2. OmniRoute"
    echo "  0. Keep current / skip"
    echo ""
    read -rp "Enter your choice: " router_choice

    local tool=""
    case "$router_choice" in
        1) if [ "$have_9router" = true ];   then tool="9router";   else print_error "9router is not installed";   read -rp "Press Enter to continue..." _; return 1; fi ;;
        2) if [ "$have_omniroute" = true ]; then tool="omniroute"; else print_error "OmniRoute is not installed"; read -rp "Press Enter to continue..." _; return 1; fi ;;
        0|"") print_status "No change."; read -rp "Press Enter to continue..." _; return 0 ;;
        *) print_error "Invalid choice"; read -rp "Press Enter to continue..." _; return 1 ;;
    esac

    # Stop whichever router is running (enforces one-at-a-time), then start the chosen one.
    # Escalate SIGTERM -> SIGKILL and WAIT for the shared port to be released before starting;
    # otherwise the new router hits EADDRINUSE and the dashboard shows "Internal Server Error".
    print_status "Stopping any running router..."
    if pgrep -f '9router|omniroute' >/dev/null 2>&1; then
        pkill -TERM -f '9router'   2>/dev/null || true
        pkill -TERM -f 'omniroute' 2>/dev/null || true
        local stop_waited=0
        while pgrep -f '9router|omniroute' >/dev/null 2>&1 && [ "$stop_waited" -lt 5 ]; do
            sleep 1; stop_waited=$((stop_waited + 1))
        done
        pkill -KILL -f '9router'   2>/dev/null || true
        pkill -KILL -f 'omniroute' 2>/dev/null || true
    fi
    # Wait for the shared port to actually be free (TIME_WAIT / slow teardown) before launching.
    local port_waited=0
    while netstat -tln 2>/dev/null | grep -q ":$port " && [ "$port_waited" -lt 10 ]; do
        sleep 1; port_waited=$((port_waited + 1))
    done

    print_status "Starting $tool on 0.0.0.0:$port ..."
    config_log "INFO" "AI router: starting $tool on port $port"
    # Bind 0.0.0.0 (not localhost) so Docker's published port reaches it. DATA_DIR points at the
    # tool's own persisted data dir (survives rebuilds). Detached.
    local data_dir="$HOME/.router-data/$tool"
    mkdir -p "$data_dir"
    HOST=0.0.0.0 HOSTNAME=0.0.0.0 PORT="$port" DATA_DIR="$data_dir" nohup "$tool" > "/tmp/$tool.log" 2>&1 &
    disown 2>/dev/null || true

    # Wait for it to listen (first run may download assets)
    local waited=0
    while [ $waited -lt 30 ]; do
        netstat -tlnp 2>/dev/null | grep -q ":$port " && break
        sleep 1
        waited=$((waited + 1))
    done

    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        print_success "$tool started."
        config_log "INFO" "AI router: $tool started on port $port"
    else
        print_warning "$tool did not report ready within 30s - it may still be starting."
        print_warning "Check /tmp/$tool.log for details."
        config_log "WARN" "AI router: $tool not listening within timeout on port $port"
    fi
    echo ""
    echo "  Open the dashboard from your host browser and link your subscriptions there:"
    echo "    http://localhost:$port/dashboard"
    echo ""
    read -rp "Press Enter to continue..." _
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
        "ai_router:AI Router (9router / OmniRoute)"
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
    while true; do
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
        echo "6. AI Router (9router / OmniRoute)"
        echo "A. Configure All"
        echo "0. Exit"
        echo ""

        read -rp "Enter your choice (0-6, A): " choice

        case $choice in
            1) configure_claude ;;
            2) configure_github ;;
            3) configure_openai ;;
            4) configure_codex ;;
            5) configure_gemini ;;
            6) configure_ai_router ;;
            [Aa])
                configure_claude
                configure_github
                configure_openai
                configure_codex
                configure_gemini
                configure_ai_router
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
                ;;
        esac
    done
}

# Main execution
case "${1:-}" in
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
    --codex)
        configure_codex
        ;;
    --ai-router|--9router|--omniroute)
        configure_ai_router
        ;;
    --all)
        configure_claude
        configure_github
        configure_openai
        configure_codex
        configure_gemini
        configure_ai_router
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
        echo "  --ai-router      Choose/start the AI router (9router or OmniRoute)"
        echo "  --all            Configure all tools"
        echo "  --help, -h       Show this help message"
        echo ""
        echo "Without options, runs interactive configuration wizard"
        ;;
    *)
        interactive_configure
        ;;
esac