# AI Docker Manager - Testing Walkthrough

## Pre-CEO Demo Testing - Step-by-Step Guide

**Purpose**: Walk through all critical tests to ensure the tool works perfectly before CEO demo.

**Date**: ________________
**Tester**: ________________

---

## Phase 1: Run Automated Unit Tests

### Step 1.1: Run Test Suite

```powershell
# Open PowerShell in project directory
cd C:\path\to\ai-docker-cli-setup

# Run automated tests
powershell -ExecutionPolicy Bypass -File run_tests.ps1
```

**Expected Output**:
```
================================================================
  AI DOCKER MANAGER - AUTOMATED TEST SUITE
================================================================

[PASS] File exists: setup_wizard.ps1
[PASS] File exists: launch_claude.ps1
...
[PASS] entrypoint.sh sets ownership of .claude directory
...
ALL TESTS PASSED - READY FOR DISTRIBUTION
```

**Result**: [ ] All tests passed
**Notes**: _______________________________________________

---

## Phase 2: Clean Environment Preparation

### Step 2.1: Clean Previous Installation

```powershell
# Stop and remove old container
docker stop ai-cli
docker rm ai-cli

# Remove old image (force rebuild)
docker rmi ai-docker-ai

# Remove old configuration
Remove-Item "$env:LOCALAPPDATA\AI_Docker_Manager" -Recurse -Force -ErrorAction SilentlyContinue

# Remove old AI_Work folder (if testing)
# CAREFUL: This deletes all your work! Only do for fresh test
# Remove-Item "C:\path\to\AI_Work" -Recurse -Force
```

**Result**: [ ] Clean environment confirmed
**Notes**: _______________________________________________

### Step 2.2: Verify Docker Desktop

```powershell
# Check Docker is running
docker info

# Check Docker Compose
docker compose version
```

**Expected**: Both commands work without errors

**Result**: [ ] Docker Desktop running
**Notes**: _______________________________________________

---

## Phase 3: Build New Executable

### Step 3.1: Rebuild AI_Docker_Manager.exe

```batch
# Double-click this file:
BUILD_NOW.bat

# OR run in PowerShell:
powershell -ExecutionPolicy Bypass -File build_complete_exe.ps1
```

**Watch for**:
- [ ] All files read successfully
- [ ] Base64 embedding completes
- [ ] No unreplaced placeholders
- [ ] Compilation succeeds
- [ ] AI_Docker_Manager.exe created
- [ ] File size: ~1-2 MB

**Expected Output**:
```
================================================================
                BUILD COMPLETE!
================================================================

Output: AI_Docker_Manager.exe
Size: X.XX MB

Ready for distribution!
```

**Result**: [ ] Build successful
**File Size**: ________ MB
**Notes**: _______________________________________________

---

## Phase 4: First Time Setup Test

### Step 4.1: Launch Setup Wizard

```powershell
# Double-click: AI_Docker_Manager.exe
# OR run:
.\AI_Docker_Manager.exe
```

**Verify**:
- [ ] Main menu appears
- [ ] Matrix green theme visible
- [ ] Two buttons: "1. FIRST TIME SETUP" and "2. LAUNCH CLAUDE CLI"

**Result**: [ ] Launcher opens correctly
**Notes**: _______________________________________________

### Step 4.2: Click "1. FIRST TIME SETUP"

**Verify**:
- [ ] Setup wizard opens (950x700px)
- [ ] Console window opens showing logging
- [ ] Pre-flight checks run automatically

**Console Output to Watch**:
```
[CHECK 1/3] Checking shell script line endings...
[OK] Shell scripts already have correct line endings

[CHECK 2/3] Checking for existing containers...
[OK] No existing container found

[CHECK 3/3] Docker image status...
[OK] No rebuild needed

[PRE-FLIGHT] All automatic checks complete!
[READY] Starting wizard GUI...
```

**Result**: [ ] Pre-flight checks passed
**Notes**: _______________________________________________

### Step 4.3: Page 1 - Welcome

- [ ] Welcome text readable
- [ ] Click "Next"

**Result**: [ ] Page 1 completed

### Step 4.4: Page 2 - Credentials

Enter test credentials:
- Username: `testuser`
- Password: `TestPass123!`
- Confirm: `TestPass123!`

- [ ] Click "Next"

**Test Validation**:
- [ ] Try empty fields → Should reject
- [ ] Try mismatched passwords → Should reject
- [ ] Valid credentials → Should accept

**Result**: [ ] Page 2 completed
**Notes**: _______________________________________________

### Step 4.5: Page 3 - Workspace Location

- [ ] Click "Browse"
- [ ] Select: `C:\Users\<YourName>\Documents`
- [ ] Path appears in textbox
- [ ] Click "Next"

**Console Output to Watch**:
```
[INFO] Creating workspace at: C:\Users\...\Documents\AI_Work
[SUCCESS] AI_Work directory created
[SUCCESS] .env file created
```

**Verify**:
- [ ] AI_Work folder created in selected location
- [ ] .env file created in `%LOCALAPPDATA%\AI_Docker_Manager\.env`

**Result**: [ ] Page 3 completed
**Workspace Path**: _______________________________________________
**Notes**: _______________________________________________

### Step 4.6: Page 4 - Docker Check

**Verify**:
- [ ] Status shows "Docker is running"
- [ ] Click "Next"

**If Docker not running**:
- [ ] Error message appears
- [ ] Start Docker Desktop
- [ ] Click "Retry Check"
- [ ] Status updates

**Result**: [ ] Page 4 completed
**Notes**: _______________________________________________

### Step 4.7: Page 5 - Building Container (CRITICAL!)

**This is where the previous bug occurred!**

**Console Output - WATCH CAREFULLY**:
```
[INFO] Building Docker image...
[EXEC] docker compose build
```

**CRITICAL VERIFICATION**:
- [ ] Console shows: `[EXEC] docker compose build` (NOT `docker compose -f "C:/..."`)
- [ ] NO quoted paths in docker commands!
- [ ] Build completes without errors
- [ ] Console shows: `[SUCCESS] Docker image built`
- [ ] Console shows: `[EXEC] docker compose up -d` (NOT with quotes!)
- [ ] Console shows: `[SUCCESS] Container started`

**Expected Build Time**: 2-5 minutes

**Result**: [ ] Container built successfully
**Build Time**: ________ minutes
**Notes**: _______________________________________________

### Step 4.8: Page 6 - Installing Claude CLI (CRITICAL!)

**Console Output - WATCH CAREFULLY**:
```
[INFO] Installing npm package @anthropic-ai/claude-code
[INFO] This will download packages from npm registry...
[INFO] This step requires internet connection
```

**CRITICAL VERIFICATION**:
- [ ] npm install completes successfully
- [ ] Console shows: `[SUCCESS] Claude Code CLI npm package installed`
- [ ] Console shows: `[INFO] Verifying npm installation...`
- [ ] Console shows: `[SUCCESS] npm package verified`
- [ ] Console shows: `[INFO] Installing wrapper script`
- [ ] Console shows: `[INFO] Making wrapper executable`
- [ ] Console shows: `[INFO] Validating Claude CLI installation...`
- [ ] **CRITICAL**: Console shows: `[SUCCESS] Claude CLI validated successfully`
- [ ] Console shows: `[INFO] Verifying user sudo privileges...`
- [ ] Console shows: `[SUCCESS] User has passwordless sudo access`
- [ ] Console shows: `[SUCCESS] Installation complete!`

**Expected Install Time**: 1-2 minutes

**Result**: [ ] Claude CLI installed and validated
**Install Time**: ________ minutes
**Notes**: _______________________________________________

### Step 4.9: Page 7 - Setup Complete

**Verify**:
- [ ] Completion page displays
- [ ] Instructions mention first-time authentication
- [ ] Instructions are clear
- [ ] Click "Finish"
- [ ] Wizard closes
- [ ] Success message appears (NOT error!)

**Success Message Should Say**:
```
Setup wizard completed successfully!

You can now use 'Launch Claude CLI' to access your workspace.

Configuration stored in: C:\Users\...\AppData\Local\AI_Docker_Manager
```

**Result**: [ ] Setup completed successfully
**Notes**: _______________________________________________

---

## Phase 5: First Launch Test (CRITICAL!)

**This tests the fix for the permission error your boss encountered!**

### Step 5.1: Launch Claude CLI

- [ ] Double-click AI_Docker_Manager.exe
- [ ] Click "2. LAUNCH CLAUDE CLI"
- [ ] Launcher window appears
- [ ] Click "Launch Workspace Shell"

**Verify**:
- [ ] Terminal window opens (Windows Terminal or cmd)
- [ ] Prompt shows: `testuser@ai-cli:/workspace$` (NOT root@!)
- [ ] User is correct (testuser)
- [ ] Location is correct (/workspace)

**Result**: [ ] Terminal opened correctly
**Notes**: _______________________________________________

### Step 5.2: Verify Environment

Run these commands in the terminal:

```bash
# Check user
whoami
```
**Expected**: `testuser`
**Actual**: _______________

```bash
# Check location
pwd
```
**Expected**: `/workspace`
**Actual**: _______________

```bash
# Check sudo works WITHOUT password
sudo whoami
```
**Expected**: `root` (NO password prompt!)
**Actual**: _______________

```bash
# Check claude command exists
which claude
```
**Expected**: `/usr/local/bin/claude`
**Actual**: _______________

```bash
# Check .claude directory permissions (CRITICAL FIX!)
ls -la ~ | grep .claude
```
**Expected**: `drwxr-xr-x ... testuser testuser ... .claude`
**Owner should be testuser, NOT root!**
**Actual**: _______________

**Result**: [ ] All environment checks passed
**Notes**: _______________________________________________

### Step 5.3: First Run of Claude (THE CRITICAL TEST!)

**This is where your boss got the permission error!**

In the terminal, type:
```bash
claude
```

**CRITICAL VERIFICATION**:
- [ ] **NO permission denied error!**
- [ ] **NO "EACCES: permission denied, mkdir '/home/testuser/.claude/debug'" error!**
- [ ] Claude CLI starts successfully
- [ ] Authentication prompt appears (first time only)

**Expected Output**:
```
Welcome to Claude Code!

To get started, you'll need to authenticate...
[Follow authentication prompts]
```

**If you see this error, THE FIX FAILED**:
```
Error: EACCES: permission denied, mkdir '/home/testuser/.claude/debug'
```

**Result**: [ ] Claude started WITHOUT permission errors
**Notes**: _______________________________________________

### Step 5.4: Complete First-Time Authentication

**Follow the authentication prompts**:
- [ ] Enter Anthropic API key or login
- [ ] Authentication succeeds
- [ ] Claude CLI becomes ready

**Verify**:
- [ ] Authentication completed
- [ ] Claude responds to simple query
- [ ] No errors

**Result**: [ ] Authentication successful
**Notes**: _______________________________________________

### Step 5.5: Test Basic Claude Functionality

```bash
# Create a test file
echo "Hello from Docker!" > /workspace/test.txt

# List files
ls -la /workspace/
```

**Verify**:
- [ ] File created successfully
- [ ] File visible in /workspace

Now ask Claude:
```
"List all files in the workspace and read the test.txt file"
```

**Verify**:
- [ ] Claude can list files
- [ ] Claude can read test.txt
- [ ] No permission errors

**Result**: [ ] Claude works correctly
**Notes**: _______________________________________________

### Step 5.6: Verify Files Sync to Windows

**Open Windows File Explorer**:
- Navigate to: `C:\Users\<YourName>\Documents\AI_Work`
- Look for: `test.txt`

**Verify**:
- [ ] test.txt exists in Windows folder
- [ ] File contains: "Hello from Docker!"
- [ ] Files sync bidirectionally

**Result**: [ ] File sync works
**Notes**: _______________________________________________

---

## Phase 6: Persistence Test

### Step 6.1: Exit and Relaunch

```bash
# In terminal, type:
exit
```

- [ ] Terminal closes
- [ ] Double-click AI_Docker_Manager.exe
- [ ] Click "2. LAUNCH CLAUDE CLI"
- [ ] Terminal opens again

```bash
# Type:
claude
```

**CRITICAL VERIFICATION**:
- [ ] **Claude starts WITHOUT asking for authentication again!**
- [ ] Authentication persisted
- [ ] No permission errors
- [ ] Claude works immediately

**Result**: [ ] Authentication persisted
**Notes**: _______________________________________________

### Step 6.2: Container Restart Test

**In PowerShell**:
```powershell
docker stop ai-cli
docker start ai-cli
```

**Then relaunch**:
- [ ] Double-click AI_Docker_Manager.exe
- [ ] Click "2. LAUNCH CLAUDE CLI"
- [ ] Type: `claude`

**Verify**:
- [ ] Container restarts successfully
- [ ] Claude still works
- [ ] Authentication still persisted
- [ ] No permission errors

**Result**: [ ] Container restart works
**Notes**: _______________________________________________

---

## Phase 7: Error Handling Tests

### Step 7.1: Cancel Button Test

- [ ] Run "First Time Setup" again
- [ ] On Page 2 (credentials), click "Cancel"
- [ ] Should ask for confirmation
- [ ] Click "Yes" to cancel
- [ ] Wizard closes properly
- [ ] No crash

**Result**: [ ] Cancel works correctly
**Notes**: _______________________________________________

### Step 7.2: Container Protection Test

**Important: This tests the container protection feature**

- [ ] Run "First Time Setup" AGAIN (intentionally)
- [ ] **CRITICAL**: Warning dialog should appear!

**Warning Should Say**:
```
*** EXISTING CONTAINER DETECTED ***

An ai-cli container already exists on your system.

This container contains:
  - Your Claude authentication
  - Your configuration and settings
  - Persistent data

RECOMMENDED: Click 'No' and use 'Launch Claude' instead.

Do you want to DELETE the existing container?
```

- [ ] Default button is "No" (safe option)
- [ ] Click "No"
- [ ] Info message appears
- [ ] Setup exits
- [ ] NO success message (correctly cancelled)
- [ ] Existing container still works

**Result**: [ ] Container protection works
**Notes**: _______________________________________________

---

## Phase 8: Cross-Device Testing (If Possible)

### Step 8.1: Test on Different Windows Version

**If you have access to another Windows machine**:

- [ ] Copy AI_Docker_Manager.exe to different machine
- [ ] Ensure Docker Desktop installed
- [ ] Run full setup
- [ ] Verify everything works

**Tested On**:
- Windows Version: _______________
- Docker Version: _______________

**Result**: [ ] Works on different machine
**Notes**: _______________________________________________

---

## FINAL VERIFICATION CHECKLIST

### Critical Bugs Fixed:
- [ ] **Docker compose command doesn't use quoted paths** (docker compose build, not -f "...")
- [ ] **Claude command works on first run** (no permission errors)
- [ ] **.claude directory has correct ownership** (owned by user, not root)
- [ ] **Post-installation validation ensures Claude works** (setup fails if Claude broken)
- [ ] **Cancel button works and confirms during critical steps**
- [ ] **Container protection warns before deletion**

### Documentation Complete:
- [ ] USER_MANUAL.md exists and is comprehensive
- [ ] QUICK_REFERENCE.md exists for quick lookup
- [ ] TESTING_CHECKLIST.md exists for QA
- [ ] FIXES_APPLIED.md documents all changes
- [ ] README.md links to all documentation

### Build System:
- [ ] build_complete_exe.ps1 includes all new files
- [ ] AI_Docker_Complete.ps1 has all placeholders
- [ ] BUILD_NOW.bat works correctly
- [ ] AI_Docker_Manager.exe builds without errors
- [ ] EXE is portable (can be moved anywhere)

### Automated Tests:
- [ ] run_tests.ps1 exists
- [ ] All automated tests pass
- [ ] No critical test failures

---

## READY FOR CEO DEMO?

### Pre-Demo Checklist:
- [ ] All tests above passed
- [ ] No critical bugs found
- [ ] Tested on clean Windows environment
- [ ] Documentation ready (printed or accessible)
- [ ] Demo script prepared
- [ ] Backup plan ready (screenshots/video)

### Demo Materials:
- [ ] AI_Docker_Manager.exe (latest build)
- [ ] USER_MANUAL.md (printed or PDF)
- [ ] QUICK_REFERENCE.md (printed)
- [ ] Clean test laptop ready
- [ ] Docker Desktop installed on demo laptop
- [ ] Anthropic API key ready

**Final Decision**: [ ] READY FOR CEO DEMO

**Tester Signature**: __________________ **Date**: __________

---

## Notes for CEO Demo

### Key Talking Points:
1. **Security**: "AI runs in isolated container, only accesses designated folder"
2. **Simplicity**: "One-click setup, one-click launch, no technical knowledge needed"
3. **Persistence**: "Authenticate once, works forever"
4. **Professional**: "Enterprise-grade with comprehensive documentation"

### Demo Flow (5-10 minutes):
1. Show AI_Docker_Manager.exe on desktop
2. Run First Time Setup (~5 minutes)
3. Show completion message
4. Launch Claude CLI
5. Type `claude` and authenticate
6. Ask Claude to create simple project
7. Show files in Windows Explorer
8. Emphasize security, persistence, simplicity

### Potential CEO Questions:
- **Q**: "Is my data safe?"
  **A**: "Yes, AI only accesses AI_Work folder. Complete isolation."

- **Q**: "What if I want multiple AI tools?"
  **A**: "Easy to add - just modify Dockerfile to install additional tools."

- **Q**: "Do I need to authenticate every time?"
  **A**: "No! Only once. Authentication persists permanently."

- **Q**: "Can I access my work from Windows?"
  **A**: "Yes! AI_Work folder is a regular Windows folder. Full bidirectional sync."

---

**GOOD LUCK WITH THE CEO DEMO! 🚀**
