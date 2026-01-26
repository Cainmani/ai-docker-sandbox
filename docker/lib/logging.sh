#!/bin/bash

# Container-side logging library for ai-docker-cli-setup
# Provides consistent logging with sanitization, rotation, and timestamps
#
# Usage:
#   source /usr/local/lib/logging.sh
#   LOG_FILE=$(init_logging "INSTALL" "install")
#   log_info "INSTALL" "Installing Claude Code CLI..." "$LOG_FILE"

# ============================================================================
# Configuration
# ============================================================================

# Log directory - prefer workspace for Windows accessibility, fallback to home
if [ -d "/workspace" ] && [ -w "/workspace" ]; then
    LOG_DIR="/workspace/.ai-docker-cli/logs"
else
    LOG_DIR="${HOME}/.ai-docker-cli/logs"
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Log rotation settings
MAX_LOG_SIZE_MB=${MAX_LOG_SIZE_MB:-10}
MAX_ROTATED_FILES=${MAX_ROTATED_FILES:-3}

# Colors for terminal output (won't appear in log files)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Sanitization Functions
# ============================================================================

# Sanitize sensitive data from log messages BEFORE writing
# This ensures log files are always safe to share publicly
sanitize_message() {
    local msg="$1"

    # Return early if message is empty
    [ -z "$msg" ] && echo "" && return

    # Sanitize Linux home paths (e.g., /home/username/ -> /home/<USER>/)
    msg=$(echo "$msg" | sed -E "s|/home/[a-zA-Z0-9_-]+/|/home/<USER>/|g")

    # Sanitize Windows paths with usernames (e.g., C:\Users\JohnDoe\ -> C:\Users\<USER>\)
    msg=$(echo "$msg" | sed -E "s|C:\\\\Users\\\\[^\\\\]+\\\\|C:\\\\Users\\\\<USER>\\\\|g")
    msg=$(echo "$msg" | sed -E "s|C:/Users/[^/]+/|C:/Users/<USER>/|g")

    # Sanitize API keys (OpenAI sk-... and sk-proj-... patterns)
    msg=$(echo "$msg" | sed -E "s|sk-proj-[a-zA-Z0-9_-]{20,}|<REDACTED_API_KEY>|g")
    msg=$(echo "$msg" | sed -E "s|sk-[a-zA-Z0-9]{20,}|<REDACTED_API_KEY>|g")

    # Sanitize Anthropic API keys
    msg=$(echo "$msg" | sed -E "s|sk-ant-[a-zA-Z0-9_-]{20,}|<REDACTED_API_KEY>|g")

    # Sanitize GitHub tokens (ghp_, gho_, ghu_, ghs_, ghr_)
    msg=$(echo "$msg" | sed -E "s|gh[pousr]_[a-zA-Z0-9]{36,}|<REDACTED_TOKEN>|g")

    # Sanitize generic tokens/secrets (token=xxx, TOKEN: xxx, secret=xxx)
    msg=$(echo "$msg" | sed -E "s|([Tt]oken)[=:][[:space:]]*[a-zA-Z0-9_-]{20,}|\1=<REDACTED>|g")
    msg=$(echo "$msg" | sed -E "s|([Ss]ecret)[=:][[:space:]]*[a-zA-Z0-9_-]{20,}|\1=<REDACTED>|g")
    msg=$(echo "$msg" | sed -E "s|([Pp]assword)[=:][[:space:]]*[^[:space:]]+|\1=<REDACTED>|g")

    # Sanitize AWS keys (access key ID and secret patterns)
    msg=$(echo "$msg" | sed -E "s|AKIA[A-Z0-9]{16}|<REDACTED_AWS_KEY>|g")

    # Sanitize Google Cloud API keys
    msg=$(echo "$msg" | sed -E "s|AIza[a-zA-Z0-9_-]{35}|<REDACTED_GCP_KEY>|g")

    # Sanitize Bearer tokens in Authorization headers
    msg=$(echo "$msg" | sed -E "s|Bearer [a-zA-Z0-9_.-]{20,}|Bearer <REDACTED>|g")

    # Sanitize JWT tokens (base64.base64.base64 pattern)
    msg=$(echo "$msg" | sed -E "s|eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*|<REDACTED_JWT>|g")

    # Sanitize private key markers
    msg=$(echo "$msg" | sed -E "s|-----BEGIN [A-Z ]+ PRIVATE KEY-----|<REDACTED_PRIVATE_KEY>|g")

    echo "$msg"
}

# ============================================================================
# Log Rotation
# ============================================================================

# Rotate log file if it exceeds maximum size
rotate_log() {
    local log_file="$1"
    local max_size_bytes=$((MAX_LOG_SIZE_MB * 1024 * 1024))

    [ ! -f "$log_file" ] && return 0

    local current_size
    current_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)

    if [ "$current_size" -gt "$max_size_bytes" ]; then
        # Rotate existing compressed files
        local i
        for i in $(seq $((MAX_ROTATED_FILES - 1)) -1 1); do
            if [ -f "${log_file}.${i}.gz" ]; then
                mv "${log_file}.${i}.gz" "${log_file}.$((i + 1)).gz"
            fi
        done

        # Compress current log
        if command -v gzip >/dev/null 2>&1; then
            gzip -c "$log_file" > "${log_file}.1.gz"
        else
            # Fallback: just move without compression
            mv "$log_file" "${log_file}.1"
        fi

        # Truncate current log
        > "$log_file"

        # Log the rotation (after truncation, so it's the first entry)
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
        echo "[${timestamp}] [INFO] [LOGGING] Log rotated (exceeded ${MAX_LOG_SIZE_MB}MB)" >> "$log_file"

        # Remove oldest if exceeds max
        if [ -f "${log_file}.$((MAX_ROTATED_FILES + 1)).gz" ]; then
            rm "${log_file}.$((MAX_ROTATED_FILES + 1)).gz"
        fi
        if [ -f "${log_file}.$((MAX_ROTATED_FILES + 1))" ]; then
            rm "${log_file}.$((MAX_ROTATED_FILES + 1))"
        fi
    fi
}

# ============================================================================
# Core Logging Functions
# ============================================================================

# Core logging function - sanitizes and writes to file
# Usage: log_message "COMPONENT" "LEVEL" "message" "log_file"
log_message() {
    local component="${1:-UNKNOWN}"
    local level="${2:-INFO}"
    local message="$3"
    local log_file="${4:-${LOG_DIR}/container.log}"

    # Sanitize message before writing
    local sanitized
    sanitized=$(sanitize_message "$message")

    # Format timestamp to match PowerShell format
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')

    local log_entry="[${timestamp}] [${level}] [${component}] ${sanitized}"

    # Write to log file
    echo "$log_entry" >> "$log_file"

    # Also output to terminal with colors
    case "$level" in
        ERROR)
            echo -e "${RED}${log_entry}${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}${log_entry}${NC}"
            ;;
        DEBUG)
            # Only show debug if DEBUG_LOGGING is set
            if [ "${DEBUG_LOGGING:-0}" = "1" ]; then
                echo -e "${BLUE}${log_entry}${NC}"
            fi
            ;;
        *)
            echo -e "${log_entry}"
            ;;
    esac
}

# Convenience functions
log_info() {
    log_message "$1" "INFO" "$2" "$3"
}

log_warn() {
    log_message "$1" "WARN" "$2" "$3"
}

log_error() {
    log_message "$1" "ERROR" "$2" "$3"
}

log_debug() {
    log_message "$1" "DEBUG" "$2" "$3"
}

# ============================================================================
# Session Initialization
# ============================================================================

# Initialize logging for a script session
# Usage: LOG_FILE=$(init_logging "COMPONENT" "log_name")
# Returns: Path to the log file
init_logging() {
    local component="$1"
    local log_name="${2:-${component,,}}"

    # Sanitize log_name to prevent path traversal (remove /, \, ..)
    log_name=$(echo "$log_name" | sed 's|[/\\]||g' | sed 's|\.\.||g')

    local log_file="${LOG_DIR}/${log_name}.log"

    # Ensure directory exists
    mkdir -p "$LOG_DIR" 2>/dev/null || true

    # Check for rotation before starting session
    rotate_log "$log_file"

    # Log session start with separator
    {
        echo ""
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [INFO] [${component}] ========================================"
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [INFO] [${component}] Session started"
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [INFO] [${component}] Log file: ${log_file}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [INFO] [${component}] ========================================"
    } >> "$log_file"

    # Return log file path
    echo "$log_file"
}

# ============================================================================
# Utility Functions
# ============================================================================

# Run a command and log its output
# Usage: run_logged "COMPONENT" "description" "log_file" command args...
run_logged() {
    local component="$1"
    local description="$2"
    local log_file="$3"
    shift 3

    log_info "$component" "Starting: $description" "$log_file"

    # Run command, capture both stdout and stderr
    local output
    local exit_code
    output=$("$@" 2>&1)
    exit_code=$?

    # Log output line by line (sanitized)
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            log_info "$component" "  $line" "$log_file"
        fi
    done <<< "$output"

    if [ $exit_code -eq 0 ]; then
        log_info "$component" "Completed: $description" "$log_file"
    else
        log_error "$component" "Failed: $description (exit code: $exit_code)" "$log_file"
    fi

    return $exit_code
}

# Get the log directory path (useful for scripts that need to reference it)
get_log_dir() {
    echo "$LOG_DIR"
}

# ============================================================================
# Export for use in subshells
# ============================================================================

export LOG_DIR
export -f sanitize_message log_message log_info log_warn log_error log_debug
export -f init_logging rotate_log run_logged get_log_dir
