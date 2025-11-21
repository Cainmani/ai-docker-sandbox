# How to Write Effective GitHub Issues

## Structure Template

### 1. Title
- **Format**: `[Component] Brief Problem Description - Key Impact`
- **Length**: 50-72 characters ideal
- **Examples**:
  - `Node.js Version Incompatibility and Permission Error When Installing Package`
  - `Loading Bar Hangs at 90% During Docker Build Process`
  - `Claude Code Auto-Update Failed - Manual Intervention Required`

### 2. Issue Body Structure

#### Problem Section
```markdown
## Problem
One-sentence summary of what's wrong. Be specific but concise.
```

#### Environment Section (if applicable)
```markdown
## Environment
- OS: [Windows/Linux/macOS version]
- Node.js: vX.X.X
- npm/yarn: vX.X.X
- Tool version: X.X.X
- Browser: [if relevant]
```

#### Error Details / Current Behavior
```markdown
## Error Details
### 1. First Issue Component
Description of first problem aspect

### 2. Second Issue Component  
Description of second problem aspect

## Current Behavior
1. Step-by-step what happens now
2. Second step
3. Final outcome
```

#### Code Blocks for Errors
Always wrap error messages in code blocks:
````markdown
```
npm ERR! code EACCES
npm ERR! Error: EACCES: permission denied
```
````

#### Expected Behavior
```markdown
## Expected Behavior
Clear description of what SHOULD happen instead.
- Bullet points for multiple expectations
- Be specific about desired outcome
```

#### Steps to Reproduce
```markdown
## Steps to Reproduce
1. First action user takes
2. Second action with any specific parameters
3. Observe the error/issue
```

#### Proposed Solutions / Attempted Solutions
```markdown
## Proposed Solutions
1. **Solution Name** - Brief description
   - Implementation detail
   - Why this would work

## Attempted Solutions  
- [ ] First attempt (checkbox for tracking)
- [ ] Second attempt
- [x] What worked (if anything)
```

#### Priority
```markdown
## Priority
[Critical/High/Medium/Low] - Brief justification

Examples:
- Critical - System completely broken, blocking all users
- High - Blocking key functionality
- Medium - Affects user experience but workaround exists
- Low - Minor inconvenience, cosmetic issue
```

#### Additional Context
```markdown
## Additional Notes
- Related to issue #123
- Only occurs under specific conditions
- Link to relevant documentation
```

## Best Practices

### 1. Be Specific
❌ **Bad**: "Docker doesn't work"  
✅ **Good**: "Docker build hangs at 90% progress during compose phase"

### 2. Include Actual Error Messages
Always copy-paste the exact error, don't paraphrase.

### 3. Use Formatting
- **Bold** for emphasis
- `code formatting` for commands, file names, versions
- > Blockquotes for citations

### 4. Organize with Headers
Use `##` for main sections, `###` for subsections

### 5. Provide Context
- What were you trying to achieve?
- When did this start happening?
- Has it ever worked before?

### 6. Be Objective
❌ "This stupid thing is broken"  
✅ "The component fails with error X under condition Y"

### 7. One Issue Per Issue
Don't combine multiple unrelated problems in one issue.

## Quick Template

```markdown
## Problem
[What's broken in one sentence]

## Environment
- Node.js: vX.X.X
- OS: [Your OS]

## Current Behavior
[What happens now]

## Expected Behavior
[What should happen]

## Steps to Reproduce
1. [First step]
2. [Second step]
3. [See error]

## Error Output
```
[Paste actual error here]
```

## Possible Solution
[Any ideas for fixing]

## Priority
[High/Medium/Low] - [Why]
```

## Examples of Good vs Bad Issues

### ❌ Bad Issue Example
**Title**: "help plz urgent!!!"  
**Body**: "docker broken cant install anything"

### ✅ Good Issue Example
**Title**: "Docker Build Hangs at 90% During Compose Phase"  
**Body**: Uses structured format with all sections properly filled out

## Issue Examples

### Example 1: Installation Error
```markdown
## Title
Node.js Version Incompatibility and Permission Error When Installing @google/gemini-cli

## Problem
Unable to install @google/gemini-cli due to Node.js version requirements and permission errors.

## Environment
- Current Node.js: v18.19.1
- Current npm: 9.2.0
- OS: Linux (Docker container)

## Error Details
### 1. Engine Incompatibility
Multiple packages require Node.js >=20, but current version is 18.19.1

### 2. Permission Error
```
npm ERR! code EACCES
npm ERR! Error: EACCES: permission denied, mkdir '/usr/local/lib/node_modules/@google'
```

## Steps to Reproduce
1. Run npm install -g @google/gemini-cli with Node.js v18.19.1
2. Observe engine warnings and permission error

## Expected Behavior
Package should install successfully with proper permissions.

## Proposed Solutions
1. Update Node.js to version 20 or higher
2. Fix permissions using sudo or npm configuration

## Priority
High - Blocking installation of required CLI tool
```

### Example 2: UI/UX Issue
```markdown
## Title
Loading Bar Hangs at 90% During Docker Compose Build - Doesn't Reflect Variable Build Time

## Problem
The loading bar during Docker build process reaches 90% and hangs indefinitely while waiting for docker compose to complete, giving users a false impression that the process is stuck.

## Current Behavior
1. Loading bar progresses normally from 0-90%
2. Hangs at 90% for variable amount of time
3. Remains at 90% until docker compose build completes
4. No indication to user that process is still running normally

## Expected Behavior
- Loading bar should accurately reflect the build progress
- Should indicate that Docker build time is variable
- Provide feedback that the process is still active (not frozen)

## Suggested Improvements
1. Indeterminate Progress Indicator after 90%
2. Better Progress Estimation
3. Verbose Output Option

## Priority
Medium - Affects user experience but doesn't break functionality
```

## Checklist Before Submitting

- [ ] Searched existing issues for duplicates
- [ ] Included version numbers
- [ ] Added steps to reproduce
- [ ] Included actual error messages
- [ ] Used clear, descriptive title
- [ ] Added appropriate labels
- [ ] Assigned priority level
- [ ] Checked spelling and grammar
- [ ] Added screenshots if relevant
- [ ] Mentioned related issues with #

## Tips for Maintainers

When creating issues, remember that the person reading it:
- Might not have your context
- Needs to reproduce the problem
- Wants to understand the impact
- Needs enough detail to prioritize

Write issues as if you're explaining to someone who just joined the project!

---

*This guide helps create consistent, well-structured GitHub issues that are easy for developers to understand and act upon.*