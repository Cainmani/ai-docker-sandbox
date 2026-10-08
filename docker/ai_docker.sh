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

# update_lock_held: an updater currently holds the update lock.
update_lock_held() {
    command -v flock >/dev/null 2>&1 || return 1
    [ -e "$STATE_DIR/update.lock" ] || return 1
    ! flock -n "$STATE_DIR/update.lock" true 2>/dev/null
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
            running)
                if update_lock_held; then
                    : # in progress; shown in the summary, not a problem
                else
                    ISSUES+=("last update was interrupted $(age_phrase "${attempt_days:-0}")")
                    HINTS+=("Run it again: update-container-tools --force")
                fi
                ;;
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
    if [ "$(status_value RESULT)" = running ] && update_lock_held; then
        echo "update running"
        return
    fi
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
        elif [ "$(install_status_get "$INSTALL_MARKER" "TOOL_$tool" 2>/dev/null)" = ok ]; then
            # The installer recorded it as working; it no longer runs.
            printf '            %-9s %s\n' "$tool" "NOT WORKING"
            ISSUES+=("$tool is installed but not working")
            HINTS+=("Repair it: install_cli_tools.sh --repair")
        else
            printf '            %-9s %s\n' "$tool" "not installed"
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
# or no remote; any other file outside dependency folders) and --copy
# moves it into the workspace, verified by checksum. Exit: 0 nothing found,
# 3 work found (or, with --copy, 0 once safely copied), 1 copy failed,
# 4 scan incomplete (some location unreadable).

MOUNTS_FILE="${AI_DOCKER_MOUNTS_FILE:-/proc/mounts}"
RESCUE_ROOT="${AI_DOCKER_RESCUE_ROOT:-/workspace/_rescued}"
# Folders whose contents are reinstalled, never hand-made work.
RESCUE_SKIP_DIRS="node_modules .venv venv site-packages __pycache__ .cache .npm .npm-global .local .cargo .rustup .gradle"
RESCUE_DOC_EXTS="png jpg jpeg gif svg ipynb pdf doc docx xls xlsx xlsm ppt pptx odt ods csv kmz kml gpkg shp dbf geojson tif tiff dwg dxf step stp stl 3mf f3d fcstd iges igs zip 7z md txt"

# Mount targets inside the scan roots (named volumes) survive a rebuild.
rescue_mounts() {
    awk '{ print $2 }' "$MOUNTS_FILE" 2>/dev/null | sed 's/\\040/ /g'
}

# rescue_find <root>: candidate git repos and document files, NUL-separated,
# prefixed "repo:" or "doc:". Never descends into skip dirs, mounts or repos.
rescue_find() {
    local root="$1" name
    local -a prune=()
    [ -d "$root" ] || return 0
    for name in $RESCUE_SKIP_DIRS; do prune+=(-name "$name" -o); done
    while IFS= read -r name; do
        [ -n "$name" ] && [ "$name" != "/" ] && prune+=(-path "$name" -o)
    done < <(rescue_mounts)
    # Provably rebuildable or not user work: hidden top-level folders are
    # application state (certificate stores, tool configs, sockets) - except a
    # .git, which marks the root itself as a repo; Claude Code's bundled skills
    # and pytest temp are recreated; ai-docker-rescue is this scanner's own copy.
    prune+=(\( -path "$root/.*" ! -name .git \) -o -path "$root/claude-*/bundled-skills" -o
            -path "$root/pytest-of-*" -o -path "$root/ai-docker-rescue" -o)
    unset 'prune[${#prune[@]}-1]'

    # Any regular file a person or agent left is work unless it is provably
    # rebuildable - file types are no guide (scripts, notebooks, images...).
    # Dotfiles directly in the root (shell rc, install markers, tool config)
    # are app state. Each entry carries its size so callers need no stat.
    # pyvenv.cfg marks a virtualenv, whatever the folder is called.
    # Errors (unreadable folders) go to RESCUE_ERRFILE: a scan that could not
    # see everything must never report "nothing found".
    find "$root" -mindepth 1 \( -type d \( "${prune[@]}" \) -prune \) \
        -o \( -name .git -printf 'repo:%h\0' -prune \) \
        -o \( -name pyvenv.cfg -printf 'venv:%h\0' \) \
        -o \( -type f ! -path "$root/.*" -printf 'doc:%s:%p\0' \) 2>>"${RESCUE_ERRFILE:-/dev/null}"
}

# rescue_repo_docs <repo>: document files in the working tree (relative paths),
# skipping .git and dependency/cache folders.
rescue_repo_docs() {
    local repo="$1" name ext
    local -a prune=(-name .git -o) docs=()
    for name in $RESCUE_SKIP_DIRS; do prune+=(-name "$name" -o); done
    unset 'prune[${#prune[@]}-1]'
    for ext in $RESCUE_DOC_EXTS; do docs+=(-iname "*.$ext" -o); done
    unset 'docs[${#docs[@]}-1]'
    ( cd "$repo" && find . -mindepth 1 \( \( "${prune[@]}" \) -prune \) -o \( -type f \( "${docs[@]}" \) -print \) 2>/dev/null | sed 's|^\./||' )
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
        # Every local branch, not just the checked-out one.
        n=$(git -C "$repo" rev-list --count HEAD --branches --not --remotes 2>/dev/null || echo 0)
        [ "$n" -gt 0 ] && reasons+=("$n unpushed commit(s)")
    fi
    # Deliverables hidden by .gitignore (build output, exports) are not in the
    # remote either. Ask git about document files only: listing every ignored
    # file would walk node_modules and friends.
    n=$(rescue_repo_docs "$repo" | git -C "$repo" check-ignore --stdin 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && reasons+=("$n ignored document(s)")
    local IFS=','
    echo "${reasons[*]}"
}

# rescue_collect: fills RESCUE_PATHS and RESCUE_LINES for $HOME and /tmp.
rescue_collect() {
    rescue_collect_roots "$HOME" "$TMP_ROOT"
}

# rescue_collect_roots <root...>: fills RESCUE_PATHS and RESCUE_LINES.
rescue_collect_roots() {
    RESCUE_PATHS=()
    RESCUE_LINES=()
    RESCUE_UNREADABLE=()
    RESCUE_ERRFILE=$(mktemp)
    local root entry path reasons repo inside group rel venv
    local -a repos=() docs=() groups=() venvs=()
    local -A doc_root=() doc_size=() group_count=() group_bytes=()
    # find only learns a folder is a repo (or virtualenv) when it reaches its
    # .git (or pyvenv.cfg), so gather everything first, then judge files inside
    # a repo by the repo and drop files inside a virtualenv.
    for root in "$@"; do
        while IFS= read -r -d '' entry; do
            case "$entry" in
                repo:*) repos+=("${entry#repo:}") ;;
                venv:*) venvs+=("${entry#venv:}") ;;
                doc:*)
                    entry=${entry#doc:}
                    path=${entry#*:}
                    docs+=("$path"); doc_root[$path]=$root; doc_size[$path]=${entry%%:*}
                    ;;
            esac
        done < <(rescue_find "$root")
    done
    mapfile -t RESCUE_UNREADABLE < <(sed -n -E "s/^find: ['‘](.*)['’]: Permission denied$/\1/p" "$RESCUE_ERRFILE" | sort -u)
    if [ "${#RESCUE_UNREADABLE[@]}" -eq 0 ] && [ -s "$RESCUE_ERRFILE" ]; then
        # Any other find error also makes the scan untrustworthy.
        mapfile -t RESCUE_UNREADABLE < <(sed 's/^find: //' "$RESCUE_ERRFILE" | sort -u)
    fi
    rm -f "$RESCUE_ERRFILE"

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
        for venv in "${venvs[@]}"; do
            case "$path" in "$venv"/*) inside=1; break ;; esac
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
        group_bytes[$group]=$(( ${group_bytes[$group]} + ${doc_size[$path]:-0} ))
    done
    local -A loose_count=() loose_bytes=()
    for group in "${groups[@]}"; do
        RESCUE_PATHS+=("$group")
        if [ -d "$group" ]; then
            RESCUE_LINES+=("folder    $group  ($(plural "${group_count[$group]}" file), $(human_bytes "${group_bytes[$group]}"))")
        else
            # Loose files directly in a scan root: one summary line per root.
            root=${group%/*}
            loose_count[$root]=$(( ${loose_count[$root]:-0} + 1 ))
            loose_bytes[$root]=$(( ${loose_bytes[$root]:-0} + ${group_bytes[$group]} ))
        fi
    done
    for root in "${!loose_count[@]}"; do
        RESCUE_LINES+=("files     $root/  ($(plural "${loose_count[$root]}" "loose file"), $(human_bytes "${loose_bytes[$root]}"))")
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
        if [ -e "$path/.git" ]; then
            rescue_make_standalone "$path" "$dest$path" || return 1
            rescue_verify_repo "$path" "$dest$path" || return 1
        fi
    done
}

# rescue_make_standalone <source repo> <copy>: a worktree's .git is a file that
# points at the original repository, which a rebuild may delete. Rebuild the
# copy as an independent repository from a bundle of every ref.
rescue_make_standalone() {
    local src="$1" copy="$2" bundle head remote
    [ -f "$copy/.git" ] || return 0
    bundle=$(mktemp) || return 1
    git -C "$src" bundle create "$bundle" --all >/dev/null 2>&1 || { rm -f "$bundle"; return 1; }
    rm -f "$copy/.git"
    git -C "$copy" init -q >/dev/null 2>&1 \
        && git -C "$copy" fetch -q --update-head-ok "$bundle" 'refs/*:refs/*' >/dev/null 2>&1 \
        || { rm -f "$bundle"; return 1; }
    rm -f "$bundle"
    for remote in $(git -C "$src" remote 2>/dev/null); do
        git -C "$copy" remote add "$remote" "$(git -C "$src" remote get-url "$remote")" 2>/dev/null || true
    done
    if head=$(git -C "$src" symbolic-ref -q HEAD); then
        git -C "$copy" symbolic-ref HEAD "$head"
    else
        git -C "$copy" update-ref --no-deref HEAD "$(git -C "$src" rev-parse HEAD)"
    fi
    # Rebuild the index from HEAD; the working tree files are already in place.
    git -C "$copy" reset -q >/dev/null 2>&1
}

# rescue_verify_repo <source repo> <copy>: the copy must work on its own and
# match the original's HEAD and tracked changes - checksums alone cannot tell.
# (Untracked files are covered by the checksum step; dependency folders are
# deliberately not copied, so they are left out of this comparison.)
rescue_verify_repo() {
    local src="$1" copy="$2"
    [ "$(git -C "$copy" rev-parse HEAD 2>/dev/null)" = "$(git -C "$src" rev-parse HEAD 2>/dev/null)" ] || return 1
    [ "$(git -C "$copy" status --porcelain --untracked-files=no 2>/dev/null | sort)" \
        = "$(git -C "$src" status --porcelain --untracked-files=no 2>/dev/null | sort)" ] || return 1
}

cmd_rescue_scan() {
    rescue_collect
    if [ "${#RESCUE_UNREADABLE[@]}" -gt 0 ]; then
        # Incomplete: something could not be checked, so nothing can be
        # declared safe and no rescue can be certified.
        echo "The scan is INCOMPLETE - these locations could not be read:"
        printf '  could not be read: %s\n' "${RESCUE_UNREADABLE[@]}"
        if [ "${#RESCUE_PATHS[@]}" -gt 0 ]; then
            echo ""
            echo "Work found in the readable locations:"
            printf '  %s\n' "${RESCUE_LINES[@]}"
        fi
        echo ""
        if [ "${1:-}" = "--copy" ]; then
            echo "ERROR: cannot certify a rescue while locations are unreadable. Do not rebuild or uninstall until this is resolved." >&2
            return 1
        fi
        echo "Fix the permissions (or copy those folders out by hand) before rebuilding."
        return 4
    fi
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

# --- cleanup --------------------------------------------------------------------
#
# Conservative removal of disposable data. Only tool-managed data with reliable
# recreation can be deleted: download caches and old Claude Code versions are
# suggested, older Playwright builds are opt-in. Clones, temporary virtualenvs
# and dependency folders in agent scratch are REPORT ONLY in this release -
# shown with paths and sizes, never deleted by cleanup - because no check can
# prove they hold nothing unique. Every deletion is re-checked for active use.

CLEANUP_AGE_DAYS="${AI_DOCKER_CLEANUP_AGE_DAYS:-3}"

# recently_used <dir>: any file in it modified within CLEANUP_AGE_DAYS.
# Directory timestamps are ignored (deleting a sub-folder bumps them; a new
# file is still caught), and so are .git internals (git status rewrites the index).
recently_used() {
    [ -n "$(find "$1" -name .git -prune -o ! -type d -newermt "-$CLEANUP_AGE_DAYS days" -print -quit 2>/dev/null)" ]
}

# in_use_by_process <path>: a running process uses it - its executable is
# <path> or inside it, or its working directory is inside it.
in_use_by_process() {
    local proc link
    for proc in /proc/[0-9]*; do
        for link in exe cwd; do
            link=$(readlink "$proc/$link" 2>/dev/null) || continue
            link=${link% (deleted)}
            case "$link/" in "$1"/*) return 0 ;; esac
        done
    done
    return 1
}

kb_of() { du -sk "$@" 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'; }
# kb_of_list <newline-separated paths>: total size, safe for spaces in names.
kb_of_list() {
    printf '%s\n' "$1" | sed '/^$/d' | tr '\n' '\0' | du -sck --files0-from=- 2>/dev/null | tail -n1 | cut -f1
}
kb_phrase() { human_bytes $(( $1 * 1024 )); }

# rebuildable_dirs_in <dir>: outermost dependency/cache folders and virtualenvs
# (a pyvenv.cfg marks one, whatever its name) below <dir>, one per line.
rebuildable_dirs_in() {
    local name
    local -a names=()
    for name in $RESCUE_SKIP_DIRS; do names+=(-name "$name" -o); done
    unset 'names[${#names[@]}-1]'
    {
        find "$1" -mindepth 1 -type d \( "${names[@]}" \) -prune -print 2>/dev/null
        find "$1" -mindepth 2 -name pyvenv.cfg -printf '%h\n' 2>/dev/null
    } | sort -u | awk 'NR == 1 || index($0, prev "/") != 1 { print; prev = $0 }'
}

# Groups: parallel arrays. KIND is "cmd" (run CMD), "paths" (delete ITEMS after
# confirmation) or "report" (list ITEMS with sizes; never deleted).
cleanup_add_group() {
    G_LABEL+=("$1"); G_DEFAULT+=("$2"); G_KIND+=("$3"); G_CMD+=("$4"); G_ITEMS+=("$5"); G_KB+=("$6")
}

cleanup_collect() {
    G_LABEL=(); G_DEFAULT=(); G_KIND=(); G_CMD=(); G_ITEMS=(); G_KB=()
    local items dir name current prev builds keep path

    [ -d "$HOME/.npm/_cacache" ] && \
        cleanup_add_group "npm download cache" y cmd "npm cache clean --force" "" "$(kb_of "$HOME/.npm/_cacache")"
    [ -d "$HOME/.cache/pip" ] && \
        cleanup_add_group "pip download cache" y cmd "pip3 cache purge" "" "$(kb_of "$HOME/.cache/pip")"

    # Claude Code: keep the running version and the newest other one.
    dir="$HOME/.local/share/claude/versions"
    if [ -d "$dir" ]; then
        current=$(readlink -f "$(command -v claude 2>/dev/null)" 2>/dev/null || true)
        current=${current#"$dir"/}; current=${current%%/*}
        # The native installer keeps each version as one executable file
        # (older layouts used a folder); accept both.
        prev=$(find "$dir" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -printf '%f\n' | grep -vxF -- "$current" | sort -V | tail -n1)
        items=$(find "$dir" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -printf '%f\n' | grep -vxF -e "$current" -e "${prev:-/}" | sed "s|^|$dir/|")
        [ -n "$items" ] && [ -n "$current" ] && \
            cleanup_add_group "Claude Code versions ($(printf '%s\n' "$items" | wc -l) old; current and fallback kept)" y paths "" "$items" "$(kb_of_list "$items")"
    fi

    # Playwright: keep the newest build of each browser; a project may pin an
    # older one, so older builds are opt-in.
    dir="$HOME/.cache/ms-playwright"
    if [ -d "$dir" ]; then
        items=""
        for name in $(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sed 's/-[0-9]*$//' | sort -u); do
            builds=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -name "$name-[0-9]*" -printf '%f\n' | sort -V)
            keep=$(printf '%s\n' "$builds" | tail -n1)
            items+=$(printf '%s\n' "$builds" | grep -vxF -- "$keep" | sed "s|^|$dir/|")$'\n'
        done
        items=$(printf '%s' "$items" | sed '/^$/d')
        [ -n "$items" ] && cleanup_add_group "Playwright browser builds ($(printf '%s\n' "$items" | wc -l) older)" n paths "" "$items" "$(kb_of_list "$items")"
    fi

    # Rebuildable folders (virtualenvs, node_modules, caches) inside agent
    # scratch folders unused for CLEANUP_AGE_DAYS. The scratch folders
    # themselves, and every other file in them, are never deleted: age alone
    # does not make hand-made work rebuildable.
    items=""
    while IFS= read -r session; do
        [ -n "$session" ] || continue
        recently_used "$session" && continue
        in_use_by_process "$session" && continue
        items+=$(rebuildable_dirs_in "$session")$'\n'
    done < <(find "$TMP_ROOT/claude-$(id -u)" -mindepth 2 -maxdepth 2 -type d ! -name bundled-skills 2>/dev/null)
    items=$(printf '%s' "$items" | sed '/^$/d')
    [ -n "$items" ] && cleanup_add_group "Dependency folders in agent scratch ($(printf '%s\n' "$items" | wc -l), unused ${CLEANUP_AGE_DAYS}+ days)" n report "" "$items" "$(kb_of_list "$items")"

    # Temporary virtualenvs (a pyvenv.cfg marks one), wherever they sit in /tmp.
    items=""
    while IFS= read -r path; do
        path=${path%/pyvenv.cfg}
        recently_used "$path" && continue
        in_use_by_process "$path" && continue
        items+="$path"$'\n'
    done < <(find "$TMP_ROOT" -mindepth 2 -maxdepth 5 -path "$TMP_ROOT/claude-*" -prune -o -name pyvenv.cfg -print 2>/dev/null)
    items=$(printf '%s' "$items" | sed '/^$/d')
    [ -n "$items" ] && cleanup_add_group "Temporary virtualenvs ($(printf '%s\n' "$items" | wc -l))" n report "" "$items" "$(kb_of_list "$items")"

    # Clones in ~/src that are clean, stash-free and fully pushed.
    items=""
    while IFS= read -r path; do
        path=${path%/.git}
        [ -n "$(rescue_repo_reasons "$path")" ] && continue
        recently_used "$path" && continue
        in_use_by_process "$path" && continue
        items+="$path"$'\n'
    done < <(find "$HOME/src" -mindepth 2 -maxdepth 2 -name .git 2>/dev/null)
    items=$(printf '%s' "$items" | sed '/^$/d')
    [ -n "$items" ] && cleanup_add_group "Clones in ~/src with nothing unpushed ($(printf '%s\n' "$items" | wc -l))" n report "" "$items" "$(kb_of_list "$items")"
}

cleanup_preview() {
    local i mark path shown deletable=0 reported=0
    echo "Cleanup - estimated sizes"
    echo ""
    for i in "${!G_LABEL[@]}"; do
        [ "${G_KIND[$i]}" != report ] || continue
        deletable=1
        if [ "${G_DEFAULT[$i]}" = y ]; then mark="[x]"; else mark="[ ]"; fi
        printf '  %s %-58s %s\n' "$mark" "${G_LABEL[$i]}" "$(kb_phrase "${G_KB[$i]}")"
    done
    [ "$deletable" -eq 1 ] || echo "  Nothing that cleanup can delete was found."

    for i in "${!G_LABEL[@]}"; do
        [ "${G_KIND[$i]}" = report ] || continue
        if [ "$reported" -eq 0 ]; then
            echo ""
            echo "Report only - cleanup never deletes these (check them and remove by hand if you are sure):"
            reported=1
        fi
        printf '  %-62s %s\n' "${G_LABEL[$i]}" "$(kb_phrase "${G_KB[$i]}")"
        shown=0
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            shown=$((shown + 1))
            if [ "$shown" -gt 15 ]; then
                echo "      ... and $(( $(printf '%s\n' "${G_ITEMS[$i]}" | sed '/^$/d' | wc -l) - 15 )) more"
                break
            fi
            printf '      %-56s %s\n' "$path" "$(kb_phrase "$(kb_of "$path")")"
        done <<< "${G_ITEMS[$i]}"
    done
    echo ""
    echo "[x] = suggested. Freeing space inside Linux does not shrink the Windows disk file until it is compacted."
}

# Re-check a path right before deleting it; prints why it was skipped.
cleanup_still_safe() {
    local path="$1"
    [ -e "$path" ] || return 1
    if in_use_by_process "$path"; then
        echo "  Skipped $path: in use by a running process"
        return 1
    fi
}

cmd_cleanup() {
    cleanup_collect
    cleanup_preview
    if [ "${1:-}" != "--apply" ]; then
        echo ""
        echo "Nothing was deleted. To choose what to delete, run: ai-docker cleanup --apply"
        return 0
    fi

    local i answer prompt freed_kb=0 path
    echo ""
    for i in "${!G_LABEL[@]}"; do
        [ "${G_KIND[$i]}" != report ] || continue
        if [ "${G_DEFAULT[$i]}" = y ]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
        printf 'Delete %s (%s)? %s ' "${G_LABEL[$i]}" "$(kb_phrase "${G_KB[$i]}")" "$prompt"
        answer=""
        if ! read -r answer; then
            # Closed or interrupted input is never a "yes".
            echo ""
            echo "Input ended - stopping; nothing more will be deleted."
            break
        fi
        echo ""
        answer=${answer:-${G_DEFAULT[$i]}}
        case "$answer" in [Yy]*) ;; *) continue ;; esac

        if [ "${G_KIND[$i]}" = cmd ]; then
            if ${G_CMD[$i]} >/dev/null 2>&1; then
                freed_kb=$((freed_kb + G_KB[i]))
            else
                echo "  Could not clear ${G_LABEL[$i]}"
            fi
            continue
        fi
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            cleanup_still_safe "$path" || continue
            local kb
            kb=$(kb_of "$path")
            rm -rf -- "$path" && freed_kb=$((freed_kb + kb))
        done <<< "${G_ITEMS[$i]}"
    done
    echo "Freed about $(kb_phrase "$freed_kb") inside the container (estimated)."
    echo "To return the space to Windows, the Docker disk file must be compacted (see docs/CLI_TOOLS_GUIDE.md)."
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
  cleanup              Preview disposable data that can be removed
  cleanup --apply      Choose, group by group, what to delete
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
    cleanup)
        cmd_cleanup "${2:-}"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
