#!/bin/bash

# Auto-update script for CLI tools inside the Docker container
# This script checks for updates and installs them automatically
# Can be run via cron or manually
#
# IMPORTANT: This script updates CLI tools INSIDE the container only.
# It does NOT update the AI Docker Manager launcher app on Windows.
# To update the launcher app, download the latest release from GitHub.

# Note: We do NOT use "set -e" because we want to continue updating other tools
# even if one tool fails to update.

# Ensure npm is configured to use user-local directory (fixes permission issues)
mkdir -p "${HOME}/.npm-global"
npm config set prefix "${HOME}/.npm-global"
# Include: npm global and local bin paths (Claude native installer uses ~/.local/bin)
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

# Source logging library
if [ -f "/usr/local/lib/logging.sh" ]; then
    source "/usr/local/lib/logging.sh"
    LOG_FILE=$(init_logging "UPDATE" "update")
    LOGGING_LIBRARY_AVAILABLE=1
else
    # Fallback to old location if library not available
    LOG_FILE="${HOME}/.cli_tools_update.log"
    LOGGING_LIBRARY_AVAILABLE=0
fi

# Migrate old log file if exists
OLD_LOG="${HOME}/.cli_tools_update.log"
if [ -f "$OLD_LOG" ] && [ "$LOG_FILE" != "$OLD_LOG" ]; then
    cat "$OLD_LOG" >> "$LOG_FILE"
    rm "$OLD_LOG"
fi

UPDATE_CHECK_FILE="${HOME}/.last_update_check"
UPDATE_INTERVAL_DAYS=${UPDATE_INTERVAL_DAYS:-7}  # Default: check weekly

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log with timestamp
# Uses the shared logging library if available, otherwise falls back to simple logging
log_message() {
    local msg="$1"
    if [ "$LOGGING_LIBRARY_AVAILABLE" = "1" ]; then
        # Use the shared logging library
        log_info "UPDATE" "$msg" "$LOG_FILE"
    else
        # Fallback to simple logging
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
        echo -e "$msg"
    fi
}

# Function to check if update is needed
should_update() {
    if [ ! -f "$UPDATE_CHECK_FILE" ]; then
        return 0  # First run, should update
    fi

    last_update=$(stat -c %Y "$UPDATE_CHECK_FILE" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    days_since_update=$(( (current_time - last_update) / 86400 ))

    if [ $days_since_update -ge $UPDATE_INTERVAL_DAYS ]; then
        return 0  # Time to update
    else
        return 1  # Too soon
    fi
}

# Function to check for available updates
check_updates() {
    local updates_available=0

    log_message "${BLUE}[INFO]${NC} Checking for available updates..."

    # Check ALL global npm packages for updates (dynamic, not hardcoded)
    npm_outdated=$(npm outdated -g 2>/dev/null | tail -n +2 || true)
    if [ ! -z "$npm_outdated" ]; then
        log_message "${YELLOW}[UPDATE]${NC} npm packages have updates available:"
        echo "$npm_outdated" | while read line; do
            log_message "  - $line"
        done
        updates_available=1
    fi

    # Check ALL user pip packages for updates (dynamic, not hardcoded)
    pip_outdated=$(pip3 list --user --outdated 2>/dev/null | tail -n +3 || true)
    if [ ! -z "$pip_outdated" ]; then
        log_message "${YELLOW}[UPDATE]${NC} Python packages have updates available:"
        echo "$pip_outdated" | while read line; do
            log_message "  - $line"
        done
        updates_available=1
    fi

    # Check apt updates for known CLI tools
    sudo apt-get update -qq
    apt_updates=$(apt list --upgradable 2>/dev/null | grep -E "gh|azure-cli|google-cloud-sdk|bat|ripgrep|fd-find|fzf|httpie|jq" || true)
    if [ ! -z "$apt_updates" ]; then
        log_message "${YELLOW}[UPDATE]${NC} System packages have updates available:"
        echo "$apt_updates" | while read line; do
            log_message "  - $line"
        done
        updates_available=1
    fi

    return $updates_available
}

# Function to apply updates
apply_updates() {
    log_message "${BLUE}[INFO]${NC} Applying updates to container CLI tools..."
    log_message ""
    log_message "${YELLOW}NOTE:${NC} This updates tools INSIDE the Docker container only."
    log_message "      To update the AI Docker Manager launcher app, download from:"
    log_message "      https://github.com/Cainmani/ai-docker-cli-setup/releases/latest"
    log_message ""

    # Note: Claude Code uses native installer and auto-updates in the background
    # No manual update needed - just log current version for visibility
    if command -v claude >/dev/null 2>&1; then
        claude_version=$(claude --version 2>/dev/null | head -n1 || echo "unknown")
        log_message "Claude Code: $claude_version (auto-updates in background)"
    fi

    # Update ALL global npm packages (dynamic)
    # Note: Claude Code is no longer installed via npm (uses native installer)
    log_message "Updating npm packages..."
    npm_output=$(npm update -g 2>&1)
    npm_exit_code=$?
    if [ $npm_exit_code -eq 0 ]; then
        echo "$npm_output" | grep -E "added|updated|changed" | while read line; do log_message "  $line"; done
        if ! echo "$npm_output" | grep -qE "added|updated|changed"; then
            log_message "  No npm updates applied"
        fi
    else
        log_message "${RED}[ERROR]${NC} npm update failed (exit code: $npm_exit_code)"
        echo "$npm_output" | while read line; do log_message "  $line"; done
    fi

    # Update ALL user pip packages (dynamic)
    log_message "Updating Python packages..."
    outdated_packages=$(pip3 list --user --outdated --format=freeze 2>/dev/null | cut -d= -f1 || true)
    if [ ! -z "$outdated_packages" ]; then
        pip_output=$(echo "$outdated_packages" | xargs -r pip3 install --user --upgrade 2>&1)
        pip_exit_code=$?
        if [ $pip_exit_code -eq 0 ]; then
            echo "$pip_output" | grep -E "Successfully installed" | while read line; do log_message "  ${GREEN}$line${NC}"; done
        else
            log_message "${RED}[ERROR]${NC} Some pip packages failed to update (exit code: $pip_exit_code)"
            # Log both successes and failures for visibility
            echo "$pip_output" | grep -E "Successfully installed" | while read line; do log_message "  ${GREEN}$line${NC}"; done
            echo "$pip_output" | grep -iE "error|failed|could not" | while read line; do log_message "  ${RED}$line${NC}"; done
        fi
    else
        log_message "  All Python packages are up to date"
    fi

    # Update apt packages (keeping specific list for safety)
    log_message "Updating system packages..."
    apt_output=$(sudo apt-get upgrade -y -qq gh azure-cli google-cloud-sdk bat ripgrep fd-find fzf httpie jq 2>&1)
    apt_exit_code=$?
    if [ $apt_exit_code -eq 0 ]; then
        echo "$apt_output" | grep -E "upgraded|newly installed" | while read line; do log_message "  $line"; done
    else
        log_message "${RED}[ERROR]${NC} apt upgrade failed (exit code: $apt_exit_code)"
        echo "$apt_output" | while read line; do log_message "  $line"; done
    fi

    # Update AWS CLI if installed
    if command -v aws >/dev/null 2>&1; then
        log_message "Updating AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" --silent
        unzip -q -o /tmp/awscliv2.zip -d /tmp/
        sudo /tmp/aws/install --update 2>&1 | grep -E "updated|installed" | \
            while read line; do log_message "  $line"; done
        rm -rf /tmp/awscliv2.zip /tmp/aws/
    fi

    # Update Codeium if installed
    if command -v codeium >/dev/null 2>&1; then
        log_message "Updating Codeium..."
        current_version=$(codeium --version 2>/dev/null || echo "unknown")
        curl -Ls https://github.com/Exafunction/codeium/releases/latest/download/codeium_linux_x64.tar.gz | \
            sudo tar -xz -C /usr/local/bin/ 2>/dev/null
        new_version=$(codeium --version 2>/dev/null || echo "unknown")
        if [ "$current_version" != "$new_version" ]; then
            log_message "  Codeium updated from $current_version to $new_version"
        fi
    fi

    log_message "${GREEN}[SUCCESS]${NC} Updates completed successfully"
}

# Function to run update check and apply if needed
run_auto_update() {
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
    # Use whoami instead of USER_NAME since cron doesn't pass USER_NAME
    chown $(whoami):$(whoami) "$LOG_FILE"

    log_message "=========================================="
    log_message "${BLUE}[INFO]${NC} Starting auto-update check"

    # Check if we should run update based on interval
    if ! should_update && [ "$1" != "--force" ]; then
        last_check_date=$(date -r "$UPDATE_CHECK_FILE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "never")
        log_message "${BLUE}[INFO]${NC} Skipping update check (last check: $last_check_date)"
        log_message "  Next check in $((UPDATE_INTERVAL_DAYS - $(( ($(date +%s) - $(stat -c %Y "$UPDATE_CHECK_FILE")) / 86400 )))) days"
        log_message "  Use --force to check now"
        return 0
    fi

    # Check for updates
    if check_updates || [ "$1" == "--force" ]; then
        apply_updates
    else
        log_message "${GREEN}[INFO]${NC} All tools are up to date"
    fi

    # Update the check timestamp
    date > "$UPDATE_CHECK_FILE"
    # Use whoami instead of USER_NAME since cron doesn't pass USER_NAME
    chown $(whoami):$(whoami) "$UPDATE_CHECK_FILE"

    log_message "${BLUE}[INFO]${NC} Auto-update check completed"
    log_message "=========================================="
}

# Setup cron job for auto-updates if requested
setup_cron() {
    local cron_schedule=${1:-"0 2 * * 0"}  # Default: Weekly on Sunday at 2 AM

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "auto_update.sh"; then
        log_message "${YELLOW}[WARNING]${NC} Cron job already exists"
        return 1
    fi

    # Add cron job
    (crontab -l 2>/dev/null; echo "$cron_schedule /usr/local/bin/auto_update.sh >/dev/null 2>&1") | crontab -
    log_message "${GREEN}[SUCCESS]${NC} Cron job added: $cron_schedule"
}

# Parse command line arguments
case "$1" in
    --check|-c)
        check_updates
        if [ $? -eq 0 ]; then
            echo "No updates available"
        else
            echo "Updates are available. Run with --apply to install them."
        fi
        ;;
    --apply|-a)
        apply_updates
        ;;
    --force|-f)
        run_auto_update --force
        ;;
    --cron)
        setup_cron "$2"
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Update CLI tools inside the Docker container."
        echo ""
        echo "NOTE: This updates container tools only (Claude CLI, Codex, gh, etc.)."
        echo "      It does NOT update the AI Docker Manager launcher app."
        echo "      To update the launcher, download from GitHub releases."
        echo ""
        echo "Options:"
        echo "  --check, -c     Check for available updates"
        echo "  --apply, -a     Apply available updates"
        echo "  --force, -f     Force update check regardless of interval"
        echo "  --cron [SCHEDULE]  Setup cron job for auto-updates"
        echo "  --help, -h      Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  UPDATE_INTERVAL_DAYS  Days between update checks (default: 7)"
        ;;
    *)
        run_auto_update
        ;;
esac