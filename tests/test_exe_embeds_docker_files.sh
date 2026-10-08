#!/usr/bin/env bash
# Every file the Dockerfile COPYs must be embedded in the launcher EXE:
# end users build the image from the EXE's extracted copy, so a missing
# entry in $filesToEmbed breaks every user's image build.
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PASS=0
FAIL=0
pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

embed_list=$(sed -n '/^\$filesToEmbed = @(/,/^)/p' "$ROOT_DIR/scripts/build/build_complete_exe.ps1" \
    | sed -n 's/^[[:space:]]*"\.\.\\\.\.\\docker\\\(.*\)",\{0,1\}[[:space:]]*$/\1/p' | tr '\\' '/' | tr -d '\r')
[ -n "$embed_list" ] && pass "embed list parsed" || fail "embed list parsed"

sources=$(grep -E '^COPY[[:space:]]' "$ROOT_DIR/docker/Dockerfile" | grep -v -- '--from=' \
    | awk '{ for (i = 2; i < NF; i++) print $i }' | tr -d '\r')
[ -n "$sources" ] && pass "Dockerfile COPY sources parsed" || fail "Dockerfile COPY sources parsed"

# The launcher keeps three more lists keyed by the path inside the docker
# folder: the placeholder map, the extraction list and the change-detection hash.
complete="$ROOT_DIR/scripts/AI_Docker_Complete.ps1"
placeholder_keys=$(sed -n "s/^[[:space:]]*'\([^']*\)' = '[A-Z0-9_]*_BASE64_HERE'.*/\1/p" "$complete" | tr -d '\r')
extract_list=$(grep -m1 '^[[:space:]]*\$dockerFiles = @(' "$complete" | grep -o "'[^']*'" | tr -d "'")
hash_list=$(grep -m1 'foreach (\$fileName in @(' "$complete" | grep -o "'[^']*'" | tr -d "'")

in_list() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

while IFS= read -r src; do
    [ -n "$src" ] || continue
    key=$src
    case "$src" in lib/*) ;; *) key=${src##*/} ;; esac
    in_list "$src" "$embed_list" && pass "build embeds $src" || fail "build embeds $src (add to \$filesToEmbed in build_complete_exe.ps1)"
    in_list "$key" "$placeholder_keys" && pass "placeholder for $key" || fail "placeholder for $key (add to \$script:EmbeddedFiles in AI_Docker_Complete.ps1)"
    in_list "$key" "$extract_list" && pass "extracted: $key" || fail "extracted: $key (add to \$dockerFiles in Extract-DockerFiles)"
    in_list "$key" "$hash_list" && pass "change-detected: $key" || fail "change-detected: $key (add to the hash list in Extract-DockerFiles)"
done <<< "$sources"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
