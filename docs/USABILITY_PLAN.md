# AI Docker usability implementation plan

Draft, 9 October 2026. Baseline: main at `e903677`, released as v1.6.0 on 8 October 2026.

Make daily use follow one clear journey: choose a project, check that the selected tool is available, and start working. The proposed 1.7 scope is a project picker, guided tool connections, and visible health with repair actions. Keep the native terminal and Vibe Kanban available throughout.

This draft PR starts with planning only. Continue implementation and review on the same branch and PR once scope is agreed. Keep it draft until the implementation and release gates below are satisfied; merge to main only after the user is happy with the result. Version 1.7 is a proposed target, not a release commitment.

## Scope and sequence

| Order | Deliverable | Completion condition |
| --- | --- | --- |
| 1 | Shared launcher and tool integration foundations | Both launcher variants use the same behavior; installed tool capabilities are detected safely |
| 2 | Project home screen | Open, create, clone, pin and reopen projects; launch the selected tool in the right directory |
| 3 | Guided connections | Native sign-in for supported tools; installation, saved authentication and connection checks are distinct |
| 4 | Health and recovery | Show existing health records; offer bounded diagnostics and targeted, non-destructive repair |
| 5 | Migration, packaging and user review | Existing 1.6 users retain settings and work; compiled EXE and real Windows flows pass |
| Later | Browser workspace, protected mounts, profiles, published images and separate-change workflows | Each passes its own feasibility and acceptance gate before becoming release scope |

Orders 1–5 form the proposed initial release. Later items are planned here so that the first implementation leaves room for them; they are not prerequisites for merging the initial release. Expand this PR's scope only through an explicit scope decision and update its description to match.

## Current implementation and gaps

- `scripts/AI_Docker_Complete.ps1` is the packaged application; `scripts/AI_Docker_Launcher.ps1` is the alternate launcher. Their UI behavior overlaps and can drift.
- `scripts/launch_claude.ps1`, despite its name, opens a login shell at `/workspace`. Extend or delegate this path for project-specific launches while retaining the existing entry point.
- `docker/configure_tools.sh` offers native interactive configuration, but some status checks infer authentication from files or environment variables. These are evidence of saved configuration, not proof of a working account.
- `docker/ai_docker.sh` implements health, diagnostics, rescue and cleanup. `~/.ai-docker/update-status` is authoritative for update health. The launcher should consume structured output rather than parse colored display text or invent another status record.
- `docker/install_cli_tools.sh --repair` skips healthy tools but currently evaluates the installation set. A button labelled "Repair Codex" needs a real tool selector before it can make that promise.
- The container shares the mounted workspace across tools. Launching in a subfolder selects context; it does not restrict access to sibling projects.

## User journeys

### Existing user

Open the manager and see recent projects plus container health. Select a project and an agent, then choose Open. Start the container if necessary, wait for readiness, and open the agent in that project's directory as the existing container user. Preserve a plain terminal option and the Vibe Kanban launch path.

Never run setup automatically because the project list is empty. If the container is missing, show a specific setup action. If Docker is unavailable, distinguish not installed, not running, and readiness timeout.

### New user

Complete the existing setup wizard, then choose a folder or create a project. Connect the desired tool using its native flow and return to the project screen. Connecting every installed tool is optional. Explain subscription login versus API-key billing where relevant without requesting secrets in the general project UI.

### User with a problem

Show which tool or operation failed and when it was checked. Offer its native sign-in, diagnostics, or repair action. Network failure is not labelled expired credentials. A tool that is already working remains available while another tool is repaired.

## Compatibility contract

1. Launch installed vendor binaries through documented interfaces, with capability detection for the installed version. Never assume all tools have the same login, status or resume command.
2. Preserve the same container user, home directory, login-shell environment and existing persistence volumes. The manager does not copy or reinterpret credential stores.
3. Store project selection and UI preferences separately from vendor settings. Do not rewrite models, API base URLs, permissions, MCP entries, hooks, skills, `AGENTS.md`, `CLAUDE.md`, or project configuration when opening a project.
4. Pass only the arguments needed for the user's chosen operation. No automatic permission bypass or trust acceptance. Tool prompts remain visible in an interactive terminal.
5. Detect unsupported commands and fall back to opening the tool or plain terminal. Unknown status is an honest state, not a reason to reset configuration.
6. Preserve human-readable health commands and their existing exit-code semantics when adding machine-readable output.
7. Keep repairs and updates serialized using the existing update lock contract. Avoid replacing a binary used by an active session; explain how to finish the session and retry.
8. Preserve the Windows PowerShell 5.1 runtime, compiled EXE behavior under Restricted policy, release asset names, loopback-only dashboard ports, and rescue protections.

Official interfaces to recheck against installed versions during implementation: [Codex CLI](https://learn.chatgpt.com/docs/developer-commands?surface=cli), [Codex configuration precedence](https://learn.chatgpt.com/docs/config-file/config-basic), and [Claude CLI](https://code.claude.com/docs/en/cli-reference). Add verified Gemini, OpenCode and GitHub CLI references when their adapters are implemented.

## Phase 1 Shared foundations

- [ ] Extract shared project, process and UI behavior used by both launcher variants. Keep EXE loading compatible with embedded ScriptBlocks; do not dot-source extracted scripts inside the compiled host.
- [ ] Define a small, versioned tool registry: stable tool ID, executable, display name, supported launch/login/status/repair actions, and capability detection. Use a fixed allowlist rather than commands supplied by project metadata.
- [ ] Define a versioned status response with timestamp, tool version, installation state, authentication evidence, connection state, supported actions, and sanitized failure classification.
- [ ] Add structured output to existing health/diagnostic entry points. Keep normal text output and existing behavior intact. Missing or malformed records become unknown with an actionable explanation.
- [ ] Implement asynchronous process execution with timeouts, bounded output, cancellation and duplicate-action guards. Slow Docker commands, directory scans or network checks must not freeze WinForms.
- [ ] Separate lightweight launch-time checks from explicit detailed/network checks. Normal opening must not send an AI prompt or incur inference charges.

Expected touch points: `scripts/docker_helpers.ps1`, a shared launcher helper, `docker/ai_docker.sh`, `docker/configure_tools.sh`, and both launcher templates. Add embedded-file registration, extraction and structural tests for every new runtime dependency.

Acceptance: a failing or older CLI cannot crash the manager; unknown capabilities have a usable terminal fallback; launcher variants produce the same actions; canceled operations never show success.

## Phase 2 Project home screen

- [ ] Show a searchable recent/pinned project list, selected tool, Open, Open terminal, Open in Explorer, and Vibe Kanban. Include Add existing folder, New project and Clone repository actions.
- [ ] Store a versioned `projects.json` under the existing Windows application-data directory. Record stable IDs, display names, workspace-relative paths, preferred tool, pin state and last-opened time; never secrets or arbitrary shell commands.
- [ ] Save atomically and handle malformed JSON, concurrent launcher instances and missing folders. Preserve a corrupt file for recovery rather than overwriting it silently.
- [ ] Translate the configured Windows workspace root to `/workspace` using validated relative paths. Test canonical containment, traversal, symlink/junction escapes and missing paths. External folders require a later explicit mount workflow.
- [ ] Pass arguments safely across PowerShell, Windows Terminal/cmd and Docker. Do not concatenate user-controlled names into a shell command. Test spaces, Unicode, apostrophes, ampersands, dollar signs and other metacharacters.
- [ ] Create projects only after validating the name and destination. Clone via the existing Git/GitHub tools; do not overwrite an existing destination, and make interrupted clones visible for retry/review.
- [ ] Keep both terminal hosts supported and preserve the existing launcher command for callers that do not select a project.
- [ ] Make the screen usable with keyboard navigation, high-DPI scaling, readable status text and sufficient contrast. Status must not depend on color alone.

Acceptance: opening a selected project starts the chosen native tool there; an empty list does not alter existing setup; removing an item only removes the listing; canceled create/clone actions preserve existing folders.

## Phase 3 Guided tool connections

- [ ] Show separate installation and connection information. Use states such as Not installed, Installed, Sign-in needed, Saved authentication, Verified at a stated time, Unknown and Check failed.
- [ ] Implement Claude and Codex first, then Gemini, GitHub CLI and OpenCode. Treat the OpenAI SDK separately from an interactive coding agent. Leave optional routers in their existing opt-in flow.
- [ ] Use supported native status commands where available. File-based fallback reports saved authentication only, without exposing or reading token values into the UI.
- [ ] Launch sign-in in an interactive terminal as the same container user. Verify browser/device-code behavior across the Windows/container boundary; offer supported manual/device flows when automatic callbacks cannot work.
- [ ] Recheck status when the user returns. Closing a terminal or a zero process-launch result does not mean authentication succeeded.
- [ ] Make any live account check explicit and classify network, TLS, rejected credentials, usage/quota restrictions and unsupported checks separately. If no non-inference check is supported, explain that verification is unavailable instead of issuing a billable prompt.
- [ ] Mask secrets in any dedicated API-key path; keep them out of command arguments, project metadata and logs. Prefer the vendor's existing credential handling.

Acceptance: subscription and supported API-key flows work; expired credentials and offline conditions have distinct outcomes; changing the selected agent does not change another agent's settings or account.

## Phase 4 Visible health and targeted recovery

- [ ] Display container readiness, installed tool versions, update result and ages, disk usage, resource limits and the timestamp of the latest observation.
- [ ] Read durable update status rather than infer successful updates from the scheduling marker. Label disk measurements accurately: container filesystem usage is not necessarily Windows Docker virtual-disk size or reclaimable space.
- [ ] Offer Refresh, Diagnostics, Sign in, Repair selected tool, and the existing full update action where appropriate. Do not label an all-tool update as a selected-tool update.
- [ ] Add validated tool selection to repair, preserving aggregate install-marker correctness after partial repair. Keep healthy installations, vendor config and credentials intact on failure.
- [ ] Serialize maintenance with startup/cron/manual updates and handle lock contention clearly. Recheck running sessions before a disruptive action.
- [ ] Present sanitized progress, operation results and concrete next actions. Export sanitized support information only on request, with a preview before sharing.
- [ ] Link to the existing cleanup preview and rescue flow. Preserve report-only treatment of repositories, virtualenvs and scratch dependencies; no generic "clean everything" button.

Acceptance: failures are not shown as success; update/repair operations cannot overlap; working tools survive a failed repair; rebuild and uninstall still pass the rescue check.

## Phase 5 Migration and release readiness

- [ ] Upgrade from an existing 1.6 installation without deleting volumes, changing workspace mappings or resetting accounts. Project preferences are additive and optional.
- [ ] Degrade gracefully with an older container: retain terminal access and explain which new actions need a container upgrade. Route necessary recreates through the existing rescue checks.
- [ ] Update the user manual, quick reference, troubleshooting and migration guidance to show the new flows and truthful folder-access boundaries.
- [ ] Update build embedding, extraction, Dockerfile COPY/chmod and line-ending lists as applicable. Check both launcher variants and the actual packaged EXE.
- [ ] Bump release versions only when implementation scope is settled. Update ContainerBaselineVersion only if container-side changes actually require recreation.
- [ ] Publish a CI-built candidate artifact for user testing on the draft PR; do not create a release tag or overwrite published release assets.

## Later phases and decision gates

| Feature | Proposed behavior | Gate before implementation |
| --- | --- | --- |
| Browser workspace | Optional browser chat, files and native session discovery alongside terminal/Vibe Kanban | Prototype compatibility with persistent state, installed CLI versions and session ownership; evaluate licensing; loopback-only by default; authenticated remote access requires separate design |
| Protected references and project isolation | Explicit editable project and read-only reference mounts, with a clear access summary | Design per-project containers/Compose identities, labels, ports, lifecycle and persistence; a subfolder picker alone cannot enforce isolation; verify write protection and credential visibility |
| Work and personal profiles | Explicitly isolated accounts/configuration when supported | Distinguish model/settings profiles from separate credentials; choose supported vendor homes and separate volumes; validate switching without automatic credential copying |
| Published images | Pull a tested, versioned image with a local-build fallback | Measure first-run time and download size; define digest verification, provenance, tag-to-release mapping, proxy/custom-CA behavior, offline recovery and supported architectures |
| Separate changes and review | Create a persistent Git worktree, review diffs and checks, then merge explicitly | Reuse Vibe Kanban where possible; retain untracked/ignored work; handle conflicts and non-Git folders; no automatic commit, merge or discard |
| Resume sessions | Reopen a tool's existing conversation in the right project | Use native supported resume interfaces; distinguish starting a new session from attaching to a live process; avoid two writers to one conversation |
| Editor integration | Open the selected container project in VS Code | Verify Dev Containers prerequisites, same user/home and configuration, path mapping and behavior when the extension is absent |

Reference patterns: [CloudCLI](https://github.com/siteboon/claudecodeui) for project/session UI; [claude-sandbox](https://github.com/rsh3khar/claude-sandbox) for remembered mounts, worktrees and published images; [dclaude](https://github.com/stanislavkozlovski/dclaude) for warm project containers and read-only references; [DevPod](https://github.com/loft-sh/devpod) for editor/devcontainer workflows; [devc](https://github.com/grahambrooks/ai-dev-container) for session-aware lifecycle. Borrow behavior after verification rather than importing their configuration wholesale.

## Validation matrix

| Area | Required evidence |
| --- | --- |
| Project launch | Windows PowerShell 5.1 and 7 helper tests; both terminal hosts; paths with spaces, Unicode and shell metacharacters; invalid/outside/missing paths; correct container user and working directory |
| Preferences | Atomic saves, concurrent instances, malformed file recovery, stale folders and pin/recent ordering; no folder deletion from removing a listing |
| Tool integrations | Supported installed versions plus unsupported-command fallback; healthy, absent and broken binaries; native status/login behavior; custom MCP, hooks, instructions and settings remain intact |
| Authentication | User-observed real login for each supported interactive tool; supported account modes; failed/canceled login; expired credentials; offline/proxy/TLS conditions; no secret leakage |
| Maintenance | Lock contention with startup/cron, partial selected-tool repair, active-session handling, interrupted operation, preserved working tools and accurate durable records |
| Persistence | Existing 1.6 upgrade plus disposable fresh-install/recreate flows; credentials, conversations, user config and work survive; old-container fallback works |
| Packaging | PowerShell parsers, Pester matrix, focused behavioral Bash tests, required lint, embedding consistency, version consistency, compiled EXE Restricted-policy smoke and disposable Docker smoke |
| Usability | Real Windows screenshots and walkthrough: fresh user reaches a working agent; existing user opens a recent project; failing tool is diagnosed/repaired; keyboard and high-DPI checks |

Use mock tools for repeatable error/timeout/argument tests and uniquely named disposable Docker resources for persistence tests. Mocks cannot certify real OAuth/browser behavior. Never point destructive integration tests at the user's live workspace or volumes.

## Draft PR review and merge gates

- [ ] Agree initial scope and review the home-screen layout before substantial UI implementation.
- [ ] Land phases as focused commits on this branch; keep this checklist and PR description current with implementation and observed evidence.
- [ ] Review config preservation, path/argument handling, auth boundaries, maintenance locking and rescue behavior after each affected phase.
- [ ] All required CI checks pass on the final commit; record Windows and real-login evidence separately from mocked CI evidence.
- [ ] User tests the compiled candidate against an existing 1.6 workspace and approves the final behavior.
- [ ] Resolve material review findings, confirm documentation and version metadata, and check the final diff against main.
- [ ] Mark ready and merge only after the user's explicit go-ahead. Release tagging/publishing remains a separate action.

## Working handoff

Planning branch: `feature/usability-plan`. Persistent worktree: `/workspace/_wt/ai-docker-usability`, created to isolate this work from local edits and `dist/` in the original checkout. Keep it for implementation and review; do not remove existing worktrees or artifacts as part of this task. The original checkout remains untouched.

At creation, only this plan is implemented. No runtime behavior, release metadata or published assets are changed. Next action: review initial scope/layout, then implement Phase 1 on this draft PR.
