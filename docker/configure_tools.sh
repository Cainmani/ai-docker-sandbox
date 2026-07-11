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
    source "$helper"
done

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
            # A deliberate uninstall via the AI Router menu also counts as "nothing to do".
            if [ -f "${AI_ROUTER_OPTOUT_FILE:-$HOME/.router-data/routers-optout}" ]; then
                return 0
            fi
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

# CLI routing env file: sourced by the managed ~/.bashrc block. The router's
# own settings (linked providers, its API key) live in its web dashboard, but
# the container CLIs still have to be TOLD to send requests to the router -
# that is what these exported variables do. Absent file = routing disabled.
CLI_ROUTING_ENV_FILE="${CLI_ROUTING_ENV_FILE:-$HOME/.router-data/cli-routing.env}"

# Enable/disable routing the container CLIs through the local AI router.
configure_cli_routing() {
    local port="${1:-${AI_ROUTER_PORT:-20128}}"
    local base_url="http://localhost:${port}/v1"

    echo ""
    print_status "CLI routing points the container CLIs at the router's endpoint instead"
    print_status "of each provider directly, so requests use your linked subscriptions."
    if [ -f "$CLI_ROUTING_ENV_FILE" ]; then
        print_success "CLI routing is currently ENABLED"
    else
        print_status "CLI routing is currently disabled (CLIs talk to providers directly)."
    fi
    echo ""
    echo "  1. Enable for OpenAI-compatible CLIs (Codex CLI + OpenAI Python SDK)"
    echo "  2. Enable for OpenAI-compatible CLIs AND Claude Code"
    echo "  3. Disable CLI routing"
    echo "  0. Leave unchanged"
    echo ""
    read -rp "Enter your choice: " routing_choice

    case "$routing_choice" in
        1|2) ;;
        3)
            if [ -f "$CLI_ROUTING_ENV_FILE" ]; then
                rm -f "$CLI_ROUTING_ENV_FILE"
                print_success "CLI routing disabled. Open a new shell (or 'source ~/.bashrc') to apply."
                print_status "Variables already exported in THIS shell keep their values until it closes."
                config_log "INFO" "CLI routing: disabled"
            else
                print_status "CLI routing was already disabled."
            fi
            return 0
            ;;
        0|"") print_status "CLI routing unchanged."; return 0 ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac

    echo ""
    echo "  Paste the router's API key - you'll find it in the router web dashboard"
    echo "  (Settings / API keys) at http://localhost:${port}/dashboard"
    read -rsp "  Router API key (input hidden): " router_key
    echo ""
    if [ -z "$router_key" ]; then
        print_error "No key entered - CLI routing not changed."
        return 1
    fi

    local anthropic_base=""
    if [ "$routing_choice" = "2" ]; then
        echo ""
        echo "  Claude Code needs the router's Anthropic-compatible endpoint; check the"
        echo "  router dashboard for the exact URL (Enter accepts http://localhost:${port})."
        read -rp "  Anthropic-compatible base URL [http://localhost:${port}]: " anthropic_base
        anthropic_base="${anthropic_base:-http://localhost:${port}}"
    fi

    mkdir -p "$(dirname "$CLI_ROUTING_ENV_FILE")"
    {
        echo "# Managed by configure-tools (AI Router menu). Sourced by the managed"
        echo "# ~/.bashrc block; routes the container CLIs through the local AI router."
        echo "# Disable via: configure-tools -> AI Router -> CLI routing -> disable."
        printf 'export OPENAI_BASE_URL=%q\n' "$base_url"
        printf 'export OPENAI_API_KEY=%q\n' "$router_key"
        if [ -n "$anthropic_base" ]; then
            printf 'export ANTHROPIC_BASE_URL=%q\n' "$anthropic_base"
            printf 'export ANTHROPIC_AUTH_TOKEN=%q\n' "$router_key"
        fi
    } > "$CLI_ROUTING_ENV_FILE"
    chmod 600 "$CLI_ROUTING_ENV_FILE"

    print_success "CLI routing enabled. Open a new shell (or 'source ~/.bashrc') to apply."
    print_status "The key is stored in $CLI_ROUTING_ENV_FILE (mode 600, persisted router-data volume)."
    if [ -n "$anthropic_base" ]; then
        print_warning "If 'claude' errors after this, the router may not expose an Anthropic-compatible endpoint - rerun and choose option 1 instead."
    fi
    config_log "INFO" "CLI routing: enabled (claude included: $([ -n "$anthropic_base" ] && echo yes || echo no))"
    return 0
}

# Opt-out marker: while present, install_cli_tools.sh does not (re)install the
# routers and does not count them in the install marker, so an uninstall done
# here survives container restarts and --repair runs. It lives on the persisted
# router-data volume, so it also survives rebuilds.
AI_ROUTER_OPTOUT_FILE="${AI_ROUTER_OPTOUT_FILE:-$HOME/.router-data/routers-optout}"

# Reinstall path: choosing a router clears any uninstall opt-out and installs
# the package if missing (at its pinned version when the pin manifest exists).
ensure_router_installed() {
    local name="$1" pin spec
    rm -f "$AI_ROUTER_OPTOUT_FILE"
    if npm list -g "$name" >/dev/null 2>&1; then
        return 0
    fi
    spec="$name"
    if [ -f "$HOME/.npm-pinned-tools" ]; then
        pin=$(grep "^${name}@" "$HOME/.npm-pinned-tools" | head -n1)
        [ -n "$pin" ] && spec="$pin"
    fi
    print_status "$name is not installed - installing $spec (may take a minute)..."
    config_log "INFO" "AI router: installing $spec"
    if npm install -g "$spec" >/dev/null 2>&1; then
        print_success "$name installed"
        return 0
    fi
    print_error "Could not install $name - try manually: npm install -g $spec"
    config_log "ERROR" "AI router: install failed for $spec"
    return 1
}

# Remove the routers entirely and return the CLIs to their normal provider
# endpoints. Dashboard data (linked subscriptions) is kept unless the user
# explicitly chooses to delete it.
uninstall_ai_routers() {
    local port="${1:-${AI_ROUTER_PORT:-20128}}" confirm wipe pkg
    echo ""
    print_status "This stops any running router, uninstalls the 9router and OmniRoute"
    print_status "packages, and disables CLI routing, so claude/codex talk directly to"
    print_status "their providers again. The routers stay uninstalled across container"
    print_status "restarts and rebuilds until you reinstall them from this menu."
    echo ""
    read -rp "Uninstall both routers? [y/N]: " confirm
    case "$confirm" in
        y|Y) ;;
        *) print_status "Uninstall cancelled."; return 0 ;;
    esac

    print_status "Stopping any running router..."
    ai_router_stop_all "$port" >/dev/null 2>&1

    # Direct CLI traffic back at the providers (new shells pick this up).
    rm -f "$CLI_ROUTING_ENV_FILE"

    for pkg in 9router omniroute; do
        if npm list -g "$pkg" >/dev/null 2>&1; then
            if npm uninstall -g "$pkg" >/dev/null 2>&1; then
                print_success "Uninstalled $pkg"
                config_log "INFO" "AI router: uninstalled $pkg"
            else
                print_error "Failed to uninstall $pkg - try manually: npm uninstall -g $pkg"
                config_log "ERROR" "AI router: failed to uninstall $pkg"
            fi
        fi
    done

    mkdir -p "$(dirname "$AI_ROUTER_OPTOUT_FILE")"
    printf 'Routers uninstalled via configure-tools on %s\n' "$(date)" > "$AI_ROUTER_OPTOUT_FILE"

    echo ""
    echo "  The routers' stored data (SQLite DB + linked provider credentials) is"
    echo "  still under ~/.router-data and would be reused on a reinstall."
    read -rp "Also DELETE that stored router data? [y/N]: " wipe
    case "$wipe" in
        y|Y)
            rm -rf "$HOME/.router-data/9router" "$HOME/.router-data/omniroute"
            print_success "Router data deleted."
            config_log "INFO" "AI router: stored router data deleted"
            ;;
        *) print_status "Router data kept." ;;
    esac

    echo ""
    print_success "Routers removed and CLI routing disabled - claude/codex use their"
    print_success "normal provider endpoints in new shells (or after 'source ~/.bashrc')."
    return 0
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

    if [ "$have_9router" = false ] && [ "$have_omniroute" = false ] && [ ! -f "$AI_ROUTER_OPTOUT_FILE" ]; then
        print_error "Neither 9router nor OmniRoute is installed"
        echo ""
        echo "They normally install automatically during setup - try 'update-container-tools',"
        echo "or install manually: npm install -g 9router   (or)   npm install -g omniroute"
        echo ""
        read -rp "Press Enter to continue..." _
        return 1
    fi

    if [ -f "$AI_ROUTER_OPTOUT_FILE" ]; then
        print_status "The routers are currently UNINSTALLED (opted out via this menu);"
        print_status "the CLIs talk directly to their providers. Picking one reinstalls it."
        echo ""
    fi

    print_status "9router and OmniRoute both link multiple AI subscriptions behind one"
    print_status "OpenAI-compatible endpoint. They share port $port, so only one runs at a time."
    echo ""
    echo "  Note: you sign into each AI provider in the router's web dashboard - not here."
    echo ""

    # Report only router processes this installation owns. Stale/recycled PID
    # records do not validate and unrelated processes are never matched.
    local running=""
    if ai_router_owned_pid 9router >/dev/null 2>&1; then running="9router"; fi
    if ai_router_owned_pid omniroute >/dev/null 2>&1; then running="omniroute"; fi
    if [ -n "$running" ]; then
        print_success "Currently running: $running  ->  http://localhost:$port/dashboard"
        echo ""
    fi

    # Installed routers are offered directly; a missing one can be (re)installed
    # when the routers were uninstalled via this menu.
    echo "Which router do you want to run?"
    if [ "$have_9router" = true ];   then echo "  1. 9router";   else echo "  1. 9router (not installed - will be installed)"; fi
    if [ "$have_omniroute" = true ]; then echo "  2. OmniRoute"; else echo "  2. OmniRoute (not installed - will be installed)"; fi
    echo "  3. CLI routing settings only (keep current router state)"
    echo "  4. Uninstall the routers (CLIs talk directly to their providers)"
    echo "  0. Keep current / skip"
    echo ""
    read -rp "Enter your choice: " router_choice

    local tool=""
    case "$router_choice" in
        1) if ensure_router_installed 9router;   then tool="9router";   else read -rp "Press Enter to continue..." _; return 1; fi ;;
        2) if ensure_router_installed omniroute; then tool="omniroute"; else read -rp "Press Enter to continue..." _; return 1; fi ;;
        3) configure_cli_routing "$port"; local routing_rc=$?; read -rp "Press Enter to continue..." _; return "$routing_rc" ;;
        4) uninstall_ai_routers "$port"; local uninstall_rc=$?; read -rp "Press Enter to continue..." _; return "$uninstall_rc" ;;
        0|"") print_status "No change."; read -rp "Press Enter to continue..." _; return 0 ;;
        *) print_error "Invalid choice"; read -rp "Press Enter to continue..." _; return 1 ;;
    esac

    # Stop only owned router processes (plus narrowly anchored pre-PID-wrapper
    # legacy entry points) and require the shared port to be free before launch.
    print_status "Stopping any running router..."
    ai_router_stop_all "$port"
    local stop_rc=$?
    if [ "$stop_rc" -eq 2 ]; then
        print_error "Neither ss nor netstat is available; cannot safely inspect port $port"
        read -rp "Press Enter to continue..." _
        return 1
    elif [ "$stop_rc" -ne 0 ]; then
        print_error "Port $port is still occupied; refusing to start $tool"
        print_status "Inspect the listener with: ss -tlnp"
        read -rp "Press Enter to continue..." _
        return 1
    fi

    print_status "Starting $tool on 0.0.0.0:$port ..."
    config_log "INFO" "AI router: starting $tool on port $port"
    if ! ai_router_start_detached "$tool" "$port" "/tmp/$tool.log"; then
        print_error "Could not start or record ownership for $tool"
        read -rp "Press Enter to continue..." _
        return 1
    fi

    ai_router_wait_port_listen "$port" 30
    local listen_rc=$?
    if [ "$listen_rc" -eq 0 ]; then
        print_success "$tool started."
        config_log "INFO" "AI router: $tool started on port $port"
    elif [ "$listen_rc" -eq 2 ]; then
        ai_router_stop_process "$tool"
        print_error "The port probe disappeared while starting $tool; the owned process was stopped"
        config_log "ERROR" "AI router: no port probe available while starting $tool"
    else
        print_warning "$tool did not report ready within 30s - it may still be starting."
        print_warning "Check /tmp/$tool.log for details."
        config_log "WARN" "AI router: $tool not listening within timeout on port $port"
    fi
    echo ""
    echo "  Open the dashboard from your host browser and link your subscriptions there:"
    echo "    http://localhost:$port/dashboard"
    echo ""

    # Linking subscriptions in the dashboard configures the ROUTER; the CLIs
    # only use it once routing is enabled here too.
    configure_cli_routing "$port"
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

    for tool in claude gh openai codex gemini ai_router; do
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
        echo "  --diagnose       Run sanitized install/auth/router/network diagnostics"
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