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

# Reuse the same migration and router ownership logic as container startup and
# the generated shell wrappers. Missing helpers are an installation error, not
# a reason to fall back to broad process matching or an unsafe config rewrite.
eh_log() { config_log "$1" "$2"; }
for helper in /usr/local/lib/entrypoint_helpers.sh /usr/local/lib/router_utils.sh; do
    if [ ! -f "$helper" ]; then
        echo "ERROR: required helper is missing: $helper" >&2
        exit 1
    fi
    # shellcheck disable=SC1090  # helper path is validated above; not statically known
    source "$helper"
done

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
    else
        migrate_codex_wire_api "$config_file"
        local migrate_rc=$?
        if [ "$migrate_rc" -eq 0 ]; then
            print_success "Updated config.toml to use modern Responses API"
        elif [ "$migrate_rc" -eq 2 ]; then
            print_warning "Could not safely migrate config.toml; the original file was preserved"
        fi
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

# Sanitized, read-only diagnostic summary. It reports state, never credential
# contents, and returns nonzero only for failures that require user action.
diagnose_environment() {
    print_header "AI Docker Environment Diagnostic"
    local failures=0 marker="${HOME}/.cli_tools_installed"
    local state
    state=$(install_status_state "$marker")
    echo "INSTALL_STATUS=$state"
    if [ "$state" = "partial" ]; then
        echo "FAILED_TOOLS=$(install_status_get "$marker" FAILED_TOOLS)"
        failures=1
    elif [ "$state" = "missing" ]; then
        failures=1
    fi

    local tool
    for tool in claude gh codex gemini; do
        if command -v "$tool" >/dev/null 2>&1 && "$tool" --version >/dev/null 2>&1; then
            echo "BINARY_${tool}=ok"
        else
            echo "BINARY_${tool}=missing_or_broken"
            failures=1
        fi
    done

    for tool in claude gh openai codex gemini; do
        if is_configured "$tool"; then
            echo "AUTH_${tool}=configured"
        else
            echo "AUTH_${tool}=not_configured"
        fi
    done

    local port="${AI_ROUTER_PORT:-20128}" port_rc
    if ai_router_port_busy "$port"; then
        echo "ROUTER_PORT=busy"
    else
        port_rc=$?
        if [ "$port_rc" -eq 1 ]; then echo "ROUTER_PORT=free"; else echo "ROUTER_PORT=probe_missing"; failures=1; fi
    fi

    if [ -n "${HTTPS_PROXY:-${HTTP_PROXY:-}}" ]; then echo "PROXY=configured"; else echo "PROXY=not_configured"; fi
    if getent hosts api.anthropic.com >/dev/null 2>&1 && getent hosts api.openai.com >/dev/null 2>&1; then
        echo "DNS=ok"
    else
        echo "DNS=failed"
        failures=1
    fi
    # TLS reachability: a successful DNS+TCP+TLS handshake is what we probe for.
    # We deliberately do NOT use `curl -f`, because --fail turns any HTTP status
    # >= 400 into exit 22 - so an unauthenticated 401/403 or a bare-root 404/421
    # (these APIs serve no content at "/") would be misreported as a TLS/network
    # failure. Instead we treat any real HTTP response as transport success and
    # only count genuine transport errors (DNS/connect/timeout/SSL) as failures.
    tls_probe() {
        local url="$1" code rc
        code=$(curl -sS --connect-timeout 5 --max-time 10 -o /dev/null \
            -w '%{http_code}' "$url" 2>/dev/null)
        rc=$?
        if [ "$rc" -eq 0 ] && [ -n "$code" ] && [ "$code" != "000" ]; then
            printf '%s' "$code"
            return 0
        fi
        return 1
    }
    local anthropic_code openai_code
    if anthropic_code=$(tls_probe https://api.anthropic.com/) \
        && openai_code=$(tls_probe https://api.openai.com/); then
        echo "TLS=ok"
        # Sanitized: HTTP status codes only (never headers/body) so an operator
        # can tell "TLS fine, just unauthenticated" from an unexpected 5xx/429.
        echo "HTTP_STATUS_anthropic=$anthropic_code"
        echo "HTTP_STATUS_openai=$openai_code"
    else
        echo "TLS=failed"
        failures=1
    fi
    if [ -r /etc/ai-docker-version ]; then
        echo "CONTAINER_VERSION=$(tr -cd '0-9.A-Za-z+-' < /etc/ai-docker-version)"
    else
        echo "CONTAINER_VERSION=legacy"
    fi
    return "$failures"
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
        echo "A. Configure All"
        echo "0. Exit"
        echo ""
        echo "Note: 9router / OmniRoute are not configured here - just run"
        echo "'9router' or 'omniroute' in the workspace to install and start one."
        echo ""

        read -rp "Enter your choice (0-5, A): " choice

        case $choice in
            1) configure_claude ;;
            2) configure_github ;;
            3) configure_openai ;;
            4) configure_codex ;;
            5) configure_gemini ;;
            [Aa])
                configure_claude
                configure_github
                configure_openai
                configure_codex
                configure_gemini
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
    --diagnose)
        diagnose_environment
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
    --all)
        configure_claude
        configure_github
        configure_openai
        configure_codex
        configure_gemini
        show_status
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --status, -s     Show configuration status"
        echo "  --diagnose       Run sanitized install/auth/router/network diagnostics"
        echo "  --claude         Configure Claude Code CLI"
        echo "  --github, --gh   Configure GitHub CLI"
        echo "  --openai, --gpt  Configure OpenAI/GPT tools (Python SDK)"
        echo "  --codex          Configure OpenAI Codex CLI"
        echo "  --gemini         Configure Google Gemini"
        echo "  --all            Configure all tools"
        echo "  --help, -h       Show this help message"
        echo ""
        echo "Without options, runs interactive configuration wizard"
        ;;
    *)
        interactive_configure
        ;;
esac