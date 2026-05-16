---
name: dev-team
description: Use when the user runs /dev-team or asks to start the development team. Starts an 8-agent DAMO Academy development team in tmux panes.
user-invocable: true
---

# dev-team - Team Startup

## Purpose

`/dev-team` is a team bootstrap command, not a coding task.

It creates the fixed team `dev-team` with 8 roles:

| Role | Member | Responsibility |
|---|---|---|
| team-lead | Current Claude Code main session | Plan, split work, assign tasks, coordinate, verify, and make final decisions |
| fe-team-leader | `fe-team-leader` teammate | Plan frontend work, review frontend code, coordinate `fe-developer` |
| fe-developer | `fe-developer` teammate | Implement frontend work, self-test, report changes |
| be-team-leader | `be-team-leader` teammate | Plan backend work, review backend code, coordinate `be-developer` |
| be-developer | `be-developer` teammate | Implement backend work, self-test, report changes |
| test-team-leader | `test-team-leader` teammate | Plan testing, route bugs, coordinate `test-engineer` |
| test-engineer | `test-engineer` teammate | Design and implement automated tests |
| security-engineer | `security-engineer` teammate | Passive security audit role |

After startup, the current main session is `team-lead`. It coordinates the team and must not be replaced by a teammate.

## When to Use

Use this skill when the user runs `/dev-team` or explicitly asks to start the dev team / tmux development team.

## Resource Paths

All bundled resource paths in this skill are relative to this `SKILL.md` file, not relative to the user's project working directory. Resolve this skill's directory once and refer to it as `<SKILL_DIR>`.

- Prompt files: `<SKILL_DIR>/prompts/<role>.md`
- Layout reference: `<SKILL_DIR>/resources/layout.md`
- Layout script: `<SKILL_DIR>/scripts/apply-layout.sh`

Do not search the user's project tree for these files.

## Instructions

### Step 1: Preconditions

Before creating the team, verify that the runtime is tmux team mode. If any check fails, stop and clearly report what is missing.

1. Use Bash to confirm the current session is inside tmux:
   - command: `test -n "$TMUX"`
   - If it fails, stop and tell the user to start Claude Code inside a tmux session.
2. Use Read to inspect the project root `.claude/settings.local.json` and confirm both settings exist:
   - `"teammateMode": "tmux"`
   - `"env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" }`
   - If the file is missing or either setting is missing, stop and tell the user to create or update it:
   ```json
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     },
     "teammateMode": "tmux"
   }
   ```
   After the file is updated, the user must restart Claude Code and run `/dev-team` again.
3. Use Bash to confirm tmux panes can be listed:
   - command: `tmux list-panes -a -F '#{pane_id}'`
   - Save this output, or rerun it later, for stale-team detection.
   - If it fails, stop and report that tmux pane listing is unavailable.

### Step 2: Stale-Team Detection

The fixed team name is `dev-team`. Do not blindly trust old config.

Inspect `~/.claude/teams/dev-team/config.json`:

1. If the file does not exist, continue with team creation.
2. If the file exists, read it and compare it with `tmux list-panes -a -F '#{pane_id}'`.
3. Treat the existing team as valid only when all conditions are true:
   - The team config is readable and active.
   - The 7 canonical member names exist exactly: `fe-team-leader`, `fe-developer`, `be-team-leader`, `be-developer`, `test-team-leader`, `test-engineer`, `security-engineer`.
   - Every member has a non-empty `tmuxPaneId`.
   - Every `tmuxPaneId` exists in `tmux list-panes -a -F '#{pane_id}'`.
   - Drifted substitute names such as `fe-team-leader-2` or `fe-developer-2` are not treated as canonical team members.
4. If a valid team already exists, do not create another team or teammate. Report:

```markdown
dev-team is already running.

| Role              | Member            | tmux pane | Status |
|-------------------|-------------------|-----------|-------|
| team-lead         | current session   | current   | ready |
| fe-team-leader    | fe-team-leader    | <paneId>  | ready |
| fe-developer      | fe-developer      | <paneId>  | ready |
| be-team-leader    | be-team-leader    | <paneId>  | ready |
| be-developer      | be-developer      | <paneId>  | ready |
| test-team-leader  | test-team-leader  | <paneId>  | ready |
| test-engineer     | test-engineer     | <paneId>  | ready |
| security-engineer | security-engineer | <paneId>  | ready |
```

5. If any condition fails, treat the existing state as stale and continue to cleanup.

### Step 3: Cleanup Stale `dev-team` State

Cleanup must be scoped only to the fixed team `dev-team`. Do not delete other teams, panes, code, or user files.

Prefer gentle cleanup:

1. Send a shutdown request to each recognizable canonical member in the config:
   - SendMessage to each of the 7 canonical names with `type: shutdown_request`, content: `Cleaning stale dev-team state before restarting the canonical dev team.`
   - If a member is missing, unreachable, or send fails, record it and continue.
2. Call TeamDelete for `dev-team`.
   - If TeamDelete succeeds, continue with team creation.
   - If TeamDelete fails, decide whether stale config is blocking creation and stale panes are confirmed missing.

If stale config blocks team creation and old panes are confirmed missing, tell the user first that only `dev-team` stale state will be cleaned and no other teams, tmux panes, code, or user files will be touched. Then delete only these dedicated state paths:

- `~/.claude/teams/dev-team/`
- `~/.claude/tasks/dev-team/`

If TeamDelete fails and stale panes still exist, stop and tell the user:

`Team cleanup failed. Manually close these tmux panes and retry /dev-team: [list remaining stale pane IDs].`

### Step 4: Create Team

Call TeamCreate:

- `team_name`: `dev-team`
- `description`: `DAMO Academy 8-agent full-stack development team`
- `agent_type`: `team-lead`

### Step 5: Launch 7 Teammates in Parallel

Use the Agent tool to launch exactly 7 teammates. Every teammate must use `mode: bypassPermissions` and `run_in_background: true`.

Before launching:

1. Resolve `<SKILL_DIR>` as the directory containing this `SKILL.md`.
2. Read all 7 prompt files first, preferably in one parallel Read batch.
3. Only after all prompt files have been read successfully, launch all 7 teammates in one parallel Agent tool call. Pass each file's full content as that teammate's `prompt` parameter.

| name | subagent_type | team_name | prompt file |
|---|---|---|---|
| `fe-team-leader` | `fe-team-leader` | `dev-team` | `<SKILL_DIR>/prompts/fe-team-leader.md` |
| `fe-developer` | `fe-developer` | `dev-team` | `<SKILL_DIR>/prompts/fe-developer.md` |
| `be-team-leader` | `be-team-leader` | `dev-team` | `<SKILL_DIR>/prompts/be-team-leader.md` |
| `be-developer` | `be-developer` | `dev-team` | `<SKILL_DIR>/prompts/be-developer.md` |
| `test-team-leader` | `test-team-leader` | `dev-team` | `<SKILL_DIR>/prompts/test-team-leader.md` |
| `test-engineer` | `test-engineer` | `dev-team` | `<SKILL_DIR>/prompts/test-engineer.md` |
| `security-engineer` | `security-engineer` | `dev-team` | `<SKILL_DIR>/prompts/security-engineer.md` |

### Step 6: Project-Lead Operating Protocol

After startup, the current main session is `team-lead` and must follow these rules:

- Use TaskCreate to split multi-step user requests.
- Use TaskUpdate `owner` to assign frontend work to `fe-team-leader`, backend work to `be-team-leader`, and testing work to `test-team-leader`.
- Keep team responsibilities separated. Do not bypass team leaders to contact developers directly.
- After FE/BE teams complete work, make sure `test-team-leader` is involved.
- Do not claim completion while unresolved test feedback remains, unless the user explicitly accepts it.
- All teammate communication must use SendMessage. Plain text from the main session is not visible to teammates.
- For shutdown, prefer the existing `/dismiss` skill or send teammate shutdown requests.
- Do not create `fe-team-leader-2`, `fe-developer-2`, or any substitute member to bypass stale state.

### Step 7: Apply Required tmux Grouped Layout

After all 7 teammates have sent idle/ready messages, apply the required grouped tmux layout.

Target layout and intent: read `<SKILL_DIR>/resources/layout.md`.

Before applying the layout, validate:

- `jq` is available.
- All 7 canonical teammates exist in `~/.claude/teams/dev-team/config.json`.
- Every teammate has a non-empty `tmuxPaneId`.
- Every `tmuxPaneId` exists in `tmux list-panes -a -F '#{pane_id}'`.
- **No teammate's `tmuxPaneId` equals the current session's pane ID** (obtain it with `tmux display-message -p '#{pane_id}'`). If any teammate shares the team-lead pane, it means that teammate was never assigned its own pane — stop, report which role is conflicting, and instruct the user to delete the stale team with `/dismiss` and re-run `/dev-team`.
- **All 7 teammate `tmuxPaneId` values are unique.** If any two roles share the same pane ID, stop and report both conflicting roles.
- If any validation fails, do not rearrange panes. Report the exact missing or invalid pane and keep the team running.

Apply the grouped layout after validation by running (substitute the actual resolved path for `<SKILL_DIR>` — do not use shell inline assignment; either use a semicolon-separated assignment or paste the full absolute path directly):

```bash
SKILL_DIR="<SKILL_DIR>"; bash "$SKILL_DIR/scripts/apply-layout.sh"
```

If the script exits with a non-zero status, stop immediately, report the failed command and reason, and keep the team running. If the script fails midway, already moved panes are not automatically restored; the team processes continue running.

After applying the layout, verify the result with:

```bash
tmux list-panes -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}'
```

Check pane coordinates and dimensions, not only command exit status:

- `team-lead` is the leftmost pane, with width approximately half the tmux window width. A one-cell difference is acceptable.
- All teammate panes are on the right half.
- The right half has four equal-height rows. A one-cell difference is acceptable.
- FE, BE, and Test rows each contain two equal-width panes. A one-cell difference is acceptable.
- `security-engineer` is in the fourth row and spans the full right-half width within a one-cell tolerance.

Only report `dev-team ready` after the layout has been verified. If verification fails, explicitly report the failure reason.

When ready, report:

```markdown
dev-team is ready (8-agent team)

| Role              | Member            | Responsibility           | Status |
|-------------------|-------------------|--------------------------|-------|
| team-lead         | current session   | planning, assignment, verification | ready |
| fe-team-leader    | fe-team-leader    | frontend planning and code review | ready |
| fe-developer      | fe-developer      | frontend implementation and self-test | ready |
| be-team-leader    | be-team-leader    | backend planning and code review | ready |
| be-developer      | be-developer      | backend implementation and self-test | ready |
| test-team-leader  | test-team-leader  | test planning and bug routing | ready |
| test-engineer     | test-engineer     | automated test design and implementation | ready |
| security-engineer | security-engineer | passive security audit | ready |

You can now describe the development task. I will act as team-lead, split the work, and assign it to the teams.
```

## Verification Checklist

1. Confirm this skill's `SKILL.md` exists and frontmatter includes `name: dev-team` and `user-invocable: true`.
2. In a tmux Claude Code session, run `/dev-team`.
3. Confirm the terminal window contains eight role panes: current `team-lead` plus 7 teammate panes.
4. Confirm `~/.claude/teams/dev-team/config.json` has 7 canonical members and each has a valid `tmuxPaneId`.
5. Run `tmux list-panes -a -F '#{pane_id}'` and confirm those pane IDs exist.
6. Confirm the layout matches `<SKILL_DIR>/resources/layout.md`: `team-lead` on the left half; right half split into four equal-height FE, BE, Test, and Security rows; FE/BE/Test rows split into two equal-width panes; Security spans its full row. Verify with `tmux list-panes -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}'`.
7. Send a small task through team-lead. FE/BE team leaders should plan and assign, developers should implement, and the test team should test.
8. Run `/dev-team` again while the team is alive. It should detect the valid existing team and not create substitute members such as `fe-team-leader-2`.
9. Only simulate stale state when safe. The skill may clean only `dev-team` state and rebuild canonical panes.
