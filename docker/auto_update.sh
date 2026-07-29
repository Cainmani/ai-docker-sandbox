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
# We DO use set -uo pipefail to catch undefined variables and pipe failures.
set -uo pipefail

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
    # Safe fallback color definitions - normally exported by logging.sh. With
    # set -u, referencing them unset would crash the whole updater.
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# Migrate old log file if exists
OLD_LOG="${HOME}/.cli_tools_update.log"
if [ -f "$OLD_LOG" ] && [ "$LOG_FILE" != "$OLD_LOG" ]; then
    cat "$OLD_LOG" >> "$LOG_FILE"
    rm "$OLD_LOG"
fi

UPDATE_CHECK_FILE="${HOME}/.last_update_check"
UPDATE_INTERVAL_DAYS=${UPDATE_INTERVAL_DAYS:-7}  # Default: check weekly

# Function to log with timestamp
# Uses the shared logging library if available, otherwise falls back to simple logging
update_log() {
    local msg="$1"
    # Strip ANSI color codes (literal \033[...m sequences) for clean log output
    local clean_msg
    clean_msg=$(printf '%s' "$msg" | sed 's/\\033\[[0-9;]*m//g')
    if [ "$LOGGING_LIBRARY_AVAILABLE" = "1" ]; then
        log_info "UPDATE" "$clean_msg" "$LOG_FILE"
    else
        local sanitized="$clean_msg"
        local user_name
        user_name="$(whoami 2>/dev/null || echo '')"
        if [ -n "$user_name" ]; then
            sanitized="${sanitized//$user_name/<USER>}"
        fi
        # Keep the recovery logger aligned with the shared sanitizer when the
        # library is missing or damaged.
        sanitized="$(echo "$sanitized" | sed -E 's/sk-ant-[a-zA-Z0-9_-]{20,}/<REDACTED_API_KEY>/g; s/sk-proj-[a-zA-Z0-9_-]{20,}/<REDACTED_API_KEY>/g; s/sk-[a-zA-Z0-9]{20,}/<REDACTED_API_KEY>/g; s/github_pat_[a-zA-Z0-9]{22,}/<REDACTED_TOKEN>/g; s/gh[pousr]_[a-zA-Z0-9]{36,}/<REDACTED_TOKEN>/g; s/([Tt]oken|[Ss]ecret|[Pp]assword)[=:][[:space:]]*[^[:space:]]+/\1=<REDACTED>/g; s/AKIA[A-Z0-9]{16}/<REDACTED_AWS_KEY>/g; s/AIza[a-zA-Z0-9_-]{35}/<REDACTED_GCP_KEY>/g; s/Bearer [a-zA-Z0-9_.-]{20,}/Bearer <REDACTED>/g; s/eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*/<REDACTED_JWT>/g; s/-----BEGIN [A-Z ]+ PRIVATE KEY-----/<REDACTED_PRIVATE_KEY>/g')"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $sanitized" >> "$LOG_FILE"
    fi
    # Always echo with colors to terminal
    echo -e "$msg"
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
# Shell-convention return codes:
#   0 = updates available
#   1 = everything up to date
#   2 = the check itself failed (network/registry problem) - callers must NOT
#       treat this as "no updates"
check_updates() {
    local updates_available=1
    local check_failed=0

    update_log "${BLUE}[INFO]${NC} Checking for available updates..."

    # Check ALL global npm packages for updates (dynamic, not hardcoded).
    # npm outdated exits 1 when outdated packages exist, >1 on real errors.
    # Capture before formatting so pipe status cannot obscure npm's result.
    npm_outdated_raw=$(npm outdated -g 2>/dev/null)
    npm_check_rc=$?
    npm_outdated=$(printf '%s\n' "$npm_outdated_raw" | tail -n +2)
    if [ -n "$npm_outdated" ]; then
        update_log "${YELLOW}[UPDATE]${NC} npm packages have updates available:"
        echo "$npm_outdated" | while read -r line; do
            update_log "  - $line"
        done
        updates_available=0
    elif [ "$npm_check_rc" -gt 1 ]; then
        update_log "${RED}[ERROR]${NC} npm update check failed (exit code: $npm_check_rc)"
        check_failed=1
    fi

    # Check ALL user pip packages for updates (dynamic, not hardcoded).
    pip_outdated_raw=$(pip3 list --user --outdated 2>/dev/null)
    pip_check_rc=$?
    pip_outdated=$(printf '%s\n' "$pip_outdated_raw" | tail -n +3)
    if [ "$pip_check_rc" -eq 0 ]; then
        if [ -n "$pip_outdated" ]; then
            update_log "${YELLOW}[UPDATE]${NC} Python packages have updates available:"
            echo "$pip_outdated" | while read -r line; do
                update_log "  - $line"
            done
            updates_available=0
        fi
    else
        update_log "${RED}[ERROR]${NC} pip update check failed"
        check_failed=1
    fi

    # Check apt updates for installed CLI tools (only gh is installed via apt)
    if ! sudo apt-get update -qq; then
        update_log "${RED}[ERROR]${NC} apt update check failed"
        check_failed=1
    fi
    apt_updates=$(apt list --upgradable 2>/dev/null | grep -E "^gh/" || true)
    if [ -n "$apt_updates" ]; then
        update_log "${YELLOW}[UPDATE]${NC} System packages have updates available:"
        echo "$apt_updates" | while read -r line; do
            update_log "  - $line"
        done
        updates_available=0
    fi

    # Updates found trump a partial check failure; a failed check with no
    # updates found must not masquerade as "everything is current".
    if [ "$updates_available" -eq 0 ]; then
        return 0
    elif [ "$check_failed" -eq 1 ]; then
        return 2
    fi
    return 1
}

# Remove orphaned npm staging directories before a global update.
#
# When `npm install/update -g` is interrupted before its final atomic rename
# (container stopped mid-update, killed process, network drop), it leaves the
# package's hidden staging directory behind. npm names these ".<pkg>-<hash>"
# (e.g. ".9router-wciiY0Kj", "@google/.gemini-cli-yRHhsjle"). npm does not clean
# them up, and a single one makes the NEXT `npm update -g` abort immediately
# with EINVALIDPACKAGENAME ("name cannot start with a period") - which blocks
# updates for EVERY tool, not just the interrupted one. Sweeping them first is
# safe: a real package name can never start with a period, so anything matching
# this pattern is guaranteed to be an abandoned staging directory.
#
# Covers both unscoped (node_modules/.pkg-hash) and scoped
# (node_modules/@scope/.pkg-hash) layouts. Legitimate entries such as .bin and
# .package-lock.json have no "-<hash>" suffix and are never matched.
clean_npm_staging_dirs() {
    local nm
    nm=$(npm root -g 2>/dev/null)
    [ -n "$nm" ] && [ -d "$nm" ] || return 0

    local orphans
    orphans=$(find "$nm" -maxdepth 2 -type d -name '.*-*' 2>/dev/null)
    [ -n "$orphans" ] || return 0

    update_log "${YELLOW}[CLEANUP]${NC} Removing leftover staging directories from interrupted installs (these block npm update):"
    while IFS= read -r orphan; do
        [ -n "$orphan" ] || continue
        update_log "  - ${orphan#"$nm"/}"
        rm -rf "$orphan"
    done <<< "$orphans"
}

# Function to apply updates
# Returns 0 when every stage succeeded, 1 when any npm/pip/apt stage failed.
apply_updates() {
    local update_errors=0
    update_log "${BLUE}[INFO]${NC} Applying updates to container CLI tools..."
    update_log ""
    update_log "${YELLOW}NOTE:${NC} This updates tools INSIDE the Docker container only."
    update_log "      To update the AI Docker Manager launcher app, download from:"
    update_log "      https://github.com/Cainmani/ai-docker-sandbox/releases/latest"
    update_log ""

    # Note: Claude Code uses native installer and auto-updates in the background
    # No manual update needed - just log current version for visibility
    if command -v claude >/dev/null 2>&1; then
        claude_version=$(claude --version 2>/dev/null | head -n1 || echo "unknown")
        update_log "Claude Code: $claude_version (auto-updates in background)"
    fi

    # Update ALL global npm packages (dynamic)
    # Note: Claude Code is no longer installed via npm (uses native installer)
    update_log "Updating npm packages..."

    # Clear any abandoned staging directories from a previously interrupted
    # install first - otherwise `npm update -g` aborts on them (EINVALIDPACKAGENAME)
    # before updating anything.
    clean_npm_staging_dirs

    # Snapshot the installed global packages BEFORE updating. "npm update -g"
    # removes a package before reinstalling the new version, so a mid-update
    # failure (network error, peer-dependency conflict, native build failure)
    # can leave a tool uninstalled entirely rather than just out of date.
    # Anything that disappears during the update gets reinstalled below.
    # The sed keeps scoped names intact (e.g. @google/gemini-cli).
    npm_packages_before=$(npm ls -g --depth=0 --parseable 2>/dev/null | tail -n +2 | sed 's|^.*/node_modules/||' || true)

    npm_output=$(npm update -g 2>&1)
    npm_exit_code=$?
    if [ $npm_exit_code -eq 0 ]; then
        echo "$npm_output" | grep -E "added|updated|changed" | while read line; do update_log "  $line"; done
        if ! echo "$npm_output" | grep -qE "added|updated|changed"; then
            update_log "  No npm updates applied"
        fi
    else
        update_log "${RED}[ERROR]${NC} npm update failed (exit code: $npm_exit_code)"
        echo "$npm_output" | while read line; do update_log "  $line"; done
        update_errors=1
    fi

    # Reinstall any global package that the update removed instead of updating
    npm_packages_after=$(npm ls -g --depth=0 --parseable 2>/dev/null | tail -n +2 | sed 's|^.*/node_modules/||' || true)
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        if ! printf '%s\n' "$npm_packages_after" | grep -qxF "$pkg"; then
            update_log "${YELLOW}[WARNING]${NC} $pkg was removed by a failed update - reinstalling..."
            reinstalled=0
            for reinstall_attempt in 1 2 3; do
                reinstall_output=$(npm install -g "$pkg" 2>&1)
                if [ $? -eq 0 ]; then
                    reinstalled=1
                    break
                fi
                update_log "  Reinstall attempt $reinstall_attempt/3 failed for $pkg"
                npm cache clean --force 2>/dev/null || true
                sleep 3
            done
            if [ $reinstalled -eq 1 ]; then
                update_log "${GREEN}[SUCCESS]${NC} Reinstalled $pkg"
            else
                update_log "${RED}[ERROR]${NC} Could not reinstall $pkg - install manually with: npm install -g $pkg"
                echo "$reinstall_output" | tail -n 20 | while read line; do update_log "  $line"; done
                update_errors=1
            fi
        fi
    done <<< "$npm_packages_before"

    # Restore pinned tools that the blanket update moved. The AI routers
    # (9router / OmniRoute) store linked provider credentials, so they change
    # versions only deliberately via a release that bumps the pins in
    # install_cli_tools.sh - which writes this manifest (one name@version per
    # line). Tools not listed there keep updating normally.
    pinned_tools_file="${PINNED_TOOLS_FILE:-$HOME/.npm-pinned-tools}"
    if [ -f "$pinned_tools_file" ]; then
        while IFS= read -r pin; do
            case "$pin" in ''|'#'*) continue ;; esac
            pin_name=${pin%@*}
            pin_version=${pin##*@}
            installed_version=$(npm list -g "$pin_name" 2>/dev/null | grep -o "${pin_name}@[0-9][^ ]*" | head -n1 | cut -d@ -f2)
            # Missing package is handled by the reinstall loop above; only fix drift.
            if [ -n "$installed_version" ] && [ "$installed_version" != "$pin_version" ]; then
                update_log "${YELLOW}[PINNED]${NC} $pin_name moved to $installed_version but is pinned - restoring $pin_version..."
                if pin_output=$(npm install -g "$pin" 2>&1); then
                    update_log "${GREEN}[SUCCESS]${NC} Restored $pin"
                else
                    update_log "${RED}[ERROR]${NC} Could not restore $pin - install manually with: npm install -g $pin"
                    echo "$pin_output" | tail -n 5 | while read -r line; do update_log "  $line"; done
                    update_errors=1
                fi
            fi
        done < "$pinned_tools_file"
    fi

    # Update ALL user pip packages (dynamic)
    update_log "Updating Python packages..."
    outdated_packages=$(pip3 list --user --outdated --format=freeze 2>/dev/null | cut -d= -f1 || true)
    if [ -n "$outdated_packages" ]; then
        pip_output=$(echo "$outdated_packages" | xargs -r pip3 install --user --upgrade 2>&1)
        pip_exit_code=$?
        if [ $pip_exit_code -eq 0 ]; then
            echo "$pip_output" | grep -E "Successfully installed" | while read line; do update_log "  ${GREEN}$line${NC}"; done
        else
            update_log "${RED}[ERROR]${NC} Some pip packages failed to update (exit code: $pip_exit_code)"
            # Log both successes and failures for visibility
            echo "$pip_output" | grep -E "Successfully installed" | while read line; do update_log "  ${GREEN}$line${NC}"; done
            echo "$pip_output" | grep -iE "error|failed|could not" | while read line; do update_log "  ${RED}$line${NC}"; done
            update_errors=1
        fi
    else
        update_log "  All Python packages are up to date"
    fi

    # Update apt packages (only gh is installed via apt in this container)
    update_log "Updating system packages..."
    apt_output=$(sudo apt-get upgrade -y -qq gh 2>&1)
    apt_exit_code=$?
    if [ $apt_exit_code -eq 0 ]; then
        echo "$apt_output" | grep -E "upgraded|newly installed" | while read line; do update_log "  $line"; done
    else
        update_log "${RED}[ERROR]${NC} apt upgrade failed (exit code: $apt_exit_code)"
        echo "$apt_output" | while read line; do update_log "  $line"; done
        update_errors=1
    fi

    # Honest summary: no success banner after a partial failure.
    if [ "$update_errors" -eq 0 ]; then
        update_log "${GREEN}[SUCCESS]${NC} Updates completed successfully"
        return 0
    else
        update_log "${RED}[ERROR]${NC} Updates completed WITH ERRORS - review the messages above"
        return 1
    fi
}

# Function to run update check and apply if needed
run_auto_update() {
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
    # Use whoami instead of USER_NAME since cron doesn't pass USER_NAME
    chown "$(whoami)":"$(whoami)" "$LOG_FILE"

    update_log "=========================================="
    update_log "${BLUE}[INFO]${NC} Starting auto-update check"

    # Check if we should run update based on interval
    if ! should_update && [ "${1:-}" != "--force" ]; then
        last_check_date=$(date -r "$UPDATE_CHECK_FILE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "never")
        update_log "${BLUE}[INFO]${NC} Skipping update check (last check: $last_check_date)"
        update_log "  Next check in $((UPDATE_INTERVAL_DAYS - $(( ($(date +%s) - $(stat -c %Y "$UPDATE_CHECK_FILE")) / 86400 )))) days"
        update_log "  Use --force to check now"
        return 0
    fi

    # Check for updates (0 = available, 1 = up to date, 2 = check failed)
    local run_result=0
    check_updates
    local check_rc=$?
    if [ "$check_rc" -eq 0 ]; then
        apply_updates || run_result=1
    elif [ "$check_rc" -eq 2 ]; then
        update_log "${RED}[ERROR]${NC} Update check failed - cannot determine whether updates exist. Try again later."
        run_result=1
    else
        update_log "${GREEN}[INFO]${NC} All tools are up to date"
    fi

    # Update the check timestamp only on a successful run so a failed check
    # is retried on the next start instead of being snoozed for a week.
    if [ "$run_result" -eq 0 ]; then
        date > "$UPDATE_CHECK_FILE"
        # Use whoami instead of USER_NAME since cron doesn't pass USER_NAME
        chown "$(whoami)":"$(whoami)" "$UPDATE_CHECK_FILE"
    fi

    update_log "${BLUE}[INFO]${NC} Auto-update check completed"
    update_log "=========================================="
    return $run_result
}

# Setup cron job for auto-updates if requested
setup_cron() {
    local cron_schedule=${1:-"0 2 * * 0"}  # Default: Weekly on Sunday at 2 AM

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "auto_update.sh"; then
        update_log "${YELLOW}[WARNING]${NC} Cron job already exists"
        return 1
    fi

    # Add cron job. Source the proxy/CA login profile first: cron runs in a
    # bare environment, so without it the updater loses proxy/CA config on
    # corporate networks (same line entrypoint_helpers.sh installs).
    (crontab -l 2>/dev/null; echo "$cron_schedule . /etc/profile.d/ai-docker-proxy.sh 2>/dev/null; /usr/local/bin/auto_update.sh >/dev/null 2>&1") | crontab -
    update_log "${GREEN}[SUCCESS]${NC} Cron job added: $cron_schedule"
}

# Parse command line arguments
case "${1:-}" in
    --check|-c)
        check_updates
        case $? in
            0) echo "Updates are available. Run with --apply to install them." ;;
            1) echo "No updates available" ;;
            *) echo "Update check FAILED - could not determine update status." >&2; exit 2 ;;
        esac
        ;;
    --apply|-a)
        apply_updates
        ;;
    --force|-f)
        run_auto_update --force
        ;;
    --cron)
        setup_cron "${2:-}"
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