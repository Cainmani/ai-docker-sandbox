#!/bin/bash

# Shared entrypoint/config helpers for ai-docker-sandbox.
#
# Sourced by:
#   - docker/entrypoint.sh (container startup)
#   - docker/configure_tools.sh (manual `configure-tools --codex` path)
#   - behavioral tests (tests/test_entrypoint_helpers.sh)
#
# Everything here is failure-safe: a migration that cannot be verified leaves
# the original data exactly where it was, working, and reports the problem
# instead of deleting credentials.

# Logging hook - scripts that source this can override eh_log to route into
# their own logger. Default: plain stderr-ish echo.
if ! type eh_log >/dev/null 2>&1; then
    eh_log() {
        local level="$1" message="$2"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [HELPER] $message"
    }
fi

# ============================================================================
# Failure-safe directory migration (auth/config dirs -> persistent volume)
# ============================================================================

# safe_migrate_dir <source_dir> <volume_dir>
#
# Moves the contents of <source_dir> into <volume_dir> and replaces
# <source_dir> with a symlink to <volume_dir>. The copy goes through a staging
# directory inside the destination volume and is verified (diff -r) BEFORE the
# source is removed. On any failure the source directory is left untouched and
# in use (no symlink is created), so existing credentials keep working.
#
# Returns 0 on success (or nothing to do), 1 on failed migration.
safe_migrate_dir() {
    local src="$1" dest="$2" staging backup link_tmp

    # Already a symlink (migrated on a previous start): just make sure it
    # points at the right place.
    if [ -L "$src" ]; then
        ln -sfn "$dest" "$src"
        return 0
    fi

    mkdir -p "$dest" || return 1

    # No real source directory: nothing to migrate, just link.
    if [ ! -d "$src" ]; then
        mkdir -p "$(dirname "$src")" 2>/dev/null || true
        ln -sfn "$dest" "$src"
        return 0
    fi

    # Stage the copy INSIDE the destination volume so promotion is a same-
    # filesystem operation.
    staging="${dest}.staging.$$"
    backup="${src}.migration-backup.$$"
    link_tmp="${src}.migration-link.$$"
    rm -rf "$staging" "$backup"
    rm -f "$link_tmp"
    if ! mkdir -p "$staging"; then
        eh_log "ERROR" "Migration of $src failed: cannot create staging dir in volume - keeping original directory"
        return 1
    fi

    if ! cp -a "$src"/. "$staging"/ 2>/dev/null; then
        eh_log "ERROR" "Migration of $src failed during copy - keeping original directory untouched"
        rm -rf "$staging"
        return 1
    fi

    # Verify the staged copy matches the source before touching the original.
    if ! diff -r "$src" "$staging" >/dev/null 2>&1; then
        eh_log "ERROR" "Migration of $src failed verification - keeping original directory untouched"
        rm -rf "$staging"
        return 1
    fi

    # Source content is authoritative on conflicts; unrelated existing volume
    # content is retained. Prepare the replacement link before moving the
    # source, then retain the source as rollback data until link promotion.
    if ! cp -a "$staging"/. "$dest"/ 2>/dev/null || ! ln -s "$dest" "$link_tmp"; then
        eh_log "ERROR" "Migration of $src failed during promotion - keeping original directory untouched"
        rm -rf "$staging"
        rm -f "$link_tmp"
        return 1
    fi
    rm -rf "$staging"

    if ! mv "$src" "$backup"; then
        eh_log "ERROR" "Migration of $src failed while preparing the symlink - keeping original directory untouched"
        rm -f "$link_tmp"
        return 1
    fi
    if ! mv "$link_tmp" "$src"; then
        mv "$backup" "$src" 2>/dev/null || true
        rm -f "$link_tmp"
        eh_log "ERROR" "Migration of $src failed while installing the symlink - original directory restored"
        return 1
    fi

    rm -rf "$backup"
    eh_log "INFO" "Migrated $src into $dest"
    return 0
}

# safe_migrate_file <source_file> <volume_file>
#
# Same idea for a single file (e.g. ~/.claude.json): copy, verify with cmp,
# and only then remove the original and create the symlink.
safe_migrate_file() {
    local src="$1" dest="$2"

    if [ -f "$src" ] && [ ! -L "$src" ]; then
        if cp "$src" "${dest}.staging.$$" 2>/dev/null \
            && cmp -s "$src" "${dest}.staging.$$"; then
            mv "${dest}.staging.$$" "$dest"
            rm -f "$src"
            eh_log "INFO" "Migrated $src into $dest"
        else
            rm -f "${dest}.staging.$$"
            eh_log "ERROR" "Migration of $src failed - keeping original file untouched"
            return 1
        fi
    fi
    return 0
}

# ============================================================================
# Codex config migration (deprecated wire_api = "chat" -> "responses")
# ============================================================================

# migrate_codex_wire_api <config.toml>
#
# Idempotent: does nothing when the file is absent or already migrated.
# Backs the file up next to itself before editing and preserves every
# unrelated setting (only the wire_api value changes).
# Returns: 0 = migrated, 1 = nothing to do, 2 = migration failed.
migrate_codex_wire_api() {
    local config_file="$1" backup

    [ -f "$config_file" ] || return 1
    grep -Eq 'wire_api[[:space:]]*=[[:space:]]*"chat"' "$config_file" || return 1

    backup="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    if ! cp "$config_file" "$backup" 2>/dev/null; then
        eh_log "ERROR" "Codex config migration skipped: could not back up $config_file"
        return 2
    fi

    if sed -i 's/wire_api[[:space:]]*=[[:space:]]*"chat"/wire_api = "responses"/g' "$config_file" 2>/dev/null \
        && ! grep -Eq 'wire_api[[:space:]]*=[[:space:]]*"chat"' "$config_file"; then
        eh_log "INFO" "Migrated deprecated wire_api=\"chat\" to \"responses\" in $config_file (backup: $backup)"
        return 0
    fi

    # Sed failed - restore from backup so the file is never left half-edited.
    cp "$backup" "$config_file" 2>/dev/null || true
    eh_log "ERROR" "Codex config migration failed for $config_file - original restored"
    return 2
}

# ============================================================================
# Managed .bashrc block (versioned, atomic replacement)
# ============================================================================

# Bump this whenever the generated router-wrapper block changes; the installer
# below replaces any older version (and known legacy unversioned blocks) with
# the current one without touching user-authored content.
MANAGED_BLOCK_VERSION=2
MANAGED_BLOCK_BEGIN="# >>> ai-docker managed: router-wrappers"
MANAGED_BLOCK_END="# <<< ai-docker managed: router-wrappers <<<"

# managed_block_current_version <bashrc>
# Echoes the version of the installed managed block, or nothing.
managed_block_current_version() {
    local bashrc="$1"
    [ -f "$bashrc" ] || return 1
    sed -n "s/^${MANAGED_BLOCK_BEGIN} v\\([0-9][0-9]*\\) >>>\$/\\1/p" "$bashrc" | head -n1
}

# strip_managed_block <bashrc>
# Removes the marked managed block AND the known legacy (unmarked) router
# wrapper blocks that earlier releases appended:
#   - v0/v1: "# AI router wrappers (9router / OmniRoute): ..." through the
#            final "omniroute() { ... }" definition line.
# User-authored content outside those ranges is preserved byte-for-byte.
strip_managed_block() {
    local bashrc="$1" tmp
    [ -f "$bashrc" ] || return 0
    tmp="${bashrc}.tmp.$$"

    awk -v begin="$MANAGED_BLOCK_BEGIN" -v end="$MANAGED_BLOCK_END" '
        index($0, begin) == 1 { in_managed = 1; next }
        in_managed && index($0, end) == 1 { in_managed = 0; next }
        in_managed { next }
        /^# AI router wrappers \(9router \/ OmniRoute\)/ { in_legacy = 1; next }
        in_legacy && /^omniroute\(\)/ { in_legacy = 0; next }
        in_legacy { next }
        { print }
    ' "$bashrc" > "$tmp" && mv "$tmp" "$bashrc"
}

# install_managed_block <bashrc>
#
# Ensures the CURRENT versioned router-wrapper block is installed exactly
# once. No-op when the current version is already present. Replacement is
# atomic (rewrite to temp file, then mv).
install_managed_block() {
    local bashrc="$1" current

    current=$(managed_block_current_version "$bashrc" 2>/dev/null || true)
    if [ "${current:-0}" = "$MANAGED_BLOCK_VERSION" ]; then
        return 0
    fi

    touch "$bashrc"
    strip_managed_block "$bashrc"

    cat >> "$bashrc" << EOF

${MANAGED_BLOCK_BEGIN} v${MANAGED_BLOCK_VERSION} >>>
EOF
    cat >> "$bashrc" << 'EOF'
# AI router wrappers (9router / OmniRoute): bind the dashboard to 0.0.0.0 so
# it is reachable from the host browser at http://localhost:20128/dashboard
# (port overridable via AI_ROUTER_PORT). DATA_DIR points each router at its
# own persisted data dir. Only one router runs at a time - starting one stops
# the other (owned-PID stop with TERM->KILL escalation, then waits for the
# shared port to actually be released before binding).
# Managed by ai-docker-sandbox - do not edit inside this block; it is
# regenerated on container start.
if [ -f /usr/local/lib/router_utils.sh ]; then
    . /usr/local/lib/router_utils.sh
    9router()   { ai_router_exec 9router   "$@"; }
    omniroute() { ai_router_exec omniroute "$@"; }
fi
EOF
    cat >> "$bashrc" << EOF
${MANAGED_BLOCK_END}
EOF
}

# ============================================================================
# Structured install-status parsing (~/.cli_tools_installed)
# ============================================================================

# install_status_get <marker_file> <key>
# Echoes the value of KEY=VALUE in the structured marker (empty when absent).
install_status_get() {
    local marker="$1" key="$2"
    [ -f "$marker" ] || return 1
    sed -n "s/^${key}=//p" "$marker" | head -n1
}

# install_status_state <marker_file>
# Echoes: "missing" | "legacy" (pre-structured marker) | "ok" | "partial"
install_status_state() {
    local marker="$1" status
    [ -f "$marker" ] || { echo "missing"; return 0; }
    status=$(install_status_get "$marker" "STATUS")
    case "$status" in
        ok)      echo "ok" ;;
        partial) echo "partial" ;;
        *)       echo "legacy" ;;
    esac
}

# ============================================================================
# Scheduled updater setup
# ============================================================================

# setup_auto_update_cron <user>
# Installs the weekly updater entry once. A crontab failure is reported but is
# non-fatal to container startup because interactive updates remain available.
setup_auto_update_cron() {
    local user="$1"

    if crontab -u "$user" -l 2>/dev/null | grep -q "auto_update.sh"; then
        eh_log "INFO" "Auto-update cron job already configured, skipping"
        return 0
    fi

    eh_log "INFO" "Setting up auto-update cron job (weekly on Sunday at 2 AM)..."
    # Source the proxy/CA login profile first: cron runs in a bare environment
    # that inherits neither the compose env nor the user's .bashrc/.profile, so
    # without this the updater loses proxy/CA config on corporate networks.
    if (crontab -u "$user" -l 2>/dev/null; printf '%s\n' "0 2 * * 0 . /etc/profile.d/ai-docker-proxy.sh 2>/dev/null; /usr/local/bin/auto_update.sh >/dev/null 2>&1") \
        | crontab -u "$user" -; then
        eh_log "INFO" "Auto-update cron job configured successfully"
        return 0
    fi

    eh_log "WARN" "Failed to setup auto-update cron job"
    return 1
}

# ensure_cron_daemon_running
# Starts cron only when needed and verifies that it remains alive. Failure is
# returned to the caller so entrypoint policy can keep it non-fatal.
ensure_cron_daemon_running() {
    if pgrep -x cron >/dev/null 2>&1; then
        eh_log "INFO" "cron daemon is running"
        return 0
    fi

    eh_log "INFO" "Starting cron daemon for scheduled auto-updates..."
    if command -v cron >/dev/null 2>&1; then
        cron || true
        sleep "${CRON_START_WAIT_SECONDS:-1}"
    else
        eh_log "WARN" "cron executable is unavailable"
    fi

    if pgrep -x cron >/dev/null 2>&1; then
        eh_log "INFO" "cron daemon is running"
        return 0
    fi

    eh_log "WARN" "cron daemon is NOT running - scheduled auto-updates will not fire. Start it manually with: sudo cron"
    return 1
}

# ============================================================================
# Proxy / custom-CA environment propagation
# ============================================================================
#
# The container-level environment (from docker-compose.yml) carries corporate
# proxy and custom-CA trust settings into PID 1 / entrypoint.sh. But `su - user`
# is a LOGIN shell that resets the environment, and cron jobs (crontab -u) run
# in a bare non-login context - so tools invoked in those contexts
# (install_cli_tools.sh, auto_update.sh, interactive configure-tools) lose
# proxy/CA configuration and fail on corporate networks. We fix this two ways:
#   1. PROXY_CA_ENV_VARS names the vars to whitelist across `su -` (via -w).
#   2. write_proxy_ca_profile persists them into /etc/profile.d so every future
#      login/interactive shell (SSH mobile access, manual `su - user`) re-exports
#      them, and so cron-invoked scripts can source them.

# Space-free, comma-joinable list consumed by `su -w`. Includes upper/lower case
# variants because different tools read different casings.
PROXY_CA_ENV_VARS="HTTP_PROXY,HTTPS_PROXY,NO_PROXY,ALL_PROXY,http_proxy,https_proxy,no_proxy,all_proxy,NODE_EXTRA_CA_CERTS,REQUESTS_CA_BUNDLE,SSL_CERT_FILE,CUSTOM_CA_CERT"

# su_preserving_env <user> <command-string>
# Runs `su - <user> -c <command>` while preserving proxy/CA vars across the
# login-shell environment reset. Falls back to a plain `su -` if this platform's
# su lacks -w (older util-linux), so behavior degrades safely rather than error.
su_preserving_env() {
    local user="$1" cmd="$2"
    if su --help 2>&1 | grep -q -- '--whitelist-environment\|-w,'; then
        su -w "$PROXY_CA_ENV_VARS" - "$user" -c "$cmd"
    else
        eh_log "WARN" "su lacks --whitelist-environment; proxy/CA vars may not reach '$user' subshell"
        su - "$user" -c "$cmd"
    fi
}

# write_proxy_ca_profile <profile_dir>
# Writes the currently-set proxy/CA vars into <profile_dir>/ai-docker-proxy.sh so
# login shells re-export them. Only vars that are actually set are emitted, and
# values are single-quote-escaped. Writing nothing (no vars set) removes any
# stale file. Returns 0 always (best-effort; never fatal to startup).
write_proxy_ca_profile() {
    local profile_dir="$1" target="${1%/}/ai-docker-proxy.sh"
    local var value body="" esc
    for var in $(printf '%s' "$PROXY_CA_ENV_VARS" | tr ',' ' '); do
        eval "value=\${$var:-}"
        [ -n "$value" ] || continue
        # Escape single quotes for safe embedding inside single-quoted string.
        esc=$(printf '%s' "$value" | sed "s/'/'\\\\''/g")
        body="${body}export ${var}='${esc}'"$'\n'
    done

    if [ -z "$body" ]; then
        rm -f "$target" 2>/dev/null || true
        return 0
    fi

    mkdir -p "$profile_dir" 2>/dev/null || { eh_log "WARN" "Could not create $profile_dir for proxy/CA profile"; return 0; }
    {
        printf '%s\n' "# Auto-generated by ai-docker entrypoint. Proxy/custom-CA trust settings"
        printf '%s\n' "# re-exported for login shells (su -, SSH) and sourced by cron scripts."
        printf '%s' "$body"
    } > "$target" 2>/dev/null || { eh_log "WARN" "Could not write $target"; return 0; }
    chmod 0644 "$target" 2>/dev/null || true
    eh_log "INFO" "Wrote proxy/CA login profile to $target"
    return 0
}
