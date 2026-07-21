#!/usr/bin/env bash
set -u

export CLAUDE_CODE_DISABLE_FILE_SEARCH_TOOL=1

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=../docker/lib/entrypoint_helpers.sh
source "$ROOT_DIR/docker/lib/entrypoint_helpers.sh"

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_true() { local label=$1; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
assert_false() { local label=$1; shift; if "$@" >/dev/null 2>&1; then fail "$label"; else pass "$label"; fi; }

src="$TMP_DIR/source"
dest="$TMP_DIR/volume/auth"
mkdir -p "$src" "$dest"
printf 'new-token\n' > "$src/token"
printf 'source-only\n' > "$src/source-only"
printf 'old-token\n' > "$dest/token"
printf 'keep-me\n' > "$dest/unrelated"
assert_true "migrates a source directory" safe_migrate_dir "$src" "$dest"
assert_true "replaces source with destination symlink" test "$(readlink "$src")" = "$dest"
assert_true "source wins conflicting destination content" grep -Fxq new-token "$dest/token"
assert_true "retains unrelated destination content" grep -Fxq keep-me "$dest/unrelated"

# Force the final symlink promotion to fail. The production helper must restore
# the moved source directory and preserve its credential data.
rollback_src="$TMP_DIR/rollback-source"
rollback_dest="$TMP_DIR/rollback-volume/auth"
mkdir -p "$rollback_src" "$rollback_dest" "$TMP_DIR/fake-bin"
printf 'credential\n' > "$rollback_src/auth.json"
real_mv=$(command -v mv)
cat > "$TMP_DIR/fake-bin/mv" <<SCRIPT
#!/usr/bin/env bash
if [ "\$1" = "${rollback_src}.migration-link.\$PPID" ] && [ "\$2" = "$rollback_src" ]; then
    exit 1
fi
exec "$real_mv" "\$@"
SCRIPT
chmod +x "$TMP_DIR/fake-bin/mv"
# The helper uses its own shell PID, while the fake mv sees that PID as PPID.
assert_false "reports failed symlink promotion" env PATH="$TMP_DIR/fake-bin:$PATH" bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; safe_migrate_dir '$rollback_src' '$rollback_dest'"
assert_true "restores source directory after promotion failure" test -d "$rollback_src"
assert_false "does not leave a broken source symlink" test -L "$rollback_src"
assert_true "preserves source credential after rollback" grep -Fxq credential "$rollback_src/auth.json"

config="$TMP_DIR/config.toml"
printf 'model = "example"\nwire_api = "chat"\nkeep = true\n' > "$config"
assert_true "migrates deprecated Codex wire API" migrate_codex_wire_api "$config"
assert_true "writes Responses wire API" grep -Fxq 'wire_api = "responses"' "$config"
assert_true "preserves unrelated Codex settings" grep -Fxq 'keep = true' "$config"
assert_false "Codex migration is idempotent" migrate_codex_wire_api "$config"

bashrc="$TMP_DIR/bashrc"
printf '# user content\nexport CUSTOM=1\n' > "$bashrc"
assert_true "installs managed router block" install_managed_block "$bashrc"
assert_true "preserves user bashrc content" grep -Fxq 'export CUSTOM=1' "$bashrc"
assert_true "records current managed block version" test "$(managed_block_current_version "$bashrc")" = "$MANAGED_BLOCK_VERSION"
assert_true "managed block reinstall is idempotent" install_managed_block "$bashrc"
block_count=$(grep -c '^# >>> ai-docker managed: router-wrappers' "$bashrc")
assert_true "managed block appears once" test "$block_count" -eq 1

# Exercise production cron helpers with fake crontab/cron/pgrep commands.
cron_bin="$TMP_DIR/cron-bin"
cron_state="$TMP_DIR/crontab"
cron_running="$TMP_DIR/cron-running"
mkdir -p "$cron_bin"
cat > "$cron_bin/crontab" <<'SCRIPT'
#!/usr/bin/env bash
state=${TEST_CRONTAB_STATE:?}
if [ "$3" = "-l" ]; then
    [ -f "$state" ] && cat "$state"
    exit 0
fi
if [ "$3" = "-" ]; then
    cat > "$state"
    exit "${TEST_CRONTAB_INSTALL_EXIT:-0}"
fi
exit 2
SCRIPT
cat > "$cron_bin/pgrep" <<'SCRIPT'
#!/usr/bin/env bash
[ -f "${TEST_CRON_RUNNING:?}" ]
SCRIPT
cat > "$cron_bin/cron" <<'SCRIPT'
#!/usr/bin/env bash
touch "${TEST_CRON_RUNNING:?}"
SCRIPT
chmod +x "$cron_bin/crontab" "$cron_bin/pgrep" "$cron_bin/cron"

cron_env=(env PATH="$cron_bin:$PATH" TEST_CRONTAB_STATE="$cron_state" TEST_CRON_RUNNING="$cron_running" CRON_START_WAIT_SECONDS=0)
assert_true "installs weekly auto-update cron entry" "${cron_env[@]}" bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; setup_auto_update_cron testuser"
assert_true "writes expected weekly cron schedule" grep -Fxq '0 2 * * 0 . /etc/profile.d/ai-docker-proxy.sh 2>/dev/null; /usr/local/bin/auto_update.sh >/dev/null 2>&1' "$cron_state"
assert_true "cron entry sources proxy/CA login profile" grep -q '/etc/profile.d/ai-docker-proxy.sh' "$cron_state"
cron_before=$(cksum < "$cron_state")
assert_true "cron registration is idempotent" "${cron_env[@]}" bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; setup_auto_update_cron testuser"
cron_after=$(cksum < "$cron_state")
assert_true "idempotent cron setup leaves entry unchanged" test "$cron_before" = "$cron_after"
assert_true "starts and verifies cron daemon" "${cron_env[@]}" bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; ensure_cron_daemon_running"
assert_true "cron daemon start records running state" test -f "$cron_running"
rm -f "$cron_running"
assert_false "reports cron daemon that fails to stay running" env PATH="$cron_bin:$PATH" TEST_CRONTAB_STATE="$cron_state" TEST_CRON_RUNNING="$cron_running" CRON_START_WAIT_SECONDS=0 bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; cron() { return 1; }; export -f cron; ensure_cron_daemon_running"
assert_false "reports failed cron registration" env PATH="$cron_bin:$PATH" TEST_CRONTAB_STATE="$TMP_DIR/failing-crontab" TEST_CRONTAB_INSTALL_EXIT=1 bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; setup_auto_update_cron testuser"

# ---------------------------------------------------------------------------
# Proxy / custom-CA environment propagation
# ---------------------------------------------------------------------------
profile_dir="$TMP_DIR/profile.d"
profile_file="$profile_dir/ai-docker-proxy.sh"

# Only the vars that are actually set get written, and they round-trip through
# sourcing the generated profile.
rm -rf "$profile_dir"
assert_true "writes proxy/CA profile when vars are set" \
    env HTTP_PROXY="http://proxy.example:3128" NO_PROXY="localhost,127.0.0.1" \
        NODE_EXTRA_CA_CERTS="/usr/local/share/ca-certificates/ai-docker-custom-ca.crt" \
        CODEX_CA_CERTIFICATE="/etc/ssl/certs/ca-certificates.crt" \
    bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; write_proxy_ca_profile '$profile_dir'"
assert_true "generated profile exists" test -f "$profile_file"
assert_true "profile exports HTTP_PROXY value" bash -c ". '$profile_file'; [ \"\$HTTP_PROXY\" = 'http://proxy.example:3128' ]"
assert_true "profile exports NO_PROXY value" bash -c ". '$profile_file'; [ \"\$NO_PROXY\" = 'localhost,127.0.0.1' ]"
assert_true "profile exports CA bundle value" bash -c ". '$profile_file'; [ \"\$NODE_EXTRA_CA_CERTS\" = '/usr/local/share/ca-certificates/ai-docker-custom-ca.crt' ]"
assert_true "profile exports Codex CA bundle value" bash -c ". '$profile_file'; [ \"\$CODEX_CA_CERTIFICATE\" = '/etc/ssl/certs/ca-certificates.crt' ]"
assert_false "profile omits unset vars" grep -q 'HTTPS_PROXY' "$profile_file"

# Values containing single quotes are escaped safely.
rm -rf "$profile_dir"
assert_true "handles values with single quotes" \
    env HTTP_PROXY="http://it's-a-proxy:3128" \
    bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; write_proxy_ca_profile '$profile_dir'"
assert_true "escaped value round-trips" bash -c ". '$profile_file'; [ \"\$HTTP_PROXY\" = \"http://it's-a-proxy:3128\" ]"

# With no proxy/CA vars set, no stale file is left behind.
printf 'stale\n' > "$profile_file"
assert_true "clears profile when no vars set" \
    env -u HTTP_PROXY -u HTTPS_PROXY -u NO_PROXY -u ALL_PROXY -u http_proxy -u https_proxy \
        -u no_proxy -u all_proxy -u NODE_EXTRA_CA_CERTS -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE -u CODEX_CA_CERTIFICATE -u CUSTOM_CA_CERT \
    bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; write_proxy_ca_profile '$profile_dir'"
assert_false "stale profile removed when no vars set" test -f "$profile_file"

# The su whitelist covers both proxy and CA variables.
assert_true "su whitelist includes proxy vars" bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; case \",\$PROXY_CA_ENV_VARS,\" in *,HTTPS_PROXY,*) exit 0;; *) exit 1;; esac"
assert_true "su whitelist includes CA vars" bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; case \",\$PROXY_CA_ENV_VARS,\" in *,NODE_EXTRA_CA_CERTS,*) exit 0;; *) exit 1;; esac"
assert_true "su whitelist includes Codex CA var" bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; case \",\$PROXY_CA_ENV_VARS,\" in *,CODEX_CA_CERTIFICATE,*) exit 0;; *) exit 1;; esac"

# su_preserving_env passes the whitelist to a su that supports -w, and preserves
# the value across a (stubbed) login-shell reset.
su_bin="$TMP_DIR/su-bin"
mkdir -p "$su_bin"
cat > "$su_bin/su" <<'SCRIPT'
#!/usr/bin/env bash
# Stub su: supports --help (advertises -w), and with -w passes named vars through.
if [ "$1" = "--help" ]; then
    echo "  -w, --whitelist-environment <list>"
    exit 0
fi
# Expect: -w <list> - <user> -c <cmd>
if [ "$1" = "-w" ]; then
    whitelist="$2"; shift 2
    # remaining: - <user> -c <cmd>
    shift 3
    # Re-export whitelisted vars into a clean shell to simulate login preservation.
    exports=""
    IFS=',' read -ra vars <<< "$whitelist"
    for v in "${vars[@]}"; do
        val="${!v-}"
        [ -n "$val" ] && exports="$exports export $v='$val';"
    done
    exec env -i bash -c "$exports $1"
fi
exit 2
SCRIPT
chmod +x "$su_bin/su"
result=$(env PATH="$su_bin:$PATH" HTTPS_PROXY="http://proxy.example:3128" \
    bash -c "source '$ROOT_DIR/docker/lib/entrypoint_helpers.sh'; su_preserving_env testuser 'echo \$HTTPS_PROXY'")
assert_true "su_preserving_env preserves proxy across login shell" test "$result" = "http://proxy.example:3128"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
