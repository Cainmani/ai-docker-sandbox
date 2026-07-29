#!/bin/bash

# AI Docker CLI Tools Installation Script
# This script installs and configures all necessary CLI tools for AI development
# It runs on first container start and can be used for updates

# Note: We do NOT use "set -e" here because we want to continue installing other tools
# even if one tool fails. The structured marker records the honest result, and required-tool
# failures produce a nonzero exit so startup never reports a broken environment as ready.
# We DO use set -uo pipefail to catch undefined variables and pipe failures.
set -uo pipefail

# Ensure npm is configured to use user-local directory (fixes permission issues)
mkdir -p "${HOME}/.npm-global"
npm config set prefix "${HOME}/.npm-global"
# Include: npm global and local bin paths (Claude native installer uses ~/.local/bin)
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

# Source logging library
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -f "${SCRIPT_DIR}/lib/logging.sh" ]; then
    source "${SCRIPT_DIR}/lib/logging.sh"
elif [ -f "/usr/local/lib/logging.sh" ]; then
    source "/usr/local/lib/logging.sh"
fi

# Safe fallbacks when the optional logging library is unavailable. With set -u,
# color variables must always exist before the print helpers reference them.
RED=${RED:-'\033[0;31m'}
GREEN=${GREEN:-'\033[0;32m'}
YELLOW=${YELLOW:-'\033[1;33m'}
BLUE=${BLUE:-'\033[0;34m'}
NC=${NC:-'\033[0m'}

# Initialize logging (if library available)
if type init_logging >/dev/null 2>&1; then
    LOG_FILE=$(init_logging "INSTALL" "install")
fi

# Installation tracking file
# Use $HOME instead of $USER_NAME since $HOME is set by 'su -' but $USER_NAME is not passed
INSTALL_MARKER="${HOME}/.cli_tools_installed"
TOOLS_VERSION_FILE="${HOME}/.cli_tools_versions"
INSTALL_STATUS_FILE="${HOME}/.cli_install_status"

# Tools that must work for the environment to be considered healthy.
# If any of these remain broken after an install run, the script exits nonzero
# and the structured marker records STATUS=partial.
REQUIRED_TOOLS="claude gh codex"

# Install mode: "install" (first run), "repair" (retry only missing/broken
# tools), or "force" (reinstall everything, non-destructively).
INSTALL_MODE="install"

# Function to update installation status (for UI feedback)
update_install_status() {
    local tool=$1
    local pkg_manager=$2
    echo "${tool}|${pkg_manager}" > "$INSTALL_STATUS_FILE"
}

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    # Also log to file if logging is available
    if [ -n "${LOG_FILE:-}" ] && type log_info >/dev/null 2>&1; then
        log_info "INSTALL" "$1" "$LOG_FILE"
    fi
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    # Also log to file if logging is available
    if [ -n "${LOG_FILE:-}" ] && type log_info >/dev/null 2>&1; then
        log_info "INSTALL" "[SUCCESS] $1" "$LOG_FILE"
    fi
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    # Also log to file if logging is available
    if [ -n "${LOG_FILE:-}" ] && type log_error >/dev/null 2>&1; then
        log_error "INSTALL" "$1" "$LOG_FILE"
    fi
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    # Also log to file if logging is available
    if [ -n "${LOG_FILE:-}" ] && type log_warn >/dev/null 2>&1; then
        log_warn "INSTALL" "$1" "$LOG_FILE"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check whether a tool is actually WORKING (not just present).
# Used by --repair to retry only missing/broken tools and by the structured
# marker to record an honest per-tool result.
tool_healthy() {
    local tool=$1
    case $tool in
        claude)     claude --version >/dev/null 2>&1 ;;
        gh)         command_exists gh ;;
        gemini)     command_exists gemini || pip3 show gemini-cli >/dev/null 2>&1 ;;
        codex)      command_exists codex ;;
        vibe-kanban) npm list -g vibe-kanban >/dev/null 2>&1 ;;
        opencode)   npm list -g opencode-ai >/dev/null 2>&1 ;;
        9router)    npm list -g 9router >/dev/null 2>&1 ;;
        omniroute)  npm list -g omniroute >/dev/null 2>&1 ;;
        openai)     pip3 show openai >/dev/null 2>&1 ;;
        *)          return 1 ;;
    esac
}

# Decide whether a tool needs (re)installation for the current mode:
#   force  -> always install
#   repair -> only install when the tool is missing/broken
#   install-> defer to the per-tool logic below (returns 0)
should_install() {
    local tool=$1
    case "$INSTALL_MODE" in
        force)  return 0 ;;
        repair)
            if tool_healthy "$tool"; then
                print_status "$tool is already working - skipping (repair mode)"
                return 1
            fi
            return 0
            ;;
        *) return 0 ;;
    esac
}

# Function to install npm package with retry logic
# Handles ECONNRESET and other transient network errors that occur with large packages
# See: https://github.com/npm/cli/issues/5166
npm_install_with_retry() {
    local package=$1
    local npm_log_file=$2
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        print_status "Installing $package (attempt $attempt/$max_attempts)..."

        # Capture npm output and log it
        local npm_output
        npm_output=$(npm install -g "$package" 2>&1)
        local npm_exit_code=$?

        # Write to npm log file
        echo "$npm_output" > "$npm_log_file"

        # Log npm output to main log file if logging is available
        if [ -n "${LOG_FILE:-}" ] && type log_info >/dev/null 2>&1; then
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    log_info "INSTALL" "  npm: $line" "$LOG_FILE"
                fi
            done <<< "$npm_output"
        fi

        if [ $npm_exit_code -eq 0 ]; then
            return 0
        fi

        print_warning "Attempt $attempt failed for $package"

        if [ $attempt -lt $max_attempts ]; then
            print_status "Clearing npm cache and retrying in 3 seconds..."
            npm cache clean --force 2>/dev/null || true
            sleep 3
        fi

        ((attempt++))
    done

    print_error "Failed to install $package after $max_attempts attempts"
    cat "$npm_log_file"
    return 1
}

# Function to install pip package with retry logic
pip_install_with_retry() {
    local package=$1
    local max_attempts=3
    local attempt=1
    local extra_args="${2:-}"

    while [ $attempt -le $max_attempts ]; do
        print_status "Installing $package via pip (attempt $attempt/$max_attempts)..."

        if pip3 install $extra_args "$package" --quiet 2>&1; then
            return 0
        fi

        print_warning "Attempt $attempt failed for $package"

        if [ $attempt -lt $max_attempts ]; then
            print_status "Retrying in 3 seconds..."
            sleep 3
        fi

        ((attempt++))
    done

    print_error "Failed to install $package after $max_attempts attempts"
    return 1
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
            claude --version 2>/dev/null | head -n1 || echo "not installed"
            ;;
        gemini)
            gemini --version 2>/dev/null | head -n1 || echo "not installed"
            ;;
        codex)
            codex --version 2>/dev/null | head -n1 || echo "not installed"
            ;;
        vibe-kanban)
            npm list -g vibe-kanban 2>/dev/null | grep 'vibe-kanban' | cut -d'@' -f2 || echo "not installed"
            ;;
        opencode)
            npm list -g opencode-ai 2>/dev/null | grep 'opencode-ai' | cut -d'@' -f2 || echo "not installed"
            ;;
        9router)
            npm list -g 9router 2>/dev/null | grep '9router' | cut -d'@' -f2 || echo "not installed"
            ;;
        omniroute)
            npm list -g omniroute 2>/dev/null | grep 'omniroute' | cut -d'@' -f2 || echo "not installed"
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
    echo "vibe-kanban=$(get_version vibe-kanban)" >> "$TOOLS_VERSION_FILE"
    echo "9router=$(get_version 9router)" >> "$TOOLS_VERSION_FILE"
    echo "omniroute=$(get_version omniroute)" >> "$TOOLS_VERSION_FILE"
    echo "opencode=$(get_version opencode)" >> "$TOOLS_VERSION_FILE"
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

    # Update package lists. Continue when the network is unavailable so already
    # working tools remain usable and the final marker reports the honest state.
    print_status "Updating package lists..."
    if ! sudo apt-get update -qq; then
        print_warning "Could not update apt package lists; apt-based installs may fail"
    fi

    # 1. Install GitHub CLI
    update_install_status "GitHub CLI" "apt"
    if ! should_install gh; then
        : # already working - skipped in repair mode
    elif ! command_exists gh || [ "$INSTALL_MODE" = "force" ]; then
        print_status "Installing GitHub CLI..."
        # Download GPG key to temp file first to avoid curl-pipe-shell risk.
        if curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /tmp/githubcli-keyring.gpg \
            && sudo cp /tmp/githubcli-keyring.gpg /usr/share/keyrings/githubcli-archive-keyring.gpg \
            && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
            && sudo apt-get update -qq \
            && sudo apt-get install gh -y -qq \
            && tool_healthy gh; then
            print_success "GitHub CLI installed successfully"
        else
            print_warning "GitHub CLI installation failed; any existing working installation was preserved"
        fi
        rm -f /tmp/githubcli-keyring.gpg
    else
        print_status "GitHub CLI already installed ($(get_version gh))"
    fi

    # 2. Install/Update Claude Code CLI (using native installer - npm is deprecated)
    # Native installation auto-updates in the background, so we only need to install once
    # See: https://docs.anthropic.com/en/docs/claude-code/getting-started
    update_install_status "Claude Code CLI" "native"

    # Determine Claude installation status:
    # - Check if native install exists at ~/.local/bin/claude (symlink to ~/.local/share/claude/versions/X.Y.Z)
    # - Check if Claude command works (not just exists - catches broken symlinks)
    # - Detect npm installations (user ~/.npm-global OR system /usr/local)
    claude_native_path="${HOME}/.local/bin/claude"
    is_npm_install=false
    needs_install=false

    # Repair mode retries only a missing/broken Claude command. A healthy npm or
    # otherwise non-native installation may be migrated during a normal/force
    # run, but repair must leave it untouched like every other healthy tool.
    if [ "$INSTALL_MODE" = "repair" ] && tool_healthy claude; then
        print_status "claude is already working - skipping (repair mode)"
    # In force mode always reinstall via the native installer. This is NON-
    # destructive: the installer stages the new version under
    # ~/.local/share/claude/versions/<X.Y.Z> and only swaps the launcher
    # symlink once the download succeeds, so a failed download leaves the
    # current working Claude untouched.
    elif [ "$INSTALL_MODE" = "force" ]; then
        needs_install=true
        if [ -x "$claude_native_path" ] && "$claude_native_path" --version >/dev/null 2>&1; then
            print_status "Force mode: reinstalling Claude Code CLI (current: $(get_version claude))"
        fi
    # First, check if native installation exists and works
    elif [ -x "$claude_native_path" ] && "$claude_native_path" --version >/dev/null 2>&1; then
        print_status "Claude Code CLI already installed via native installer ($(get_version claude))"
        print_status "Note: Claude Code auto-updates in the background"
    else
        # Check if any claude command exists
        claude_path=$(which claude 2>/dev/null || true)
        if [ -n "$claude_path" ]; then
            # Check if it actually works
            if claude --version >/dev/null 2>&1; then
                # It works - check if it's npm (user or system-wide)
                if echo "$claude_path" | grep -qE '(/\.npm-global/bin/|^/usr/local/(lib/node_modules|bin)/|/node_modules/.bin/)'; then
                    is_npm_install=true
                    print_status "Detected Claude Code installed via npm at: $claude_path"
                    print_status "Migrating to native installer for auto-update support..."
                    needs_install=true
                else
                    # Check if it's a native installation (at ~/.local/bin or ~/.local/share/claude)
                    if echo "$claude_path" | grep -qE '(/.local/bin/|/.local/share/claude/)'; then
                        print_status "Claude Code CLI already installed via native installer ($(get_version claude))"
                        print_status "Note: Claude Code auto-updates in the background"
                    else
                        # Unknown installation type that works - leave it alone
                        print_status "Claude Code CLI found at: $claude_path ($(get_version claude))"
                    fi
                fi
            else
                # Command exists but doesn't work. Leave it in place until the
                # native installer succeeds; cleanup may remove it afterwards.
                print_warning "Found broken Claude installation at: $claude_path"
                print_status "Will install fresh via native installer..."
                needs_install=true
            fi
        else
            # No claude found at all
            needs_install=true
        fi
    fi

    # Install native version if needed
    if [ "$needs_install" = true ]; then
        print_status "Installing Claude Code CLI via native installer..."
        # Download installer first to avoid curl-pipe-shell risk
        if curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh \
            && bash /tmp/claude-install.sh \
            && [ -x "$claude_native_path" ] \
            && "$claude_native_path" --version >/dev/null 2>&1; then
            # Ensure claude is in PATH for this session
            export PATH="${HOME}/.local/bin:${PATH}"
            print_success "Claude Code CLI installed and validated via native installer"

            # Only after the native replacement is validated may obsolete npm
            # wrappers be removed. A failed download leaves the old CLI intact.
            if [ "$is_npm_install" = true ]; then
                print_status "Removing superseded npm installation..."
                npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
                if [ -f "/usr/local/bin/claude" ]; then
                    sudo rm -f /usr/local/bin/claude 2>/dev/null || true
                fi
                print_success "Migration from npm to native installer complete"
            elif [ -f "/usr/local/bin/claude" ] \
                && ! /usr/local/bin/claude --version >/dev/null 2>&1; then
                sudo rm -f /usr/local/bin/claude 2>/dev/null || true
            fi
        else
            print_warning "Claude Code CLI installation failed validation - continuing with other tools"
        fi
        rm -f /tmp/claude-install.sh
    fi

    # 3. Install Google Gemini CLI (official)
    update_install_status "Google Gemini CLI" "npm"
    if ! should_install gemini; then
        : # already working - skipped in repair mode
    elif npm view @google/gemini-cli version >/dev/null 2>&1; then
        print_status "Installing Google Gemini CLI..."
        print_status "Found @google/gemini-cli in npm registry"
        if npm_install_with_retry "@google/gemini-cli@0.53.0" "/tmp/gemini_install.log"; then
            print_success "Gemini CLI installed successfully"
        else
            # Try community version as fallback
            print_status "Attempting community pip version as fallback..."
            if pip_install_with_retry "gemini-cli" "--user"; then
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
            if pip_install_with_retry "gemini-cli" "--user"; then
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
    if ! pip3 show openai >/dev/null 2>&1 || [ "$INSTALL_MODE" = "force" ]; then
        if pip_install_with_retry "openai==2.44.0" "--break-system-packages"; then
            print_success "OpenAI Python SDK installed"
        else
            print_warning "Failed to install OpenAI Python SDK"
        fi
    else
        print_status "OpenAI SDK already installed"
    fi

    # Install OpenAI Codex CLI (official package)
    # Note: This is a large package (~100MB) that can fail with ECONNRESET on flaky networks
    # The retry logic handles this by clearing cache and retrying
    update_install_status "OpenAI Codex CLI" "npm"
    if ! should_install codex; then
        : # already working - skipped in repair mode
    elif npm view @openai/codex version >/dev/null 2>&1; then
        print_status "Installing OpenAI Codex CLI..."
        if npm_install_with_retry "@openai/codex@0.146.0" "/tmp/codex_install.log"; then
            print_success "OpenAI Codex CLI installed successfully"
        else
            print_warning "OpenAI Codex CLI installation failed - can be installed manually with: npm install -g @openai/codex"
        fi
    else
        print_warning "OpenAI Codex CLI (@openai/codex) not available in npm registry"
        print_status "Note: OpenAI API access available via openai Python package"
    fi

    # NOTE: Removed Shell-GPT, Aider, Continue, Codeium, TabNine, AWS, Azure, Google Cloud, and extra dev tools
    # User requested only: GitHub CLI, Claude Code, Gemini, OpenAI SDK, and Codex

    # 5. Install Vibe Kanban (AI agent orchestration tool)
    update_install_status "Vibe Kanban" "npm"
    if ! should_install vibe-kanban; then
        : # already working - skipped in repair mode
    elif npm_install_with_retry "vibe-kanban@0.1.44" "/tmp/vibe_kanban_install.log"; then
        print_success "Vibe Kanban installed successfully"
        # Create .vibe-kanban directory for data persistence
        mkdir -p "${HOME}/.vibe-kanban"
    else
        print_warning "Vibe Kanban installation failed - can be installed manually with: npm install -g vibe-kanban"
    fi

    # NOTE: The AI routers (9router / OmniRoute) are intentionally NOT installed
    # here. They are opt-in and installed on demand the first time the user runs
    # `9router` or `omniroute` in the container (see ai_router_exec in
    # docker/lib/router_utils.sh), which also enforces "only one at a time" and
    # records the version pin. Keeping them out of first-time setup avoids
    # forcing two large, credential-holding packages on every install.

    # 6. Install OpenCode (open-source multi-provider AI coding agent TUI;
    # authenticate inside the container with: opencode auth login)
    update_install_status "OpenCode CLI" "npm"
    if ! should_install opencode; then
        : # already working - skipped in repair mode
    elif npm_install_with_retry "opencode-ai@1.18.9" "/tmp/opencode_install.log"; then
        print_success "OpenCode installed successfully"
    else
        print_warning "OpenCode installation failed - can be installed manually with: npm install -g opencode-ai"
    fi

    # The pin manifest (~/.npm-pinned-tools) is written by ai_router_install
    # when a router is installed on demand - not here, since routers are opt-in.

    # Save versions to file
    save_versions

    print_success "All CLI tools installation completed!"
}

# Function to create the structured installation marker (prevents infinite loops)
#
# Structured, HONEST format (parsed by entrypoint.sh / the login banner /
# lib/entrypoint_helpers.sh install_status_state):
#   STATUS=ok|partial
#   FAILED_TOOLS=<space-separated names, empty when ok>
#   TIMESTAMP=<date>
#   TOOL_<name>=ok|failed
# plus human-readable [OK]/[ERROR] lines for backward compatibility.
#
# Returns 0 when all REQUIRED_TOOLS work, 1 otherwise (so callers can
# propagate a nonzero exit for a genuinely broken environment).
create_marker_file() {
    local failed_tools="" failed_required=0 tool
    # Routers (9router/omniroute) are intentionally excluded - they are opt-in,
    # installed on demand by the `9router`/`omniroute` commands, so their absence
    # is never a "partial install" and must not trigger --repair reinstalls.
    local all_tools="claude gh gemini codex vibe-kanban opencode openai"

    for tool in $all_tools; do
        if ! tool_healthy "$tool"; then
            failed_tools="${failed_tools:+$failed_tools }$tool"
            case " $REQUIRED_TOOLS " in
                *" $tool "*) failed_required=1 ;;
            esac
        fi
    done

    {
        if [ -z "$failed_tools" ]; then
            echo "STATUS=ok"
        else
            echo "STATUS=partial"
        fi
        echo "FAILED_TOOLS=$failed_tools"
        echo "TIMESTAMP=$(date)"
        echo "Installation completed at: $(date)"
        echo "Tools installed by: $(whoami)"
        echo "Node.js version: $(node --version 2>/dev/null || echo 'not found')"
        echo "npm version: $(npm --version 2>/dev/null || echo 'not found')"
        echo "Python version: $(python3 --version 2>/dev/null || echo 'not found')"
        for tool in $all_tools; do
            if tool_healthy "$tool"; then
                echo "TOOL_${tool}=ok"
                echo "[OK] $tool: installed ($(get_version "$tool" 2>/dev/null || echo 'installed'))"
            else
                echo "TOOL_${tool}=failed"
                echo "[ERROR] $tool: failed or broken"
            fi
        done
    } > "$INSTALL_MARKER"

    if [ -n "$failed_tools" ]; then
        print_warning "Installation is PARTIAL - failed tools: $failed_tools"
        print_warning "Working tools remain available; failed tools are retried on the next container start"
    fi
    print_success "Installation marker file created at: $INSTALL_MARKER"
    return $failed_required
}

# Update function
update_cli_tools() {
    print_status "Checking for updates..."

    # Update apt packages
    sudo apt-get update -qq

    # Update npm global packages
    print_status "Updating npm packages..."
    npm update -g --silent

    # Update pip packages (only currently installed tools)
    print_status "Updating Python packages..."
    pip3 install --user --upgrade openai==2.44.0 --quiet || true

    # Update GitHub CLI
    if command_exists gh; then
        print_status "Updating GitHub CLI..."
        sudo apt-get install --only-upgrade gh -y -qq
    fi

    # Save updated versions
    save_versions

    print_success "All tools updated successfully!"
}

# Note: marker file is created explicitly after install_cli_tools completes.
# We intentionally do NOT use an EXIT trap, because if the script crashes
# before reaching install (e.g. unbound variable), the marker would prevent
# retries on the next container start.

# Function to clean up BROKEN leftovers before a --force reinstall.
#
# NON-DESTRUCTIVE by design: working tools are never uninstalled up front.
# `npm install -g <pkg>@<version>` and the Claude native installer both
# replace an existing installation in place, so a failed download during
# --force leaves the previous working tool available instead of removing it
# first and hoping the reinstall succeeds. Only artifacts that are verifiably
# broken (e.g. a claude wrapper whose --version fails) are removed here.
cleanup_old_installations() {
    print_status "Checking for broken CLI leftovers (working tools are preserved)..."

    # A deprecated npm Claude install is superseded by the native installer;
    # remove it ONLY if the native installation already works, otherwise leave
    # it as the last working Claude until the native install succeeds.
    if [ -x "${HOME}/.local/bin/claude" ] && "${HOME}/.local/bin/claude" --version >/dev/null 2>&1; then
        npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
    fi
    # Remove a system-wide claude wrapper only when it is actually broken.
    if [ -f "/usr/local/bin/claude" ] && ! /usr/local/bin/claude --version >/dev/null 2>&1; then
        print_status "Removing broken system wrapper at /usr/local/bin/claude..."
        sudo rm -f /usr/local/bin/claude 2>/dev/null || true
    fi
    # Remove a broken native launcher symlink (dangling target). A dangling
    # symlink fails -e, so test -L as well or it survives cleanup forever.
    if { [ -e "${HOME}/.local/bin/claude" ] || [ -L "${HOME}/.local/bin/claude" ]; } && ! "${HOME}/.local/bin/claude" --version >/dev/null 2>&1; then
        print_status "Removing broken ~/.local/bin/claude launcher..."
        rm -f "${HOME}/.local/bin/claude" 2>/dev/null || true
    fi
    # PRESERVE ~/.claude directory - conversation history, settings, and auth.

    # Clear npm cache to avoid stale package issues; installs below replace
    # packages in place rather than uninstalling them first.
    npm cache clean --force 2>/dev/null || true

    print_success "Cleanup complete (no working tool was removed)"
}

# Check if this is first run, repair, force, or update request
# Use ${1:-} to avoid "unbound variable" error with set -u when called without arguments
# The marker is NOT deleted before reinstalling: the login banner/entrypoint
# keep reporting the last honest status until the new run rewrites it.
INSTALL_RESULT=0
if [ "${1:-}" == "--update" ] || [ "${1:-}" == "-u" ]; then
    update_cli_tools
elif [ "${1:-}" == "--force" ] || [ "${1:-}" == "-f" ]; then
    INSTALL_MODE="force"
    cleanup_old_installations
    install_cli_tools
    create_marker_file || INSTALL_RESULT=1
elif [ "${1:-}" == "--repair" ] || [ "${1:-}" == "-r" ]; then
    # Retry ONLY missing/broken tools; working tools are left untouched.
    INSTALL_MODE="repair"
    install_cli_tools
    create_marker_file || INSTALL_RESULT=1
elif [ -f "$INSTALL_MARKER" ] && grep -q '^STATUS=partial' "$INSTALL_MARKER" 2>/dev/null; then
    # Previous run was partial: automatically retry the failed tools instead of
    # either reporting "already installed" or reinstalling everything.
    print_status "Previous installation was partial - repairing failed tools..."
    INSTALL_MODE="repair"
    install_cli_tools
    create_marker_file || INSTALL_RESULT=1
elif [ -f "$INSTALL_MARKER" ]; then
    print_status "CLI tools already installed. Use --update to update, --repair to fix broken tools, or --force to reinstall."
    if [ -f "$TOOLS_VERSION_FILE" ]; then
        echo ""
        print_status "Installed versions:"
        grep -v "^#" "$TOOLS_VERSION_FILE"
    fi
    # Legacy (pre-structured) marker: verify required tools once and upgrade
    # the marker to the structured format without reinstalling anything.
    if ! grep -q '^STATUS=' "$INSTALL_MARKER" 2>/dev/null; then
        print_status "Upgrading legacy install marker to structured status format..."
        create_marker_file || INSTALL_RESULT=1
    fi
else
    install_cli_tools
    create_marker_file || INSTALL_RESULT=1
fi

# Set proper permissions (run regardless of success/failure)
if [ -d "${HOME}" ]; then
    sudo chown -R "$(whoami)":"$(whoami)" "${HOME}/" 2>/dev/null || true
fi

# Nonzero when required tools (claude/gh/codex) remain broken so callers
# (entrypoint, wizard diagnostics) see an honest result.
exit $INSTALL_RESULT
