# Team Agents Plugin Design

**Date:** 2026-05-15  
**Status:** Approved  
**Tech Stack:** Node.js Full-Stack (NestJS/Express + React/Vue)

---

## 1. Overview

A Claude Code plugin that provides a multi-agent development team using Skills + Subagents. The team operates at DAMO Academy quality standards with robust, secure code as a hard requirement.

The team consists of 9 agents organized in a two-tier hierarchy with a cross-cutting Security Engineer. All agents can communicate laterally via `SendMessage`, challenge each other's conclusions, and build on each other's work.

---

## 2. Overall Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Project Lead                       │
│  (Main Skill, single entry point)                   │
└──────────┬────────────────┬──────────────────┬───────┘
           │                │                  │
    ┌──────▼──────┐  ┌──────▼──────┐  ┌───────▼──────┐
    │ FE Team     │  │ BE Team     │  │ Test Team    │
    │ Leader      │  │ Leader      │  │ Leader       │
    │ (Subagent)  │  │ (Subagent)  │  │ (Subagent)   │
    └──────┬──────┘  └──────┬──────┘  └──┬────────┬──┘
           │                │             │        │
    ┌──────▼──────┐  ┌──────▼──────┐ ┌───▼──┐ ┌───▼────┐
    │ FE Dev      │  │ BE Dev      │ │ Test │ │ Test   │
    │ (Subagent)  │  │ (Subagent)  │ │ Auto │ │ Manual │
    └─────────────┘  └─────────────┘ └──────┘ └────────┘
                                          ↕ (peer review)
                              ┌───────────────────────┐
                              │   Security Engineer   │
                              │   (cross-cutting,     │
                              │    any Leader calls)  │
                              └───────────────────────┘
```

**Core mechanisms:**
- **Task tracking:** Native Claude Code `TaskCreate / TaskUpdate / TaskList` tools, states: `pending → in_progress → completed`
- **Agent spawning:** Project Lead spawns Team Leaders via `Agent` tool; Team Leaders spawn engineers via `Agent` tool
- **Lateral communication:** Engineers use `SendMessage` to share info, challenge conclusions, and notify of bugs
- **Security Engineer:** Not owned by any sub-team; any Team Leader may invoke it during Code Review

---

## 3. Skill File Structure

```
~/.claude/plugins/team-agents/
├── skills/
│   ├── project-lead.md          # Project Lead
│   ├── fe-team-leader.md        # Frontend Team Leader
│   ├── fe-developer.md          # Frontend Developer
│   ├── be-team-leader.md        # Backend Team Leader
│   ├── be-developer.md          # Backend Developer
│   ├── test-team-leader.md      # Test Team Leader
│   ├── test-engineer-auto.md    # Automated Test Engineer
│   ├── test-engineer-manual.md  # Manual Test Engineer
│   └── security-engineer.md    # Security Engineer
└── plugin.json                  # Plugin manifest
```

**Skill file format:**

```markdown
---
name: <role-name>
description: <trigger condition — when to invoke this role>
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
| `/project-lead build a user login module` | Project Lead takes over, auto-splits and spawns sub-teams |
| `/fe-developer implement login form component` | Directly invokes FE Dev, bypasses Team Lead |
| `/security-engineer audit this code` | Directly invokes Security Engineer |

---

## 4. Task Lifecycle

```
User → /project-lead "build user login module"
        │
        ▼
  Project Lead
  ├── Output "Requirement Understanding Confirmation" → wait for user approval
  ├── TaskCreate: [FE] Login form component
  ├── TaskCreate: [BE] Login API + JWT
  ├── TaskCreate: [Test] Login module tests
  └── Spawn three Team Leader subagents in parallel
        │
        ├── FE Team Leader
        │   ├── Output task breakdown list → user confirms
        │   ├── Sub-tasks: Form UI / State management / API integration
        │   ├── TaskUpdate → in_progress
        │   ├── Spawn FE Developer subagent
        │   ├── FE Dev completes → submit code + write component docs
        │   ├── FE Team Leader Code Review (APPROVED or CHANGES REQUIRED)
        │   ├── Invoke Security Engineer for initial security review
        │   └── TaskUpdate → completed, report to Project Lead
        │
        ├── BE Team Leader
        │   ├── Output task breakdown list → user confirms
        │   ├── Sub-tasks: Routes / Business logic / Database / JWT
        │   ├── Spawn BE Developer subagent
        │   ├── BE Dev completes → submit code + write API docs
        │   ├── BE Team Leader Code Review (APPROVED or CHANGES REQUIRED)
        │   ├── Invoke Security Engineer for deep security audit
        │   └── TaskUpdate → completed, report to Project Lead
        │
        └── Test Team Leader
            ├── Sub-tasks: Unit tests / Integration tests / Manual test cases
            ├── Spawn Test Auto + Test Manual subagents
            ├── Test Auto: Jest unit tests + Cypress E2E, coverage ≥ 80%
            ├── Test Manual: Edge cases + UX validation
            ├── Bug found → SendMessage to responsible FE/BE Dev directly
            ├── Dev fixes → re-trigger tests
            └── TaskUpdate → completed, report to Project Lead

  Project Lead
  ├── Collect reports from all three teams
  ├── Aggregate: API docs + component docs + test report + security audit
  └── Output final delivery report to user
```

**Lateral communication rules:**
- BE Dev finishes API → `SendMessage` to FE Dev that interface is ready
- Test Auto finds Bug → `SendMessage` directly to responsible Dev (no Leader relay)
- Security Engineer finds vulnerability → notify Team Leader + Dev + Project Lead simultaneously

---

## 5. Agent Behavior Specifications

### Project Lead
- Before splitting: output "Requirement Understanding Confirmation", wait for user approval
- Scale judgment: < 3 files → assign single engineer directly; larger → split into sub-teams
- Final delivery report must include: change list, doc links, test coverage, security audit conclusion
- Any sub-team reports a blocker → immediately pause and notify user

### FE / BE Team Leader (shared)
- Must output "Task Breakdown List" for user confirmation before dispatching
- Code Review checklist: logical correctness / readability / performance / security / test coverage
- Review conclusion: `APPROVED` or `CHANGES REQUIRED` (with specific change requests)
- `LGTM`-style rubber-stamp approvals are forbidden

### FE Developer
- Tech stack: React / Vue / Angular / SolidJS / Svelte / JavaScript / TypeScript / HTML / CSS
- Self-test before submission: local rendering verification
- Completion report format: `Completed / Changed files / Self-test results / Outstanding issues`
- Unclear requirements → `SendMessage` to Project Lead, no self-assumed interpretations
- Writes component documentation

### BE Developer
- Tech stack: Node.js / Python / Java / C++ / C# / Ruby / PHP / Go
- Self-test before submission: API curl verification
- Completion report format: `Completed / Changed files / Self-test results / Outstanding issues`
- Unclear requirements → `SendMessage` to Project Lead, no self-assumed interpretations
- Writes API documentation

### Test Team Leader
- Test breakdown must cover: happy path / boundary values / error paths / security scenarios
- Summary report must include: coverage percentage + uncovered modules + bug list (fixed/unfixed)

### Test Engineer (Automated)
- Tech stack: Jest / Mocha / Jasmine / Cypress / Playwright / Puppeteer / Selenium
- Writes unit tests + integration tests for frontend and backend
- Coverage target: ≥ 80%
- Reports uncovered modules explicitly

### Test Engineer (Manual)
- Focuses on edge cases, UX flows, and scenarios hard to automate
- Good communication skills; works with FE/BE devs to understand intent
- Outputs structured defect reports: `Issue / Steps to reproduce / Expected / Actual / Severity`

### Security Engineer
- Audit checklist: OWASP Top 10 / hardcoded secrets / permission bypass / dependency vulnerabilities
- Output format: `Risk level (Critical/High/Medium/Low) + Location + Fix recommendation`
- Critical/High vulnerabilities block merge — no exceptions

---

## 6. Documentation Strategy

- **FE Developer** writes component documentation inline
- **BE Developer** writes API documentation (format: OpenAPI/JSDoc)
- **Project Lead** aggregates all docs into the final delivery report
- Docs are committed alongside code in the same PR

---

## 7. Plugin Manifest (plugin.json)

```json
{
  "name": "team-agents",
  "version": "1.0.0",
  "description": "DAMO Academy-level multi-agent development team",
  "skills": [
    "skills/project-lead.md",
    "skills/fe-team-leader.md",
    "skills/fe-developer.md",
    "skills/be-team-leader.md",
    "skills/be-developer.md",
    "skills/test-team-leader.md",
    "skills/test-engineer-auto.md",
    "skills/test-engineer-manual.md",
    "skills/security-engineer.md"
  ]
}
```

---

## 8. Quality Standards

All agents operate under these non-negotiable standards:

- **Robustness:** Every function handles edge cases and error states explicitly
- **Security:** Security Engineer blocks any Critical/High vulnerability from merging
- **Test Coverage:** Automated test coverage ≥ 80% on all new code
- **Code Review:** No code ships without Team Leader `APPROVED` verdict
- **Documentation:** Every API endpoint and reusable component is documented
- **No Assumptions:** Any ambiguity triggers a clarification request, never a silent assumption
