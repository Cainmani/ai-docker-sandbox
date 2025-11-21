# AI Docker Manager - Testing Checklist

## Pre-CEO Demo Testing Checklist

**Purpose**: Ensure AI_Docker_Manager.exe works flawlessly across different Windows environments before CEO demo.

**Date**: ________________
**Tester**: ________________
**Test Device**: ________________

---

## Test Environment Requirements

- [x] **Clean Windows 10 or 11 machine** (or fresh VM)
- [x] **Docker Desktop installed** and running
- [x] **Internet connection** active
- [x] **At least 10GB free disk space**
- [x] **Administrator privileges** available

---

## Phase 1: Pre-Installation Checks

### 1.1 Docker Desktop Verification
- [x] Docker Desktop is installed
- [x] Docker Desktop icon shows in system tray
- [x] Docker Desktop is running
- [x] Command works: `docker --version`
- [x] Command works: `docker info`

**Notes**: _______________________________________________

### 1.2 File Preparation
- [x] AI_Docker_Manager.exe is available
- [x] Place AI_Docker_Manager.exe on **Desktop** (test portability)
- [x] File size is approximately 174KB
- [x] Double-click opens (no Windows Defender blocks)

**Notes**: _______________________________________________

---

## Phase 2: First Time Setup

### 2.1 Launch Setup Wizard
- [ ] Double-click AI_Docker_Manager.exe
- [ ] Menu appears with two buttons
- [ ] Click "**1. FIRST TIME SETUP**"
- [ ] Setup wizard GUI opens (950x700px)
- [ ] Console window opens showing logging
- [ ] Pre-flight checks run automatically

**Console Output to Watch For**:
- [ ] `[CHECK 1/3] Checking shell script line endings...`
- [ ] `[CHECK 2/3] Checking for existing containers...`
- [ ] `[CHECK 3/3] Docker image status...`
- [ ] `[PRE-FLIGHT] All automatic checks complete!`

**Notes**: _______________________________________________

### 2.2 Page 1: Welcome
- [ ] Welcome page displays correctly
- [ ] Text is readable (Matrix green on dark background)
- [ ] Click "**Next**"

**Notes**: _______________________________________________

### 2.3 Page 2: Credentials
- [ ] Enter username: `testuser`
- [ ] Enter password: `TestPass123!`
- [ ] Enter confirm password: `TestPass123!`
- [ ] Click "**Next**"

**Test password validation**:
- [ ] Empty fields rejected
- [ ] Mismatched passwords rejected

**Notes**: _______________________________________________

### 2.4 Page 3: Workspace Location
- [ ] Click "**Browse**"
- [ ] Select `C:\Users\<YourName>\Documents`
- [ ] Path shows in textbox
- [ ] Click "**Next**"

**Console Output to Watch For**:
- [ ] `[INFO] Creating workspace at: C:\Users\...\Documents\AI_Work`
- [ ] `[SUCCESS] AI_Work directory created` (or already exists message)
- [ ] `[SUCCESS] .env file created`

**Verify**:
- [ ] AI_Work folder created in selected location
- [ ] .env file exists in AppData: `%LOCALAPPDATA%\AI_Docker_Manager\.env`

**Notes**: _______________________________________________

### 2.5 Page 4: Docker Check
- [ ] Status shows "Docker is running"
- [ ] Click "**Next**"

**If Docker not running**:
- [ ] Error message appears
- [ ] Start Docker Desktop manually
- [ ] Click "**Retry Check**"
- [ ] Status updates to "Docker is running"

**Notes**: _______________________________________________

### 2.6 Page 5: Building Container
**This is the critical step - watch console closely!**

- [ ] Progress bar starts animating
- [ ] Console shows: `[INFO] Building Docker image...`
- [ ] **CRITICAL**: Console shows: `[EXEC] docker compose build` (NOT `docker compose -f "C:/..."`)
- [ ] Build completes successfully
- [ ] Console shows: `[SUCCESS] Docker image built`
- [ ] Console shows: `[INFO] Starting container`
- [ ] **CRITICAL**: Console shows: `[EXEC] docker compose up -d` (NOT with quotes)
- [ ] Container starts successfully
- [ ] Console shows: `[SUCCESS] Container started`
- [ ] Wait completes (5 seconds)
- [ ] Container verified running

**Timing**:
- Build time: ________ minutes
- Total time: ________ minutes

**Notes**: _______________________________________________

### 2.7 Page 6: Installing Claude CLI
**Another critical step - npm must succeed!**

- [ ] Progress bar animates
- [ ] Console shows: `[INFO] Installing npm package @anthropic-ai/claude-code`
- [ ] Console shows: `[INFO] This step requires internet connection`
- [ ] npm install completes (1-2 minutes)
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

**Timing**:
- npm install time: ________ minutes

**Notes**: _______________________________________________

### 2.8 Page 7: Setup Complete
- [ ] Completion page displays
- [ ] Instructions mention first-time authentication
- [ ] Instructions are clear and readable
- [ ] Click "**Finish**"
- [ ] Wizard closes
- [ ] Success message appears (not error message!)

**Notes**: _______________________________________________

---

## Phase 3: First Launch

### 3.1 Launch AI Workspace
- [ ] Double-click AI_Docker_Manager.exe again
- [ ] Click "**2. LAUNCH AI WORKSPACE**"
- [ ] Launcher GUI opens
- [ ] Click "**Launch Workspace Shell**"
- [ ] Terminal window opens (Windows Terminal or cmd)
- [ ] Prompt shows: `testuser@ai-cli:/workspace$` (NOT root@)

**Notes**: _______________________________________________

### 3.2 Verify Environment
Run these commands in the terminal:

```bash
# Check user
whoami
# Expected: testuser

# Check location
pwd
# Expected: /workspace

# Check sudo works without password
sudo whoami
# Expected: root (no password prompt!)

# Check files
ls -la
# Expected: Empty or shows AI_Work contents

# Check claude command exists
which claude
# Expected: /usr/local/bin/claude

# Verify claude is executable
file /usr/local/bin/claude
# Expected: shell script, executable
```

**Results**:
- [ ] whoami returns correct username
- [ ] pwd returns /workspace
- [ ] sudo works without password
- [ ] claude command found
- [ ] claude is executable

**Notes**: _______________________________________________

### 3.3 First Run of Claude CLI
**This is THE critical test!**

In the terminal, type:
```bash
claude
```

**Expected Behavior**:
- [ ] Claude CLI starts (no "command not found" error)
- [ ] **First time**: Authentication prompt appears
- [ ] Follow authentication prompts
- [ ] Authentication succeeds
- [ ] Claude CLI is ready for use

**If authentication required**:
- [ ] Prompts for Anthropic API key or login
- [ ] Enter test credentials
- [ ] Authentication persists (saved in Docker volume)

**If command fails**:
- [ ] Note exact error message: ____________________________________
- [ ] Check wrapper: `cat /usr/local/bin/claude`
- [ ] Check npm package: `npm list -g @anthropic-ai/claude-code`

**Notes**: _______________________________________________

### 3.4 Test Basic Claude Functionality
After Claude starts:

- [x] Claude responds to simple query
- [x] Can read files in /workspace
- [x] Can create files in /workspace
- [x] Created files appear in Windows AI_Work folder

**Test Commands**:
```bash
# Create test file
echo "Hello from Docker" > /workspace/test.txt

# Check from Claude
# Ask Claude: "What files are in the workspace?"
# Ask Claude: "Read the test.txt file"
```

**Results**:
- [x] Files sync to Windows correctly
- [x] Claude can read/write files
- [x] No permission errors

**Notes**: _______________________________________________

---

## Phase 4: Persistence Testing

### 4.1 Exit and Relaunch
- [ ] Type `exit` to exit Claude
- [ ] Type `exit` to exit terminal
- [ ] Terminal closes
- [ ] Double-click AI_Docker_Manager.exe
- [ ] Click "**2. LAUNCH AI WORKSPACE**"
- [ ] Terminal opens again
- [ ] Type `claude`
- [ ] **CRITICAL**: Claude starts WITHOUT asking for authentication again!

**Results**:
- [ ] Authentication persisted
- [ ] No re-authentication required
- [ ] Claude works immediately

**Notes**: _______________________________________________

### 4.2 File Persistence
- [ ] Previous test.txt file still exists in /workspace
- [ ] Previous test.txt file visible in Windows AI_Work folder
- [ ] Can create new files
- [ ] New files appear in both locations

**Notes**: _______________________________________________

### 4.3 Container Restart
```powershell
# In PowerShell (admin)
docker stop ai-cli
docker start ai-cli
```

- [ ] Container stops successfully
- [ ] Container starts successfully
- [ ] Launch AI Workspace again
- [ ] Everything still works
- [ ] Authentication still persisted

**Notes**: _______________________________________________

---

## Phase 5: Error Handling Testing

### 5.1 Docker Not Running Scenario
- [ ] Stop Docker Desktop
- [ ] Try to launch AI Workspace
- [ ] Error message appears: "Docker is not running"
- [ ] Message is clear and helpful
- [ ] Start Docker Desktop
- [ ] Try again - works

**Notes**: _______________________________________________

### 5.2 Container Protection
- [ ] Run First Time Setup AGAIN (intentionally)
- [ ] **CRITICAL**: Warning dialog appears!
- [ ] Warning mentions existing container
- [ ] Warning mentions authentication loss
- [ ] Default button is "**No**" (safe option)
- [ ] Click "**No**"
- [ ] Setup cancels (does not continue)
- [ ] No error message appears (just info message)
- [ ] Existing container still works

**Notes**: _______________________________________________

---

## Phase 6: Cross-Device Testing

### 6.1 Different Windows Versions
Test on:
- [ ] Windows 10 (version: _______)
- [ ] Windows 11 (version: _______)

**Results**: _______________________________________________

### 6.2 Different Path Scenarios
Test with AI_Work in different locations:
- [ ] C:\Users\<Name>\Documents
- [ ] C:\Projects
- [ ] D:\ drive
- [ ] Path with spaces: C:\My Projects\AI Work

**Results**: _______________________________________________

### 6.3 Portable EXE Test
- [ ] Move AI_Docker_Manager.exe to Desktop
- [ ] Run - works
- [ ] Move to Downloads folder
- [ ] Run - works
- [ ] Move to USB drive
- [ ] Run - works

**All config stays in AppData, EXE location doesn't matter**

**Notes**: _______________________________________________

---

## Phase 7: User Experience Testing

### 7.1 Documentation Clarity
- [ ] USER_MANUAL.md is clear and understandable
- [ ] QUICK_REFERENCE.md covers common tasks
- [ ] Instructions match actual behavior
- [ ] No confusing technical jargon for non-technical users

**Notes**: _______________________________________________

### 7.2 Error Messages
Review all error messages encountered:
- [ ] Error messages are clear
- [ ] Error messages provide solutions
- [ ] No cryptic technical errors shown to user

**Notes**: _______________________________________________

### 7.3 Timing Expectations
- First time setup: ________ minutes
- Daily launch: ________ seconds
- Claude start: ________ seconds

**Are timings acceptable?**: _______________________________________________

---

## Phase 8: CEO Demo Preparation

### 8.1 Pre-Demo Checklist
- [ ] Clean test device available
- [ ] Docker Desktop installed and updated
- [ ] Internet connection verified
- [ ] Anthropic API key ready
- [ ] USER_MANUAL.md printed or available
- [ ] QUICK_REFERENCE.md printed or available
- [ ] AI_Docker_Manager.exe ready on Desktop

**Notes**: _______________________________________________

### 8.2 Demo Script
1. [ ] Show AI_Docker_Manager.exe on Desktop
2. [ ] Double-click → Main menu appears
3. [ ] Click "First Time Setup"
4. [ ] Walk through wizard (5 minutes)
5. [ ] Show completion message
6. [ ] Double-click exe again
7. [ ] Click "Launch AI Workspace"
8. [ ] Terminal opens
9. [ ] Type `claude`
10. [ ] Authenticate (first time)
11. [ ] Show Claude responding to queries
12. [ ] Show files in Windows File Explorer
13. [ ] Create project with Claude
14. [ ] Show project files in AI_Work folder

**Demo duration**: ________ minutes

**Notes**: _______________________________________________

---

## Critical Issues Found

### Blocker Issues (Must Fix Before CEO Demo)
1. _______________________________________________
2. _______________________________________________
3. _______________________________________________

### Minor Issues (Nice to Fix)
1. _______________________________________________
2. _______________________________________________
3. _______________________________________________

---

## Sign-Off

### Tester
- [ ] All critical tests passed
- [ ] No blocker issues found
- [ ] Documentation is accurate
- [ ] Ready for CEO demo

**Tester Signature**: __________________ **Date**: __________

### Reviewer
- [ ] Reviewed test results
- [ ] Verified critical functionality
- [ ] Approved for CEO demo

**Reviewer Signature**: __________________ **Date**: __________

---

## Notes for CEO Demo

**Key Points to Emphasize**:
- Security: AI runs in isolated container, can't access personal files
- Simplicity: One-click setup, one-click launch
- Persistence: Authentication saved, work files always accessible
- Professional: Clean GUI, clear instructions, no technical knowledge required

**Potential Questions & Answers**:
Q: Is my data safe?
A: Yes, AI only has access to AI_Work folder, nothing else.

Q: What if I want to use multiple AI tools?
A: We can easily add more tools to the container.

Q: Can I access my work from Windows?
A: Yes! AI_Work folder is a regular Windows folder.

Q: Do I need to authenticate every time?
A: No! Only once - authentication persists permanently.

---

**GOOD LUCK WITH THE CEO DEMO! 🚀**
