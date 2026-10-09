#!/bin/bash
set -uo pipefail
# No credentials, account identifiers or vendor output ever leave this protocol.
# Native status reports login availability, not network/plan entitlement.
echo 'PROTOCOL=1'
for tool in claude codex gh; do
    state=broken
    if timeout 12 "$tool" --version >/dev/null 2>&1; then state=ready; fi
    echo "TOOL_${tool}=$state"
    auth=unable-to-verify
    if [ "$state" = ready ]; then
        case "$tool" in
            claude) timeout 12 claude auth status >/dev/null 2>&1 ;;
            codex) timeout 12 codex login status >/dev/null 2>&1 ;;
            gh) timeout 12 gh auth status >/dev/null 2>&1 ;;
        esac
        rc=$?
        # A failed status could mean missing credentials, offline or unsupported.
        # Do not guess from files or expose the captured status output.
        if [ "$rc" -eq 0 ]; then auth=ready; fi
    fi
    echo "AUTH_${tool}=$auth"
done
for record in update-status; do
    file="${HOME}/.ai-docker/$record"
    for key in RESULT LAST_ATTEMPT LAST_CHECK_OK LAST_UPDATE_OK FAILED_STAGES; do
        value=$(sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -n1)
        # Only small, printable protocol values; no arbitrary local file contents.
        if [[ "$value" =~ ^[a-zA-Z0-9_[:space:]:.+-]{0,100}$ ]]; then printf 'UPDATE_%s=%s\n' "$key" "$value"; fi
    done
done
