# Usability candidate: local acceptance

Revision 0.01, 9 October 2026. Draft PR #97 targets 1.7.0; no release is published by this work. CI evidence and local acceptance are separate. Keep account identifiers and raw auth/log output out of the public PR.

Download the `release-candidate-exe` artifact from the latest successful PR CI run. Extract and run `AI_Docker_Manager_v1.7.0.exe`. First try the health/connections screen with your existing 1.6 container. For new container functionality, use setup to recreate it after the existing rescue check; retain named volumes. Do not remove volumes to upgrade.

| Check | Expected result |
| --- | --- |
| Existing 1.6 / unlabelled image | Tool-start checks and direct terminals work. Authentication is unverified; selected repair requests recreation. No guessed container commands run. |
| Docker Desktop stopped or unavailable | The screen stays responsive and provides a plain next step and copyable support text. A repair is not presented as a Docker/WSL/network fix. |
| New connections screen | Claude is the initial choice; Codex is under Advanced. Check health, Sign in, Open, Resume and Open terminal work with keyboard navigation and your display scaling. |
| Native sign-in | Claude uses `claude auth login`; Codex uses `codex login`. If browser callback cannot complete, use the vendor terminal's manual instructions; Codex device-code flow requires enabling it in account security/admin settings. No model/permission/MCP settings change. |
| Status accuracy | A starting binary alone is “Tool ready”, not authenticated. A successful native auth status is “Ready” with a local check time; failed/offline/unsupported checks are “Unable to verify”. This does not prove credits, network/model access or company-data approval. Keyring login works without auth.json. |
| Folder selection | Open terminal as well as Open/Resume must retain the selected subfolder after startup on both new and 1.6 containers. Enter `/workspace/<folder>`. On new and real 1.6 containers the agent starts there even if .bashrc runs `cd /workspace`. Test spaces, Unicode, apostrophes, `$ ; % ^ ! " & |`. No extra commands or tabs run. |
| Missing or moved folder | A readable message appears, no agent starts elsewhere, and the terminal stays open. A symlink escaping /workspace is rejected. |
| Resume | Vendor conversation selector opens in the chosen folder. Continue yesterday's task without copying a transcript into the manager. |
| Settings preservation | Before/after compare your custom models, approvals, hooks, MCP and instructions locally. No launcher action edits those settings. Account/API-key environment choices remain the vendor's. |
| Busy maintenance | Open a managed Claude/Codex session, then request repair. It reports busy. Start maintenance first, then launch an agent: it waits for you to retry rather than racing package replacement. Repeat with a manually opened session. |
| Selected repair | A broken-but-present Claude/Codex is recognised. Reinstalling Codex stages and validates a replacement before publishing the normal npm global package and launcher. Verify `npm ls -g @openai/codex` and a later npm reinstall/update still own the running binary. Successful/failed validation leaves no staging copy. Claude uses its native latest installer under the lock; it is not staged or pinned. Unrelated tool installations and saved credentials remain. |
| Interrupted repair | Close the screen during repair. The detached container job continues. Reopen and check health before retrying; a restart may interrupt the job, and an unverified result is never shown as success. Never remove a working installation to recover. |
| Stale results | Change tool while checking: results for the old tool are discarded. Editing the folder preserves a running health check, because health is independent of the folder. Recreating/stopping a container during a check gives a retry message. |
| Copy support | Review the status first. Clipboard text contains no credentials, account identifiers, workspace paths or raw vendor output. Nothing is uploaded or sent. |
| Existing functions | Setup, terminal, Vibe Kanban, resource settings, updates and rescue/uninstall routes still work. The developer alternate launcher bundles and runs the same source implementation without requiring ps2exe or a compiled EXE. |

The application opens its native console directly with PowerShell; Windows Terminal may be the configured Windows terminal host. It does not construct cmd.exe or wt.exe command strings. Native repository trust prompts remain visible.

## Disposable Desktop SSH experiment

Use synthetic or public material only. Decide privately which authorised seat will run the pilot, ideally a dedicated seat. The pilot uses a separate `ai-desktop-pilot` container and home volume; it does not mount ai-cli's credentials. Never point its workspace at confidential projects or an entire SharePoint tree.

From the source checkout, create a dedicated SSH key using Windows OpenSSH (do not overwrite an existing key):

```powershell
ssh-keygen -t ed25519 -f "$env:LOCALAPPDATA\AI-Docker-CLI\desktop-pilot-key"
.\experiments\desktop-pilot\pilot.ps1 -Action Start -Workspace C:\AI_Work\desktop_synthetic_pilot -PublicKey "$env:LOCALAPPDATA\AI-Docker-CLI\desktop-pilot-key.pub"
.\experiments\desktop-pilot\pilot.ps1 -Action Evidence
```

The experiment requires a source checkout. Pilot scripts and SSH setup are excluded from the production image and EXE. It builds a separate `ai-docker-pilot-base:local` image and uses Docker’s default seccomp policy, with no `seccomp=unconfined` override. If a vendor sandbox fails under that policy, record the failure for review; do not silently relax it. Port 2222 must be free; the helper fails rather than reconfiguring existing mobile SSH. The standalone pilot publishes only `127.0.0.1:2222`; there are no dashboard/Mosh mappings. Local SSH forwarding is restricted to the container loopback. Password and root/agent/reverse forwarding are disabled.

Wait for the initial install. Verify the printed SSH host fingerprint against the SSH connection prompt using `ssh -p 2222 -i <pilot-private-key> pilot@127.0.0.1`. Do not turn off host-key checking. Add the SSH connection and identity file in Claude Desktop's Code tab. The generated HTML uses the vendor-documented [SSH session link](https://code.claude.com/docs/en/desktop#open-an-ssh-session-from-a-link); whether it opens this pilot successfully, and resume behavior, must be proven through Desktop itself. Do not promise Desktop compatibility until this experiment passes.

Record privately:

- Actual user, HOME, workspace, Claude path/version and settings hashes before first connection, after connection, after reconnect, and after recreating the **pilot** container with its home volume retained. Desktop installs its own remote Claude; decide installation ownership if the version/path changes. Scheduled container updates are disabled in this pilot, but vendor self-updates are outside the manager lock.
- Which seat/account type signs in, where its login lives, whether custom settings survive, and whether the saved login belongs solely to this disposable pilot.
- Whether a colleague completes a realistic synthetic task unaided, locates the output, reviews a diff and continues the conversation the next day. Include a non-Git folder. Separately track voluntary weekly use/support requests for two weeks without recording prompts or file contents.

Stop using the same paths with `-Action Stop`. This stops the pilot without deleting work. Before deliberate teardown, inspect its workspace and home for unique work, retain useful synthetic outputs, and identify only pilot state/credentials for disposal. Never log out your real Desktop account or revoke shared credentials as a teardown shortcut. No automatic teardown is included.

## Repair and update recovery

“Coordinated” means mutual exclusion with managed sessions, not an atomic vendor installer. Claude repair runs Anthropic’s native installer for its current latest release and is neither staged nor pinned; verify its version and settings after repair. Codex repair stages the pinned package in npm’s normal global layout, validates it, retains the previous package/launcher during publication, and removes its temporary download/backup on completion. A later ordinary npm update must replace the binary the launcher runs.

If a container stops during Codex publication, `~/.ai-docker/codex-recovery` records the retained staging/backup directory. Further selected Codex repairs refuse to overwrite it. Close sessions before inspecting that directory and recovering `old-package` to `~/.npm-global/lib/node_modules/@openai/codex` and `old-launcher` to `~/.npm-global/bin/codex`. Verify `codex --version` and only then remove the recovery record; preserve any retained backup until recovery has been reviewed. This is a deliberate recovery route, not automatic cleanup of existing stage directories.

Closing the UI does not terminate a detached repair. Completed result files are consumed when polled; uncollected result files older than seven days are removed on a later repair. An unfinished job or missing result is never reported as success.

The bare updater runs its existing interval check. Managed startup/cron use `--scheduled`, retrying busy admission three times at five-second intervals. Busy exits 75, records `skipped_busy` with an attempt time in `~/.ai-docker/update-skipped`, and changes neither another updater’s status nor the last successful check/scheduling time. The health screen and full status report show this separate skip history. A successful updater/check, including an admitted scheduled interval skip, clears the busy notice. Vibe Kanban, 9router and OmniRoute are intentionally included in active-process detection: stop a running server before updating or repairing managed tools, then restart it. Weekly checks keep deferring while these servers stay running; no process is terminated to make an update run. Missing locking exits 69. The managed session shell owns the admission descriptor; vendor processes and their descendants inherit it closed. If a window closes, remaining real vendor sessions may still be detected by process scanning and defer maintenance; that is active-process protection, not a leaked lock.

## Company-data gate

Before any later company-data trial, record the provider, account type, data-use/training and retention terms, settings, and responsible Cainmani confidentiality approval in private evidence. Separately agree the narrowly scoped read-only reference mount or approved working-copy process, authoritative SharePoint/VDR source and output return/versioning. Neither the pilot nor this release automatically syncs SharePoint. If either approval/access decision is unclear, use synthetic/public material only.

Every project in ai-cli still shares credentials/home and passwordless sudo. The workspace boundary is a launch/path rule, not hostile-project isolation. Manual/SSH launches and vendor self-updaters may bypass maintenance admission; visible common agent processes are checked conservatively, but that is not a guarantee against arbitrary processes or simultaneous external launches.

## Review revision evidence

The follow-up to the October 9 Claude review keeps implementation and experiment source in draft PR #97. The tracked plan, acceptance checklist, developer guide and PR body are the durable public handoff; local candidate binaries and private task notes supplement them. No SharePoint destination or upload has been authorised. Obsidian capture remains unavailable in this session.

| Automated evidence | What it proves | What still needs local acceptance |
| --- | --- | --- |
| Python contracts | Real interactive Bash startup, aliases/wrappers/status after exit, folder containment, managed admission, native status filtering, and staged Codex repair using real npm with a local package/dependency and later replacement | Actual vendor binaries and authentication; interrupted container recovery |
| Updater Bash suite | Bare default dispatch, interval checks, busy history preserving running/success records, visible long-running CLI skips, bounded scheduled retry, and existing update failures/verification | Behavior with the user's running tools and network |
| Windows PowerShell 5.1 launch boundary | Source launcher actually invokes inspect/exec through a compiled fake Docker executable with hostile folder characters and old/new container routing | Real Docker terminal, keyboard behavior and vendor prompts |
| Compiled EXE smoke | Production menu bounds and embedded connections UI ready/error/busy dispatch, under Restricted policy | High-DPI layout and live Docker/launch operations |
| Docker Smoke | Actual image health/readiness, bare/scheduled updater, live named-process admission, production terminal aliases/wrappers, and post-agent folder/environment using a mock agent | Native sign-in, paid-model access, and Desktop SSH experiment |

Use the final PR commit's CI artifact, not a previous downloaded candidate. PR #97 remains draft pending the user's local checks; version 1.7.0 is unreleased.
