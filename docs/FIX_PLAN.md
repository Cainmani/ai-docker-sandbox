# 1.4.0 Stabilization Tracker

This checked-in tracker mirrors the approved runtime stabilization work. A checkbox is marked complete only when the implementation exists and its applicable local evidence has passed. CI-only and Docker-runtime evidence remains open until observed on the pull request.

## Safety constraints

- Preserve `claude-config`, `tool-auth`, `router-data`, `vibe-kanban-data`, and `ssh-keys` during upgrades.
- Never make volume deletion the default; disposable tests use a unique Compose project and remove only their own resources.
- Never remove a working CLI before its replacement is installed and validated.
- Keep Windows PowerShell 5.1 compatibility.

## Phase 1 — Shared foundations and release source

- [x] Root `VERSION` is the 1.4.0 source used by build metadata and launcher-visible versions.
- [x] Wizard propagates the product version into `docker/.env` as `AI_DOCKER_VERSION` (launcher-passed, VERSION-file fallback), so the built image is labelled with the real version instead of the compose `0.0.0` default. CI version-consistency asserts the propagation call is present.
- [x] Environment helpers atomically read/set/remove quoted values and validate ports.
- [x] Docker helpers distinguish unavailable Docker, readiness timeout, exit, and unhealthy state.
- [x] Router and entrypoint helper modules are sourceable and packaged with the executable.
- [x] Structural tests cross-check Dockerfile-copied helper libraries against package placeholders.
- [ ] Observe CI version-consistency and Windows executable metadata gates.

## Phase 2 — Non-destructive install/update behavior

- [x] Persistent `FORCE_CLI_REINSTALL` was removed; setup removes stale values from canonical `.env`.
- [x] Force/repair installation preserves working tools and reports required-tool failures.
- [x] Structured `STATUS=ok|partial` records support legacy markers and selective later repair.
- [x] Updater result polarity and aggregate failure reporting are covered behaviorally.
- [x] npm snapshot/restore preserves packages after failed updates.
- [x] Cron registration and daemon liveness are implemented idempotently and behaviorally tested.

## Phase 3 — Existing-user migration and networking

- [x] Auth/config directory migration stages and verifies data before source replacement.
- [x] Codex `wire_api = "chat"` migration backs up, preserves unrelated settings, and is idempotent.
- [x] Managed `.bashrc` router block upgrades atomically while preserving user content.
- [x] Router PID ownership, TERM/KILL escalation, socket release, and missing-probe states are tested.
- [x] Proxy variables pass through build and runtime paths.
- [x] Proxy/custom-CA variables survive `su -` login-shell resets (whitelisted via `su -w`) and are persisted to `/etc/profile.d/ai-docker-proxy.sh` for interactive/SSH logins; the auto-update cron entry sources that profile. Behaviorally tested in `tests/test_entrypoint_helpers.sh`.
- [x] Optional custom-CA mount/trust variables are implemented without changing default Compose behavior.
- [x] `configure-tools --diagnose` TLS probe no longer conflates an unauthenticated/bare-root HTTP status (401/403/404/421) with a transport failure; only genuine DNS/connect/timeout/SSL errors report `TLS=failed`. Covered by `tests/test_configure_tools.sh`.
- [ ] Observe disposable custom-CA runtime verification in Docker-capable CI/local environment.

## Phase 4 — Compose and lifecycle

- [x] Fixed Compose/image identity and canonical `docker/.env` are used.
- [x] Mobile SSH/Mosh mappings are isolated in an opt-in override.
- [x] Ports are range-validated before Compose/shell execution.
- [x] Readiness uses bounded health/status polling and an entrypoint completion marker.
- [x] Semantic image metadata and launcher/container skew warnings are covered by Pester.
- [x] Three-tier uninstall preserves volumes by default and never removes the workspace.

## Phase 5 — Wizard resilience

- [x] WSL hardware state and core-count bounds are validated.
- [x] Navigation state supports the existing-config skip/back regression path.
- [x] Long-running wizard work has busy/cancel guards and cooperative process-tree termination.
- [x] Container password policy and Docker timeout/error classification are hardened.

## Phase 6 — Security and logging

- [x] PowerShell, Bash, packaged, and updater-fallback sanitizers cover provider/GitHub/bearer/JWT/private-key and generic secret contexts.
- [x] Public-sharing claims now state that output is sanitized and must be reviewed.
- [x] Documentation describes the single-user container, passwordless-sudo, mounted-workspace, and no-Docker-socket trust boundaries.
- [x] Residual HTTPS/TLS/vendor trust is documented where stable artifact verification is unavailable.

## Phase 7 — Tests and CI

- [x] Focused Bash suites cover updater, install repair, migration, routers, auth persistence, and cron helpers.
- [x] Pester covers env parsing, ports, WSL bounds, Docker readiness/version skew, and sanitizers.
- [x] CI defines Linux tests plus Windows PowerShell 5.1 and PowerShell 7 Pester.
- [x] ShellCheck errors block while warning-level output remains visible/nonblocking.
- [x] Disposable Docker smoke workflow validates Compose, readiness, commands, migration, cron, router probing, and recreate persistence.
- [ ] Observe Windows matrix and Docker smoke workflow results on the pull request.

## Phase 8 — Migration and recovery

- [x] Changelog, README, user, migration, logging, remote-access, and development guidance cover 1.4.0.
- [x] Existing installs are directed to preserve/identify volumes, remove stale force flags, recreate once, inspect structured status, and verify auth/router/network state.
- [x] `configure-tools --diagnose` provides sanitized install/auth/router/proxy/DNS/TLS/version classification.
- [x] Reauthentication is recommended only when credential files are genuinely absent or expired.

## Verification evidence

Observed locally as of 2026-07-10:

- [x] `tests/test_entrypoint_helpers.sh`: 25 passed, 0 failed after cron-helper extraction.
- [x] `tests/run_tests.ps1 -SkipDocker`: passed after package/CA structural additions.
- [ ] Full `bash -n` and every `tests/test_*.sh` suite after final edits.
- [ ] Full Pester suite after final edits.
- [ ] PowerShell parser checks for all modified scripts.
- [ ] Base/mobile/custom-CA Compose config validation.
- [ ] ShellCheck/hadolint where installed.
- [ ] Disposable local Docker build/readiness/recreate flow when Docker is available.
- [ ] `git diff --check` after final integration.
- [ ] Pull-request CI and release-consistency checks.
