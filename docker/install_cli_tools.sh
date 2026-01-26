#!/bin/bash

# AI Docker CLI Tools Installation Script
# This script installs and configures all necessary CLI tools for AI development
# It runs on first container start and can be used for updates

# Note: We do NOT use "set -e" here because we want to continue installing other tools
# even if one tool fails. The marker file will be created regardless to prevent infinite loops.

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

# Initialize logging (if library available)
if type init_logging >/dev/null 2>&1; then
    LOG_FILE=$(init_logging "INSTALL" "install")
fi

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
    # Also log to file if logging is available
    if [ -n "$LOG_FILE" ] && type log_info >/dev/null 2>&1; then
        log_info "INSTALL" "$1" "$LOG_FILE"
    fi
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    # Also log to file if logging is available
    if [ -n "$LOG_FILE" ] && type log_info >/dev/null 2>&1; then
        log_info "INSTALL" "[SUCCESS] $1" "$LOG_FILE"
    fi
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    # Also log to file if logging is available
    if [ -n "$LOG_FILE" ] && type log_error >/dev/null 2>&1; then
        log_error "INSTALL" "$1" "$LOG_FILE"
    fi
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    # Also log to file if logging is available
    if [ -n "$LOG_FILE" ] && type log_warn >/dev/null 2>&1; then
        log_warn "INSTALL" "$1" "$LOG_FILE"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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
        if [ -n "$LOG_FILE" ] && type log_info >/dev/null 2>&1; then
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

    # 2. Install/Update Claude Code CLI (using native installer - npm is deprecated)
    # Native installation auto-updates in the background, so we only need to install once
    # See: https://docs.anthropic.com/en/docs/claude-code/getting-started
    update_install_status "Claude Code CLI" "native"

    # Determine Claude installation status:
    # - Check if native install exists at ~/.local/bin/claude (symlink to ~/.local/share/claude/versions/X.Y.Z)
    # - Check if Claude command works (not just exists - catches broken symlinks)
    # - Detect npm installations (user ~/.npm-global OR system /usr/local)
    claude_native_path="${HOME}/.local/bin/claude"
    claude_works=false
    is_npm_install=false
    needs_install=false

    # First, check if native installation exists and works
    if [ -x "$claude_native_path" ] && "$claude_native_path" --version >/dev/null 2>&1; then
        claude_works=true
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
                        claude_works=true
                        print_status "Claude Code CLI already installed via native installer ($(get_version claude))"
                        print_status "Note: Claude Code auto-updates in the background"
                    else
                        # Unknown installation type that works - leave it alone
                        claude_works=true
                        print_status "Claude Code CLI found at: $claude_path ($(get_version claude))"
                    fi
                fi
            else
                # Command exists but doesn't work (broken symlink/wrapper)
                print_warning "Found broken Claude installation at: $claude_path"
                print_status "Will install fresh via native installer..."
                needs_install=true
                # Clean up broken system-wide installation if it exists
                if [ -f "/usr/local/bin/claude" ]; then
                    print_status "Removing broken system wrapper at /usr/local/bin/claude..."
                    sudo rm -f /usr/local/bin/claude 2>/dev/null || true
                fi
            fi
        else
            # No claude found at all
            needs_install=true
        fi
    fi

    # Install native version if needed
    if [ "$needs_install" = true ]; then
        print_status "Installing Claude Code CLI via native installer..."
        if curl -fsSL https://claude.ai/install.sh | bash; then
            # Ensure claude is in PATH for this session
            export PATH="${HOME}/.local/bin:${PATH}"
            print_success "Claude Code CLI installed successfully via native installer"

            # If migrating from npm, remove the old npm package to avoid confusion
            if [ "$is_npm_install" = true ]; then
                print_status "Removing old npm installation..."
                npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
                # Also remove any system-wide npm wrapper
                if [ -f "/usr/local/bin/claude" ]; then
                    sudo rm -f /usr/local/bin/claude 2>/dev/null || true
                fi
                print_success "Migration from npm to native installer complete"
            fi
        else
            print_warning "Claude Code CLI installation failed - continuing with other tools"
        fi
    fi

    # 3. Install Google Gemini CLI (official)
    update_install_status "Google Gemini CLI" "npm"
    print_status "Installing Google Gemini CLI..."
    if npm view @google/gemini-cli version >/dev/null 2>&1; then
        print_status "Found @google/gemini-cli in npm registry"
        if npm_install_with_retry "@google/gemini-cli@latest" "/tmp/gemini_install.log"; then
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
    if ! pip3 show openai >/dev/null 2>&1; then
        if pip_install_with_retry "openai" "--break-system-packages"; then
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
    print_status "Installing OpenAI Codex CLI..."
    if npm view @openai/codex version >/dev/null 2>&1; then
        if npm_install_with_retry "@openai/codex@latest" "/tmp/codex_install.log"; then
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
    if npm_install_with_retry "vibe-kanban@latest" "/tmp/vibe_kanban_install.log"; then
        print_success "Vibe Kanban installed successfully"
        # Create .vibe-kanban directory for data persistence
        mkdir -p "${HOME}/.vibe-kanban"
    else
        print_warning "Vibe Kanban installation failed - can be installed manually with: npm install -g vibe-kanban"
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

    # Record which tools succeeded (verify they actually work, not just exist)
    if claude --version >/dev/null 2>&1; then
        echo "[OK] Claude CLI: installed ($(claude --version 2>/dev/null | head -n1))" >> "$INSTALL_MARKER"
    else
        echo "[ERROR] Claude CLI: failed or broken" >> "$INSTALL_MARKER"
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

# Function to clean up old CLI installations before fresh install
# Called during --force to ensure a clean slate
cleanup_old_installations() {
    print_status "Cleaning up old CLI installations..."

    # Clean up Claude installations (preserves ~/.claude config/data for conversation history)
    print_status "Removing old Claude Code installations..."
    # Remove npm global installation (user)
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
    # Remove broken system-wide wrapper (from sudo npm install)
    if [ -f "/usr/local/bin/claude" ]; then
        sudo rm -f /usr/local/bin/claude 2>/dev/null || true
    fi
    # Remove native installer binary versions (e.g. ~/.local/share/claude/versions/X.Y.Z)
    if [ -d "${HOME}/.local/share/claude" ]; then
        print_status "Removing ~/.local/share/claude (native Claude binaries)..."
        rm -rf "${HOME}/.local/share/claude" 2>/dev/null || true
    fi
    # Remove native installer launcher symlink
    if [ -f "${HOME}/.local/bin/claude" ]; then
        print_status "Removing ~/.local/bin/claude launcher..."
        rm -f "${HOME}/.local/bin/claude" 2>/dev/null || true
    fi
    # PRESERVE ~/.claude directory - contains conversation history, settings, and auth
    # Auth may or may not persist between npm/native installs, but we try to keep it
    if [ -d "${HOME}/.claude" ]; then
        print_status "Preserving ~/.claude directory (conversation history, settings, auth)"
    fi

    # Clean up other npm packages that will be reinstalled
    print_status "Removing old npm CLI packages..."
    npm uninstall -g @google/gemini-cli 2>/dev/null || true
    npm uninstall -g @openai/codex 2>/dev/null || true
    npm uninstall -g vibe-kanban 2>/dev/null || true

    # Clear npm cache to avoid stale package issues
    npm cache clean --force 2>/dev/null || true

    print_success "Cleanup complete"
}

# Check if this is first run or update request
if [ "$1" == "--update" ] || [ "$1" == "-u" ]; then
    update_cli_tools
    # Update doesn't recreate marker, so disable the trap
    trap - EXIT
elif [ "$1" == "--force" ] || [ "$1" == "-f" ]; then
    rm -f "$INSTALL_MARKER"
    cleanup_old_installations
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
