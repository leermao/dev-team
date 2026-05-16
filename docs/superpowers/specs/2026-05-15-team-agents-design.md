# Team Agents Plugin Design

**Date:** 2026-05-15  
**Status:** Approved  
**Tech Stack:** Node.js Full-Stack (NestJS/Express + React/Vue)

---

## 1. Overview

A Claude Code plugin that provides an 8-agent development team using Skills + Subagents, rendered across a tmux pane grid so the user can monitor every agent simultaneously.

The team operates at DAMO Academy quality standards with robust, secure code as a hard requirement.

**Communication model:**
- **Vertical (primary):** Project Lead ↔ Team Leaders (task assignment / reporting). Team Leaders ↔ their Engineers (task assignment / review / reporting).
- **Horizontal (optional):** Engineers across teams may communicate directly only when necessary (e.g., API handoff). Clear docs and requirements minimize the need for lateral communication.
- **Security Engineer:** Cross-cutting; invoked by any Team Leader during Code Review, reports back to that Leader.

---

## 2. Overall Architecture

```
                      ┌─────────────────────┐
                      │    Project Lead      │
                      │    (main session)    │
                      └──┬──────┬──────┬────┘
               ┌─────────┘      │      └─────────┐
               ↕ tasks/reports  ↕                 ↕
        ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
        │ FE TL        │ │ BE TL        │ │ Test TL      │
        └──────┬───────┘ └──────┬───────┘ └──┬───────┬───┘
               ↕ tasks/review   ↕             ↕       ↕
        ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
        │ FE Dev       │ │ BE Dev       │ │ Test Engineer│
        └──────────────┘ └──────────────┘ └──────────────┘
               ↔ optional only

                    ┌───────────────────────┐
                    │   Security Engineer   │
                    │  (called by any TL    │
                    │   during review)      │
                    └───────────────────────┘
```

**Core mechanisms:**
- **Task tracking:** `TaskCreate / TaskUpdate / TaskList`, states: `pending → in_progress → completed`
- **Communication:** All inter-agent messages via `SendMessage` only — plain text output is invisible to other panes
- **Spawning:** Project Lead spawns Team Leaders; Team Leaders spawn their engineers
- **Security Engineer:** Invoked by a Team Leader, reports result back to that Leader only

---

## 3. tmux Pane Layout

```
┌────────────────────────┬──────────────────────────────┐
│                        │ FE Team Leader │ FE Developer│
│                        ├──────────────────────────────┤
│ Team Lead              │ BE Team Leader │ BE Developer│
│ (main session, 50%)    ├──────────────────────────────┤
│                        │ Test Team Lead │ Test Engineer│
│                        ├──────────────────────────────┤
│                        │ Security Engineer           │
└────────────────────────┴──────────────────────────────┘
```

All 8 panes launch at startup. The main `team-lead` pane occupies the left half of the tmux window. The remaining right half is split into four equal-height rows for FE, BE, Test, and Security. FE, BE, and Test rows are split into equal-width leader/developer panes; Security occupies its full row. The startup flow must verify pane coordinates after applying the layout and report a layout failure instead of falling back to an even grid.

---

## 4. Skill File Structure

```
~/.claude/plugins/team-agents/
├── skills/
│   ├── dev-team.md              # Team startup entry point (/dev-team)
│   ├── project-lead.md          # Project Lead
│   ├── fe-team-leader.md        # Frontend Team Leader
│   ├── fe-developer.md          # Frontend Developer
│   ├── be-team-leader.md        # Backend Team Leader
│   ├── be-developer.md          # Backend Developer
│   ├── test-team-leader.md      # Test Team Leader
│   ├── test-engineer.md         # Test Engineer
│   └── security-engineer.md    # Security Engineer
└── plugin.json                  # Plugin manifest
```

**Skill file format:**

```markdown
---
name: <role-name>
description: <trigger condition>
---

# Role Definition
# Skill Matrix
# Workflow (receive task → execute → self-test → report)
# Output Format Specification
# Collaboration Protocol
```

**Invocation patterns:**

| User Input | Execution |
|------------|-----------|
| `/dev-team` | Launch all 8 agents across tmux panes |
| `/project-lead build a user login module` | Project Lead takes over, splits and dispatches to Team Leaders |
| `/fe-developer implement login form component` | Directly invoke FE Dev, bypass Team Lead |
| `/security-engineer audit this code` | Directly invoke Security Engineer |

---

## 5. Team Startup Flow (`/dev-team`)

### Step 1 — Preconditions

All checks must pass. Fail → stop and tell user what is missing.

1. `test -n "$TMUX"` — must be running inside tmux
2. Read `~/.claude/settings.json` — must have `"teammateMode": "tmux"`
3. `tmux list-panes -a -F '#{pane_id}'` — save output for stale detection

### Step 2 — Stale Detection

Read `~/.claude/teams/dev-team/config.json`:

- File absent → proceed to create
- File present → valid only if ALL of the following are true:
  - Status is active
  - All 7 canonical teammate names exist: `fe-team-leader`, `fe-developer`, `be-team-leader`, `be-developer`, `test-team-leader`, `test-engineer`, `security-engineer`
  - Every teammate has a `tmuxPaneId` present in the live pane list
- Any condition fails → stale, proceed to cleanup

If valid team exists, report status table and stop — do not recreate.

### Step 3 — Cleanup Stale State

Scope: only `dev-team`. Never touch other teams, panes, or user files.

1. Send `shutdown_request` via `SendMessage` to all reachable teammates (ignore failures)
2. Call `TeamDelete` for `dev-team`
3. If `TeamDelete` fails and stale panes are confirmed absent, delete only:
   - `~/.claude/teams/dev-team/`
   - `~/.claude/tasks/dev-team/`

### Step 4 — Create Team

```
TeamCreate:
  team_name: dev-team
  description: DAMO Academy 8-agent full-stack development team
  agent_type: team-lead
```

### Step 5 — Launch 7 Teammates (parallel)

All teammates: `mode: bypassPermissions`, `run_in_background: true`.  
Launch all 7 in a single parallel tool call.

| name | subagent_type | Core prompt rules |
|------|---------------|-------------------|
| `fe-team-leader` | `fe-team-leader` | Split FE tasks via TaskCreate; dispatch to fe-developer; Code Review all FE code; invoke security-engineer during review; report to project-lead via SendMessage |
| `fe-developer` | `fe-developer` | Claim tasks assigned by fe-team-leader; implement; self-test; write component docs; report to fe-team-leader via SendMessage; contact be-developer only when necessary |
| `be-team-leader` | `be-team-leader` | Split BE tasks via TaskCreate; dispatch to be-developer; Code Review all BE code; invoke security-engineer during review; report to project-lead via SendMessage |
| `be-developer` | `be-developer` | Claim tasks assigned by be-team-leader; implement; self-test; write API docs; report to be-team-leader via SendMessage; contact fe-developer only when necessary |
| `test-team-leader` | `test-team-leader` | Plan test coverage; dispatch test-case implementation to test-engineer; review test results; report to project-lead via SendMessage |
| `test-engineer` | `test-engineer` | Design test cases; write automated unit/integration/E2E tests; target coverage ≥ 80%; report to test-team-leader via SendMessage |
| `security-engineer` | `security-engineer` | Wait to be invoked by a Team Leader; run OWASP Top 10 audit; report findings back to invoking Team Leader via SendMessage |

### Step 6 — Ready Signal

Wait for all 7 teammates to send idle/ready. Then output:

```
dev-team 已就绪（8人团队）

| 角色              | Pane             | 状态  |
|-------------------|------------------|-------|
| Project Lead      | 主会话            | ready |
| FE Team Leader    | <paneId>         | ready |
| FE Developer      | <paneId>         | ready |
| BE Team Leader    | <paneId>         | ready |
| BE Developer      | <paneId>         | ready |
| Test Team Leader  | <paneId>         | ready |
| Test Engineer     | <paneId>         | ready |
| Security Engineer | <paneId>         | ready |

现在可以描述开发任务，我作为 Project Lead 负责拆分和分配。
```

---

## 6. Task Lifecycle

```
User → /project-lead "build user login module"
        │
        ▼
  Project Lead
  ├── Output "Requirement Understanding Confirmation" → wait for user approval
  ├── TaskCreate: [FE] Login form component
  ├── TaskCreate: [BE] Login API + JWT
  ├── TaskCreate: [Test] Login module tests
  └── SendMessage → fe-team-leader, be-team-leader, test-team-leader (parallel)
        │
        ├── FE Team Leader
        │   ├── SendMessage → Project Lead: task breakdown for confirmation
        │   ├── TaskCreate sub-tasks: Form UI / State / API integration
        │   ├── SendMessage → fe-developer: task assignment
        │   ├── FE Developer implements → self-test → write component docs
        │   ├── SendMessage → fe-team-leader: completion report
        │   ├── FE Team Leader Code Review: APPROVED or CHANGES REQUIRED
        │   ├── SendMessage → security-engineer: review request
        │   ├── Security Engineer audits → SendMessage → fe-team-leader: findings
        │   ├── TaskUpdate → completed
        │   └── SendMessage → Project Lead: team report
        │
        ├── BE Team Leader  (same pattern as FE)
        │   ├── BE Developer implements → self-test → write API docs
        │   ├── BE Team Leader Code Review + deep security audit
        │   └── SendMessage → Project Lead: team report
        │         [optional: be-developer → SendMessage → fe-developer: API ready]
        │
        └── Test Team Leader
            ├── TaskCreate sub-tasks: unit / integration / E2E / security-input cases
            ├── SendMessage → test-engineer: task assignment
            ├── Test Engineer: automated test cases, coverage ≥ 80%
            ├── Bug found → SendMessage → test-team-leader → SendMessage → responsible TL
            ├── TL routes fix back to their developer
            ├── Dev fixes → re-trigger tests
            └── SendMessage → Project Lead: test report

  Project Lead
  ├── Collect SendMessage reports from all three Team Leaders
  ├── Aggregate: API docs + component docs + test report + security audit
  └── Output final delivery report to user
```

**Horizontal communication rule:** Engineers contact each other only when docs are insufficient — e.g., FE Dev needs to clarify an undocumented API behavior. Otherwise stay in vertical channels.

---

## 7. Agent Behavior Specifications

### Project Lead
- Before splitting: output "Requirement Understanding Confirmation", wait for user approval
- Scale judgment: < 3 files → assign single engineer directly; larger → split into sub-teams
- All dispatch and collection via `SendMessage` to/from Team Leaders only
- Final delivery report: change list + doc links + test coverage + security audit conclusion
- Any Team Leader reports a blocker → immediately pause and notify user

### FE / BE Team Leader (shared)
- Output "Task Breakdown List" → wait for Project Lead confirmation before dispatching
- Dispatch tasks to engineers via `SendMessage` + `TaskUpdate owner`
- Code Review checklist: logical correctness / readability / performance / security / test coverage
- Review conclusion: `APPROVED` or `CHANGES REQUIRED` (with specific change requests)
- `LGTM`-style rubber-stamp approvals are forbidden
- Always invoke Security Engineer before declaring APPROVED

### FE Developer
- Tech stack: React / Vue / Angular / SolidJS / Svelte / JavaScript / TypeScript / HTML / CSS
- Self-test before reporting: local rendering verification
- Report to FE Team Leader: `Completed / Changed files / Self-test results / Outstanding issues`
- Unclear requirements → `SendMessage` to FE Team Leader (not directly to Project Lead)
- Writes component documentation alongside code
- Contact BE Developer directly only when API behavior is undocumented

### BE Developer
- Tech stack: Node.js / Python / Java / C++ / C# / Ruby / PHP / Go
- Self-test before reporting: API curl/unit verification
- Report to BE Team Leader: `Completed / Changed files / Self-test results / Outstanding issues`
- Unclear requirements → `SendMessage` to BE Team Leader
- Writes API documentation (OpenAPI/JSDoc format)
- Contact FE Developer directly only when necessary

### Test Team Leader
- Test breakdown must cover: happy path / boundary values / error paths / security scenarios
- Bug routing: receive from test-engineer → relay to responsible Team Leader via `SendMessage`
- Summary report: coverage percentage + uncovered modules + bug list (fixed/unfixed)

### Test Engineer
- Tech stack: Jest / Mocha / Jasmine / Cypress / Playwright / Puppeteer / Selenium
- Designs test cases before implementation
- Coverage target: ≥ 80%; explicitly report uncovered modules
- Report to Test Team Leader only

### Security Engineer
- Waits to be invoked; does not initiate contact
- Audit checklist: OWASP Top 10 / hardcoded secrets / permission bypass / dependency vulnerabilities
- Output format: `Risk level (Critical/High/Medium/Low) + Location + Fix recommendation`
- Report findings to the Team Leader who invoked it
- Critical/High vulnerabilities block `APPROVED` — no exceptions

---

## 8. Documentation Strategy

- **FE Developer** writes component documentation inline with code
- **BE Developer** writes API documentation (OpenAPI/JSDoc)
- **Project Lead** aggregates all docs into the final delivery report
- Docs are committed alongside code in the same PR

---

## 9. Plugin Manifest (plugin.json)

```json
{
  "name": "team-agents",
  "version": "1.0.0",
  "description": "DAMO Academy-level 8-agent full-stack development team",
  "skills": [
    "skills/dev-team.md",
    "skills/project-lead.md",
    "skills/fe-team-leader.md",
    "skills/fe-developer.md",
    "skills/be-team-leader.md",
    "skills/be-developer.md",
    "skills/test-team-leader.md",
    "skills/test-engineer.md",
    "skills/security-engineer.md"
  ]
}
```

---

## 10. Quality Standards

All agents operate under these non-negotiable standards:

- **Robustness:** Every function handles edge cases and error states explicitly
- **Security:** Security Engineer blocks any Critical/High vulnerability from merging; invoked before every APPROVED verdict
- **Test Coverage:** Automated test coverage ≥ 80% on all new code
- **Code Review:** No code ships without Team Leader `APPROVED` verdict
- **Documentation:** Every API endpoint and reusable component is documented
- **No Assumptions:** Any ambiguity triggers a clarification request up the chain, never a silent assumption
- **Channel discipline:** All inter-agent communication via `SendMessage`; vertical channels are primary; horizontal contact only when docs are insufficient
