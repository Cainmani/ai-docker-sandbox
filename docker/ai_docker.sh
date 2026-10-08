#!/usr/bin/env bash
# ai-docker: health of the AI Docker container at a glance.
#
#   ai-docker status           tools, updates, disk and container limits
#   ai-docker status --brief   one line for the login banner (no tool is run)
#   ai-docker doctor           network/auth diagnostics (configure-tools --diagnose)
#
# Reads the records other scripts keep (install marker, update status) rather
# than re-deriving them, works offline, and reports sizes and counts only -
# never file names or contents. Exit status: 0 healthy, 1 needs attention,
# 2 usage error.
set -uo pipefail

LIB_DIR="${AI_DOCKER_LIB_DIR:-/usr/local/lib}"
STATE_DIR="${HOME}/.ai-docker"
STATUS_FILE="${STATE_DIR}/update-status"
INSTALL_MARKER="${HOME}/.cli_tools_installed"
VERSION_FILE="${AI_DOCKER_VERSION_FILE:-/etc/ai-docker-version}"
CGROUP_DIR="${AI_DOCKER_CGROUP_DIR:-/sys/fs/cgroup}"
TMP_ROOT="${AI_DOCKER_TMP_DIR:-/tmp}"
DISK_PATH="${AI_DOCKER_DISK_PATH:-/}"
DISK_WARN_GB="${AI_DOCKER_DISK_WARN_GB:-80}"
# Warn when no update check has succeeded for this long (weekly cadence + slack).
STALE_DAYS="${AI_DOCKER_STALE_DAYS:-10}"
TOOLS="claude gh codex gemini opencode"

# shellcheck source=lib/entrypoint_helpers.sh
. "$LIB_DIR/entrypoint_helpers.sh"

status_value() {
    sed -n "s/^$1=//p" "$STATUS_FILE" 2>/dev/null | head -n1
}

# days_since <iso-timestamp>: whole days elapsed, or nothing if unparseable.
days_since() {
    local since
    [ -n "$1" ] || return 1
    since=$(date -d "$1" +%s 2>/dev/null) || return 1
    echo $(( ($(date +%s) - since) / 86400 ))
}

age_phrase() {
    case "$1" in
        0) echo "today" ;;
        1) echo "1 day ago" ;;
        *) echo "$1 days ago" ;;
    esac
}

image_version() {
    if [ -r "$VERSION_FILE" ]; then
        tr -cd '0-9.A-Za-z+-' < "$VERSION_FILE"
    else
        echo "unknown"
    fi
}

disk_used_gb() {
    df -B1 --output=used "$DISK_PATH" 2>/dev/null | tail -n1 | awk '{ printf "%d", $1 / 1073741824 }'
}

# collect_issues: fills ISSUES (short phrases) and HINTS (what to do).
collect_issues() {
    ISSUES=()
    HINTS=()
    local state failed result attempt_days check_days used

    state=$(install_status_state "$INSTALL_MARKER")
    case "$state" in
        partial)
            failed=$(install_status_get "$INSTALL_MARKER" FAILED_TOOLS)
            ISSUES+=("tools failed to install: ${failed:-unknown}")
            HINTS+=("Repair failed tools: install_cli_tools.sh --repair (also retried on every start)")
            ;;
        missing)
            ISSUES+=("tool installation has not completed")
            HINTS+=("Restart the container, or run: install_cli_tools.sh")
            ;;
    esac

    if [ -f "$STATUS_FILE" ]; then
        result=$(status_value RESULT)
        attempt_days=$(days_since "$(status_value LAST_ATTEMPT)" || true)
        check_days=$(days_since "$(status_value LAST_CHECK_OK)" || true)
        case "$result" in
            failed)
                ISSUES+=("last update failed ($(status_value FAILED_STAGES)) $(age_phrase "${attempt_days:-0}")")
                HINTS+=("Retry and review the errors: update-container-tools --force")
                ;;
            check_failed)
                ISSUES+=("last update check failed $(age_phrase "${attempt_days:-0}")")
                HINTS+=("Check network access with: ai-docker doctor")
                ;;
        esac
        if [ -z "$check_days" ]; then
            [ "$result" = check_failed ] || ISSUES+=("no successful update check recorded")
        elif [ "$check_days" -ge "$STALE_DAYS" ]; then
            ISSUES+=("no successful update check for $check_days days")
            HINTS+=("Run updates now: update-container-tools --force")
        fi
    fi

    used=$(disk_used_gb)
    if [ -n "$used" ] && [ "$used" -ge "$DISK_WARN_GB" ]; then
        ISSUES+=("Docker disk $used GB used")
        HINTS+=("See the disk breakdown in: ai-docker status")
    fi
}

update_summary() {
    local check_days
    [ -f "$STATUS_FILE" ] || { echo "update check pending"; return; }
    check_days=$(days_since "$(status_value LAST_CHECK_OK)" || true)
    if [ -n "$check_days" ]; then
        echo "updates checked $(age_phrase "$check_days")"
    else
        echo "no successful update check yet"
    fi
}

cmd_brief() {
    collect_issues
    if [ "${#ISSUES[@]}" -eq 0 ]; then
        echo "AI Docker $(image_version) - tools OK - $(update_summary) - Docker disk $(disk_used_gb) GB used"
        return 0
    fi
    local joined
    joined=$(printf '%s; ' "${ISSUES[@]}")
    echo "AI Docker $(image_version): ATTENTION - ${joined%; } - run: ai-docker status"
    return 1
}

memory_limit() {
    local raw
    raw=$(cat "$CGROUP_DIR/memory.max" 2>/dev/null || echo max)
    if [ "$raw" = max ] || ! [ "$raw" -gt 0 ] 2>/dev/null; then
        echo "memory limit none"
    else
        awk -v b="$raw" 'BEGIN { printf "memory limit %.1f GB", b / 1073741824 }'
    fi
}

cpu_limit() {
    local quota period
    read -r quota period < "$CGROUP_DIR/cpu.max" 2>/dev/null || { echo "CPU limit none"; return; }
    if [ "$quota" = max ] || [ -z "${period:-}" ]; then
        echo "CPU limit none"
    else
        awk -v q="$quota" -v p="$period" 'BEGIN { c = q / p; if (c == int(c)) printf "%d CPUs", c; else printf "%.1f CPUs", c }'
    fi
}

# size_of <du-args...>: total size estimate, bounded so status never hangs on a
# huge tree. Prints e.g. "3.2 GB", "3.2 GB (partial)" when some folders were
# unreadable, or "over time limit".
size_of() {
    local out rc kb suffix=""
    out=$(timeout 20 du -sck "$@" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 124 ]; then
        echo "over time limit"
        return
    fi
    # du exits 1 when it could not read part of the tree; the total still counts the rest.
    [ "$rc" -eq 0 ] || suffix=" (partial)"
    kb=$(printf '%s\n' "$out" | tail -n1 | cut -f1)
    awk -v k="${kb:-0}" -v s="$suffix" 'BEGIN { if (k >= 1048576) printf "%.1f GB%s", k / 1048576, s; else printf "%d MB%s", k / 1024, s }'
}

cmd_status() {
    local state tool version disk_size disk_used
    collect_issues

    echo "AI Docker status"
    echo ""
    echo "Container   image $(image_version) - $(memory_limit) - $(cpu_limit)"
    echo "            (limits are set by the launcher's resource profile; changing them requires recreating the container)"
    echo ""

    state=$(install_status_state "$INSTALL_MARKER")
    echo "Tools       install status: $state"
    for tool in $TOOLS; do
        if command -v "$tool" >/dev/null 2>&1 \
            && version=$(timeout 15 "$tool" --version 2>/dev/null | head -n1) && [ -n "$version" ]; then
            printf '            %-9s %s\n' "$tool" "$version"
        else
            printf '            %-9s %s\n' "$tool" "not working"
        fi
    done
    echo ""

    if [ -f "$STATUS_FILE" ]; then
        echo "Updates     last result: $(status_value RESULT)"
        echo "            last attempt: $(status_value LAST_ATTEMPT)"
        echo "            last successful check: $(status_value LAST_CHECK_OK)"
        echo "            last successful update: $(status_value LAST_UPDATE_OK)"
        echo "            failed stages: $(status_value FAILED_STAGES)"
    else
        echo "Updates     no update has run yet (one starts in the background after container start)"
    fi
    echo ""

    disk_used=$(disk_used_gb)
    disk_size=$(df -B1 --output=size "$DISK_PATH" 2>/dev/null | tail -n1 | awk '{ printf "%d", $1 / 1073741824 }')
    echo "Disk        Docker disk: ${disk_used} GB used of ${disk_size} GB"
    echo "            (estimates; freeing space inside Linux does not shrink the Windows disk file until it is compacted)"
    printf '            %-22s %s\n' "Claude scratch dirs" "$(size_of "$TMP_ROOT/claude-$(id -u)")"
    printf '            %-22s %s\n' "other temp files" "$(size_of --exclude="claude-$(id -u)" "$TMP_ROOT")"
    printf '            %-22s %s\n' "package caches" "$(size_of "$HOME/.npm" "$HOME/.cache")"
    printf '            %-22s %s\n' 'home src folder' "$(size_of "$HOME/src")"
    echo ""

    if [ "${#ISSUES[@]}" -eq 0 ]; then
        echo "Everything looks healthy."
    else
        echo "Needs attention:"
        printf '  - %s\n' "${ISSUES[@]}"
        if [ "${#HINTS[@]}" -gt 0 ]; then
            echo ""
            echo "What to do:"
            printf '  - %s\n' "${HINTS[@]}"
        fi
    fi
    echo ""
    echo "Network, DNS and login checks: ai-docker doctor"
    [ "${#ISSUES[@]}" -eq 0 ]
}

usage() {
    cat <<'EOF'
Usage: ai-docker <command>

Commands:
  status           Tools, updates, disk use and container limits
  status --brief   One-line summary (shown when a shell starts)
  doctor           Network, DNS, TLS and login diagnostics
  help             Show this help
EOF
}

case "${1:-help}" in
    status)
        if [ "${2:-}" = "--brief" ]; then cmd_brief; else cmd_status; fi
        ;;
    doctor)
        exec /usr/local/bin/configure_tools.sh --diagnose
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
