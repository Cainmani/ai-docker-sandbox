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

# --- rescue-scan ----------------------------------------------------------------
#
# A rebuild, recreate or uninstall deletes the container's writable layer: /tmp
# and everything in $HOME except the named-volume mounts. rescue-scan lists work
# there that would be lost (git repos with uncommitted, stashed or unpushed work
# or no remote; document/CAD/GIS files outside dependency folders) and --copy
# moves it into the workspace, verified by checksum. Exit: 0 nothing found,
# 3 work found (or, with --copy, 0 once safely copied), 1 copy failed.

MOUNTS_FILE="${AI_DOCKER_MOUNTS_FILE:-/proc/mounts}"
RESCUE_ROOT="${AI_DOCKER_RESCUE_ROOT:-/workspace/_rescued}"
# Folders whose contents are reinstalled, never hand-made work.
RESCUE_SKIP_DIRS="node_modules .venv venv site-packages __pycache__ .cache .npm .npm-global .local .cargo .rustup .gradle"
RESCUE_DOC_EXTS="pdf doc docx xls xlsx xlsm ppt pptx odt ods csv kmz kml gpkg shp dbf geojson tif tiff dwg dxf step stp stl 3mf f3d fcstd iges igs zip 7z md txt"

# Mount targets inside the scan roots (named volumes) survive a rebuild.
rescue_mounts() {
    awk '{ print $2 }' "$MOUNTS_FILE" 2>/dev/null | sed 's/\\040/ /g'
}

# rescue_find <root>: candidate git repos and document files, NUL-separated,
# prefixed "repo:" or "doc:". Never descends into skip dirs, mounts or repos.
rescue_find() {
    local root="$1" name ext
    local -a prune=() docs=()
    [ -d "$root" ] || return 0
    for name in $RESCUE_SKIP_DIRS; do prune+=(-name "$name" -o); done
    while IFS= read -r name; do
        [ -n "$name" ] && [ "$name" != "/" ] && prune+=(-path "$name" -o)
    done < <(rescue_mounts)
    # Hidden top-level folders are application state (certificate stores,
    # tool configs, sockets), and Claude Code's bundled skills are reinstalled.
    prune+=(-path "$root/.*" -o -path "$root/claude-*/bundled-skills" -o -path "$root/pytest-of-*" -o)
    unset 'prune[${#prune[@]}-1]'
    for ext in $RESCUE_DOC_EXTS; do docs+=(-iname "*.$ext" -o); done
    unset 'docs[${#docs[@]}-1]'

    find "$root" -mindepth 1 \( -type d \( "${prune[@]}" \) -prune \) \
        -o \( -name .git -printf 'repo:%h\0' -prune \) \
        -o \( -type f \( "${docs[@]}" \) -printf 'doc:%p\0' \) 2>/dev/null
}

# rescue_repo_reasons <repo>: comma-separated reasons the repo holds work only
# here; empty if it is clean, stash-free and fully pushed.
rescue_repo_reasons() {
    local repo="$1" reasons=() n
    n=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && reasons+=("$n uncommitted change(s)")
    n=$(git -C "$repo" stash list 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && reasons+=("$n stash(es)")
    if [ -z "$(git -C "$repo" remote 2>/dev/null)" ]; then
        reasons+=("no remote")
    else
        n=$(git -C "$repo" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)
        [ "$n" -gt 0 ] && reasons+=("$n unpushed commit(s)")
    fi
    local IFS=','
    echo "${reasons[*]}"
}

# rescue_collect: fills RESCUE_PATHS and RESCUE_LINES.
rescue_collect() {
    RESCUE_PATHS=()
    RESCUE_LINES=()
    local root entry path reasons repo inside group rel
    local -a repos=() docs=() groups=()
    local -A doc_root=() group_count=() group_bytes=()
    # find only learns a folder is a repo when it reaches .git, so gather
    # everything first, then judge documents inside a repo by the repo.
    for root in "$HOME" "$TMP_ROOT"; do
        while IFS= read -r -d '' entry; do
            case "$entry" in
                repo:*) repos+=("${entry#repo:}") ;;
                doc:*) docs+=("${entry#doc:}"); doc_root["${entry#doc:}"]=$root ;;
            esac
        done < <(rescue_find "$root")
    done

    for repo in "${repos[@]}"; do
        reasons=$(rescue_repo_reasons "$repo")
        [ -n "$reasons" ] || continue
        RESCUE_PATHS+=("$repo")
        RESCUE_LINES+=("git repo  $repo  (${reasons//,/, })")
    done
    for path in "${docs[@]}"; do
        inside=0
        for repo in "${repos[@]}"; do
            case "$path" in "$repo"/*) inside=1; break ;; esac
        done
        [ "$inside" -eq 0 ] || continue
        # Group by top-level folder under the scan root, so one batch of
        # files is one line (and one copied folder); loose files stand alone.
        rel=${path#"${doc_root[$path]}"/}
        case "$rel" in
            */*) group="${doc_root[$path]}/${rel%%/*}" ;;
            *) group=$path ;;
        esac
        if [ -z "${group_count[$group]:-}" ]; then
            groups+=("$group")
            group_count[$group]=0
            group_bytes[$group]=0
        fi
        group_count[$group]=$(( ${group_count[$group]} + 1 ))
        group_bytes[$group]=$(( ${group_bytes[$group]} + $(stat -c %s "$path" 2>/dev/null || echo 0) ))
    done
    local -A loose_count=() loose_bytes=()
    for group in "${groups[@]}"; do
        RESCUE_PATHS+=("$group")
        if [ -d "$group" ]; then
            RESCUE_LINES+=("folder    $group  ($(plural "${group_count[$group]}" document), $(human_bytes "${group_bytes[$group]}"))")
        else
            # Loose files directly in a scan root: one summary line per root.
            root=${group%/*}
            loose_count[$root]=$(( ${loose_count[$root]:-0} + 1 ))
            loose_bytes[$root]=$(( ${loose_bytes[$root]:-0} + ${group_bytes[$group]} ))
        fi
    done
    for root in "${!loose_count[@]}"; do
        RESCUE_LINES+=("files     $root/  ($(plural "${loose_count[$root]}" "loose document"), $(human_bytes "${loose_bytes[$root]}"))")
    done
}

# plural <n> <noun>: "1 document", "3 documents".
plural() {
    if [ "$1" -eq 1 ]; then echo "1 $2"; else echo "$1 ${2}s"; fi
}

human_bytes() {
    awk -v b="$1" 'BEGIN { if (b >= 1073741824) printf "%.1f GB", b / 1073741824; else if (b >= 1048576) printf "%.1f MB", b / 1048576; else printf "%d KB", (b + 1023) / 1024 }'
}

# rescue_destination: next free <yyyymmdd>_container_rescue_vX_XX folder.
rescue_destination() {
    local day minor=0 dest
    day=$(date +%Y%m%d)
    while :; do
        dest=$(printf '%s/%s_container_rescue_v1_%02d' "$RESCUE_ROOT" "$day" "$minor")
        [ -e "$dest" ] || { echo "$dest"; return; }
        minor=$((minor + 1))
    done
}

# rescue_copy <dest>: copy each finding to <dest><absolute path>, skipping
# dependency folders, then verify every copied file by checksum.
rescue_copy() {
    local dest="$1" path name
    local -a excludes=() prune=()
    # One skip list drives both the copy and its verification.
    for name in $RESCUE_SKIP_DIRS; do
        excludes+=(--exclude="$name")
        prune+=(-name "$name" -o)
    done
    unset 'prune[${#prune[@]}-1]'
    mkdir -p "$dest" || return 1
    for path in "${RESCUE_PATHS[@]}"; do
        tar -C / "${excludes[@]}" -cf - "${path#/}" 2>/dev/null | tar -C "$dest" -xf - 2>/dev/null || return 1
        ( cd / && find "${path#/}" \( -type d \( "${prune[@]}" \) -prune \) -o -type f -print0 \
            | xargs -0 -r sha256sum ) > "$dest/.verify.$$" 2>/dev/null || return 1
        ( cd "$dest" && sha256sum --quiet -c "$dest/.verify.$$" ) >/dev/null 2>&1 || { rm -f "$dest/.verify.$$"; return 1; }
        rm -f "$dest/.verify.$$"
    done
}

cmd_rescue_scan() {
    rescue_collect
    if [ "${#RESCUE_PATHS[@]}" -eq 0 ]; then
        echo "Nothing found outside the folders a rebuild keeps."
        return 0
    fi
    echo "Found work outside the folders a rebuild keeps (${#RESCUE_LINES[@]} location(s)):"
    echo "A rebuild, recreate or uninstall of the container deletes these:"
    printf '  %s\n' "${RESCUE_LINES[@]}"
    if [ "${1:-}" != "--copy" ]; then
        echo ""
        echo "Copy them into the workspace first with: ai-docker rescue-scan --copy"
        return 3
    fi
    local dest
    dest=$(rescue_destination)
    if rescue_copy "$dest"; then
        echo ""
        echo "Copied and verified in: $dest"
        return 0
    fi
    echo ""
    echo "ERROR: the copy to $dest failed or did not verify. Do not rebuild or uninstall until this is resolved." >&2
    return 1
}

usage() {
    cat <<'EOF'
Usage: ai-docker <command>

Commands:
  status               Tools, updates, disk use and container limits
  status --brief       One-line summary (shown when a shell starts)
  doctor               Network, DNS, TLS and login diagnostics
  rescue-scan          List work a rebuild/uninstall would delete
  rescue-scan --copy   Copy that work into the workspace (verified)
  help                 Show this help
EOF
}

case "${1:-help}" in
    status)
        if [ "${2:-}" = "--brief" ]; then cmd_brief; else cmd_status; fi
        ;;
    doctor)
        exec /usr/local/bin/configure_tools.sh --diagnose
        ;;
    rescue-scan)
        cmd_rescue_scan "${2:-}"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
