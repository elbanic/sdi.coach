# sdi.coach Project

## Language Preferences

- **Conversation**: Always respond in Korean (한국어)
- **Documentation & Code**: Write in English by default (unless explicitly requested otherwise)

## Git Commit Rules

- **Do NOT add Co-Authored-By** line in commit messages
- Before committing or pushing, ALWAYS review the code to ensure you're not uploading any security-related credentials.


## Coding Principals

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style.
- If you notice unrelated dead code, mention it - don't delete it.

The test: Every changed line should trace directly to the user's request.

### 4. Code Change

All implementation MUST be approved by the user before starting.
- When you find an issue or plan a change, describe the problem and proposed solution first to user. Do NOT JUST start writing code until the user explicitly says to proceed.
- Analyze and report to user before implementing. If you find an issue, verify the root cause with real-world evidence (logs, API calls, test output) before proposing a fix.

---

## Project Documentation

### File Structure & Relationships

```
sdi.coach/
├── CLAUDE.md          ← You are here (Project instructions & TDD workflow)
├── PRD.md             ← Product requirements, architecture, type definitions
├── PLAN.md            ← Implementation plan (7 phases, parallelization strategy)
├── TODO.md            ← Task checklist with [P]/[S] parallelization markers
│
├── .claude/
│   ├── agents/        ← TDD agent definitions
│   │   ├── test-architect.md
│   │   ├── implementer.md
│   │   ├── code-reviewer.md
│   │   └── refactorer.md
│   └── settings.local.json
│
├── Sources/SDICoach/  ← Swift CLI ✅ implemented
├── backend/           ← Python backend ✅ implemented
└── scripts/           ← Launcher scripts ✅ implemented
```

### Document Relationships

```
┌─────────────┐     defines      ┌─────────────┐
│   PRD.md    │────────────────►│  PLAN.md    │
│ (What/Why)  │                 │ (How/When)  │
└─────────────┘                 └──────┬──────┘
                                       │
                                       │ breaks down into
                                       ▼
┌─────────────┐     guides      ┌─────────────┐
│  CLAUDE.md  │────────────────►│  TODO.md    │
│ (Workflow)  │                 │ (Tasks)     │
└─────────────┘                 └──────┬──────┘
       │                               │
       │ defines                       │ executed by
       ▼                               ▼
┌─────────────┐                 ┌─────────────┐
│   Agents    │────────────────►│    Code     │
│ (TDD Loop)  │   implements    │ (Swift/Py)  │
└─────────────┘                 └─────────────┘
```

### Key Documents

| Document | Purpose | When to Reference |
|----------|---------|-------------------|
| `PRD.md` | Architecture, types, IPC protocol | Design decisions, type definitions |
| `PLAN.md` | 7-phase implementation plan | Understanding phase dependencies |
| `TODO.md` | Task checklist with parallelization | Tracking progress, finding next task |
| `CLAUDE.md` | TDD workflow, agent usage | How to implement tasks |

---

## Custom Subagents (TDD Multi-Agent System)

This project uses a 4-agent TDD feedback loop. Agents are defined in `.claude/agents/`.

### Agent Overview

| Agent | TDD Phase | Purpose | Tools |
|-------|-----------|---------|-------|
| 🧪 `test-architect` | RED | Design & write failing tests | Read, Write, Glob, Grep, Bash |
| ⚙️ `implementer` | GREEN | Write minimal code to pass tests | Read, Write, Edit, Glob, Grep, Bash |
| 🔍 `code-reviewer` | Quality Gate | Review code, approve/reject | Read, Glob, Grep, Bash (read-only) |
| ✨ `refactorer` | REFACTOR | Improve code without changing behavior | Read, Write, Edit, Glob, Grep, Bash |

### TDD Feedback Loop

```
┌─────────────────────────────────────────────────────────────┐
│                    TDD Cycle Flow                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   🧪 test-architect                                         │
│      │ "Write failing tests for [component]"                │
│      │                                                      │
│      ▼ (failing tests)                                      │
│   ⚙️ implementer                                            │
│      │ "Make these tests pass"                              │
│      │                                                      │
│      ▼ (implementation)                                     │
│   🔍 code-reviewer                                          │
│      │ "Review this implementation"                         │
│      │                                                      │
│      ├─── REJECT → back to implementer                      │
│      │                                                      │
│      ▼ APPROVE                                              │
│   ✨ refactorer                                             │
│      │ "Improve this code"                                  │
│      │                                                      │
│      ▼ (edge cases found)                                   │
│   🧪 test-architect (next cycle)                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Usage Examples

```bash
# Start TDD cycle for a new component
> Use test-architect to write property tests for PromptAnalyzer based on Properties 2-5

# After tests are written
> Use implementer to make these tests pass

# After implementation
> Use code-reviewer to review the PromptAnalyzer implementation

# After approval
> Use refactorer to improve the PromptAnalyzer code

# Or invoke directly with Task tool
> @test-architect Write property tests for confidence scoring (Property 12)
```

### When to Use Each Agent

| Scenario | Agent to Use |
|----------|--------------|
| Starting new feature | test-architect |
| Tests exist but failing | implementer |
| Implementation complete | code-reviewer |
| Code approved, needs cleanup | refactorer |
| Bug found in production | test-architect (write test first!) |
| Performance issue | refactorer |

---

## TDD Workflow Protocol

### Prompt Template for Task Implementation

Use this template when requesting task implementation:

```
Implement Task [X.Y]: [Task Name]

References:
- Architecture: PRD.md (types, IPC protocol, component specs)
- Implementation Plan: PLAN.md (phase details, dependencies)
- Task List: TODO.md (find task by ID)

TDD Loop Rules:
1. Execute: test-architect → implementer → code-reviewer → refactorer
2. MAX 3 ITERATIONS per cycle
3. If unresolved after 3 loops: STOP and report to user
4. On task completion: ASK user confirmation before updating TODO.md

Acceptance Criteria:
- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] All tests pass
- [ ] Code review approved
```

### Compact Version

```
Implement Task 1.2.1: Asyncio Unix socket server

TDD Loop (max 3 iterations):
🧪 → ⚙️ → 🔍 → ✨ → (repeat if needed)

STOP conditions:
- 3 iterations without resolution → ask user
- Unclear requirements → ask user
- Task complete → confirm with user, then update TODO.md

References: PLAN.md (Phase 1.2), PRD.md (IPC protocol)
```

### Loop Execution Rules

| Iteration | Action |
|-----------|--------|
| 1st | Normal TDD cycle |
| 2nd | Focus on specific failing tests |
| 3rd | Final attempt with simplified approach |
| 4th+ | **STOP** - Report status and ask user for guidance |

### Stop and Report Format

When stopping after 3 iterations:

```
## TDD Loop Status Report

### Task: [X.Y] [Task Name]
### Iterations Completed: 3

### Current State:
- Tests passing: X/Y
- Failing tests: [list]
- Blocker: [specific issue]

### Attempted Solutions:
1. [Approach 1] - Result: [outcome]
2. [Approach 2] - Result: [outcome]
3. [Approach 3] - Result: [outcome]

### Options for User:
A) [Suggested direction 1]
B) [Suggested direction 2]
C) Provide additional guidance

Awaiting your input before continuing.
```

### Task Completion Protocol

When task is complete:

```
## Task Completion: [X.Y] [Task Name]

### Summary:
- All tests passing: ✅
- Code review: APPROVED
- Refactoring: Complete

### Files Created/Modified:
- [file1.ts] - [purpose]
- [file2.ts] - [purpose]

### Properties Validated:
- Property [N]: ✅
- Property [M]: ✅

---
**Ready to mark as complete?**
Reply "yes" to update tasks.md, or provide feedback.
```

After user confirms, update `TODO.md`:
- Change `- [ ]` to `- [x]` for completed task

### Parallel Task Implementation

For parallelizable tasks (marked `[P]` in TODO.md):

```
Implement IN PARALLEL:
- Task 1.2.1 [Python]: Asyncio Unix socket server
- Task 1.3.1 [Swift]: Unix socket client connection

Each task follows TDD Loop (max 3 iterations).
Report completion for ALL tasks together.
I will confirm before updating TODO.md.
```

### Quick Reference Commands

| Command | Purpose |
|---------|---------|
| `Implement Task X.Y.Z` | Start single task with TDD loop |
| `Implement Tasks X.Y, X.Z in parallel` | Start parallel [P] tasks |
| `Continue from iteration N` | Resume stopped loop |
| `Skip to refactorer` | After manual fix, continue cycle |
| `Mark Task X.Y.Z complete` | Force complete (updates TODO.md) |
| `Show TODO.md status` | Check overall progress |

---

## Troubleshooting

### SwiftPM Lock Conflict

If you encounter this error during build or test:
```
Another instance of SwiftPM (PID: XXXXX) is already running using '.build'
```

**Solution**: Kill the zombie process and remove the lock file:
```bash
pkill -9 -f swift; rm -f .build/.lock
```

Then retry the build/test command.

---

## External Documentation

| Component | Documentation URL | Used For |
|-----------|-------------------|----------|
| **Strands Agents** | https://strandsagents.com/latest/documentation/docs/ | AI Agents (Interviewer, Feedback) with Bedrock |

---