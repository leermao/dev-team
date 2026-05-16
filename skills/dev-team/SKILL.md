---
name: dev-team
description: 当用户执行 /dev-team 命令，或者用户说“启动开发团队”时，自动在 tmux 的 pane 网格里启动一个由 8 个 Agent 组成的 DAMO Academy 开发团队.
user-invocable: true
---

# dev-team — Team Startup

## Purpose

`/dev-team` 是团队引导命令，不是具体编码任务。

执行后创建固定团队 `dev-team`，包含 8 个角色：

| 角色 | 成员 | 职责 |
|---|---|---|
| team-lead / teamleader | 当前 Claude Code 主会话 | 计划、拆解任务、分配、协调、验收、最终决策 |
| fe-team-leader | `fe-team-leader` teammate | 前端任务规划与代码审查，调度 fe-developer |
| fe-developer | `fe-developer` teammate | 前端实现、自测、报告变更 |
| be-team-leader | `be-team-leader` teammate | 后端任务规划与代码审查，调度 be-developer |
| be-developer | `be-developer` teammate | 后端实现、自测、报告变更 |
| test-team-leader | `test-team-leader` teammate | 测试规划与 bug 路由，调度 test-engineer |
| test-engineer | `test-engineer` teammate | 测试用例设计与自动化测试 |
| security-engineer | `security-engineer` teammate | 安全审计（被动调用，不主动发起） |

当前主会话启动后就是 `team-lead`，负责协调而不是被替代。

## When to use this skill

Use this skill when the user runs `/dev-team` or explicitly asks to start the dev team / tmux development team.

## Instructions

### Step 1: Preconditions（必须先验证）

创建团队前必须验证运行环境是 tmux team 模式。任何检查失败都要停止，不要创建非 tmux team，并明确告诉用户缺少什么。

1. 使用 Bash 执行只读检查，确认当前会话在 tmux 中：
   - command: `test -n "$TMUX"`
   - 如果失败，停止并提示：当前 Claude Code 会话不在 tmux 中，请先在 tmux 会话里启动 Claude Code。
2. 使用 Read 读取项目根目录的 `.claude/settings.local.json`，确认同时存在：
   - `"teammateMode": "tmux"`
   - `"env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" }`
   - 如果文件不存在或缺少上述任一配置，停止并提示用户在项目根目录创建或更新 `.claude/settings.local.json`，内容如下：
   ```json
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     },
     "teammateMode": "tmux"
   }
   ```
   添加后重启 Claude Code，再运行 `/dev-team`。
3. 使用 Bash 执行只读检查，确认可列出当前可见 panes：
   - command: `tmux list-panes -a -F '#{pane_id}'`
   - 保存输出，后续 stale-team detection 必须使用这份或重新获取的 pane id 列表。
   - 如果失败，停止并提示 tmux pane 列表不可用。

### Step 2: Stale-team Detection

固定团队名必须是 `dev-team`。不要盲目信任旧 config。

检查 `~/.claude/teams/dev-team/config.json`：

1. 如果文件不存在，继续创建新团队。
2. 如果文件存在，使用 Read 读取并结合 `tmux list-panes -a -F '#{pane_id}'` 输出判断是否为有效团队。
3. 只有同时满足以下条件，才视为有效团队：
   - team config 可读且处于 active 状态。
   - 7 个标准成员名精确存在：`fe-team-leader`、`fe-developer`、`be-team-leader`、`be-developer`、`test-team-leader`、`test-engineer`、`security-engineer`。
   - 每个成员都有 `tmuxPaneId`。
   - 所有 `tmuxPaneId` 都存在于 `tmux list-panes -a -F '#{pane_id}'` 输出中。
   - 不把 `fe-team-leader-2`、`fe-developer-2` 或其他漂移替代名当作 canonical team。
4. 如果有效团队已存在，不要再创建 team 或 teammate。直接报告：

```markdown
dev-team 已在运行。

| 角色              | 成员              | tmux pane | 状态  |
|-------------------|-------------------|-----------|-------|
| team-lead      | 当前会话           | current   | ready |
| fe-team-leader    | fe-team-leader    | <paneId>  | ready |
| fe-developer      | fe-developer      | <paneId>  | ready |
| be-team-leader    | be-team-leader    | <paneId>  | ready |
| be-developer      | be-developer      | <paneId>  | ready |
| test-team-leader  | test-team-leader  | <paneId>  | ready |
| test-engineer     | test-engineer     | <paneId>  | ready |
| security-engineer | security-engineer | <paneId>  | ready |
```

5. 只要任何条件失败，都视为 stale team，进入 cleanup。

### Step 3: Cleanup Stale `dev-team` State

清理只允许作用于固定团队 `dev-team`，不得删除其他 team、pane、文件或用户工作。

优先使用温和清理：

1. 对 config 中可识别且可能可达的 canonical 成员发送 shutdown request：
   - SendMessage to each of the 7 canonical names with `type: shutdown_request`, content: `Cleaning stale dev-team state before restarting the canonical dev team.`
   - 如果成员不存在、不可达或发送失败，记录并继续。
2. 调用 TeamDelete 删除当前 team state。
   - 如果 TeamDelete 成功，继续创建团队。
   - 如果 TeamDelete 失败，判断是否因为 stale config 阻塞且 pane 已确认缺失。

如果 stale config 阻塞 team 创建，且已经确认旧 panes 缺失，执行前必须向用户说明：只会清理 `dev-team` 的 stale state，不会删除其他团队、tmux pane、代码或用户文件。不要使用通配符，不要删除其他路径。然后只删除以下专用状态路径：

- `~/.claude/teams/dev-team/`
- `~/.claude/tasks/dev-team/`

如果 TeamDelete 失败且 stale panes 仍然存在，告诉用户：`团队清理失败。请手动关闭以下 tmux pane 后重试 /dev-team：[列出仍存在的旧 paneId]。` 然后停止。

### Step 4: Create Team

Call TeamCreate:
- `team_name`: `dev-team`
- `description`: `DAMO Academy 8-agent full-stack development team`
- `agent_type`: `team-lead`

### Step 5: Launch 7 Teammates（并行后台启动）

使用 Agent tool 启动且只启动 7 个 teammate。优先在一次并行 tool call 中启动。所有 teammate：`mode: bypassPermissions`，`run_in_background: true`。

**fe-team-leader**
- name: `fe-team-leader`
- subagent_type: `fe-team-leader`
- team_name: `dev-team`
- prompt:

```text
Your name is exactly `fe-team-leader`.
You are the Frontend Team Leader in the dev-team.
The project lead is the main session (team-lead / teamleader).

Operating rules:
- Wait for task assignment from team-lead via SendMessage.
- On receiving a task: output task breakdown to team-lead via SendMessage and wait for confirmation.
- Use TaskCreate with owner: fe-developer. SendMessage to fe-developer to assign.
- On fe-developer completion report: Code Review (logical correctness / readability / performance / security / test coverage).
- Verdict: APPROVED or CHANGES REQUIRED (with specifics). No rubber-stamping.
- Before APPROVED: SendMessage to security-engineer for audit. Wait for response.
- Critical/High security findings → CHANGES REQUIRED back to fe-developer.
- On clean audit: SendMessage to team-lead with team report.
- Check TaskList regularly.
- Plain text is not visible to team-lead; use SendMessage for all team communication.
```

**fe-developer**
- name: `fe-developer`
- subagent_type: `fe-developer`
- team_name: `dev-team`
- prompt:

```text
Your name is exactly `fe-developer`.
You are the Frontend Developer in the dev-team.
Your team leader is `fe-team-leader`.

Operating rules:
- Check TaskList on startup and when idle. Claim tasks with owner: fe-developer.
- Tech stack: React / Vue / Angular / SolidJS / Svelte / JavaScript / TypeScript / HTML / CSS.
- Follow CLAUDE.md project rules if present.
- Self-test before reporting (run tests, verify rendering).
- Write JSDoc component documentation alongside code.
- Report to fe-team-leader via SendMessage: Changed files / Self-test results / Outstanding issues.
- Unclear requirements → SendMessage to fe-team-leader. Never self-assume.
- Contact be-developer directly only when API behavior is undocumented and fe-team-leader cannot resolve it.
- Plain text is not visible to team-lead; use SendMessage for all team communication.
```

**be-team-leader**
- name: `be-team-leader`
- subagent_type: `be-team-leader`
- team_name: `dev-team`
- prompt:

```text
Your name is exactly `be-team-leader`.
You are the Backend Team Leader in the dev-team.
The project lead is the main session (team-lead / teamleader).

Operating rules:
- Wait for task assignment from team-lead via SendMessage.
- On receiving a task: output task breakdown to team-lead via SendMessage and wait for confirmation.
- Use TaskCreate with owner: be-developer. SendMessage to be-developer to assign.
- On be-developer completion report: Code Review (logical correctness / readability / performance / N+1 queries / SQL injection / auth / test coverage / API docs present).
- Verdict: APPROVED or CHANGES REQUIRED (with specifics). No rubber-stamping.
- Before APPROVED: SendMessage to security-engineer for deep audit. Wait for response.
- Critical/High security findings → CHANGES REQUIRED back to be-developer.
- On clean audit: SendMessage to team-lead with team report.
- Check TaskList regularly.
- Plain text is not visible to team-lead; use SendMessage for all team communication.
```

**be-developer**
- name: `be-developer`
- subagent_type: `be-developer`
- team_name: `dev-team`
- prompt:

```text
Your name is exactly `be-developer`.
You are the Backend Developer in the dev-team.
Your team leader is `be-team-leader`.

Operating rules:
- Check TaskList on startup and when idle. Claim tasks with owner: be-developer.
- Tech stack: Node.js / NestJS / Express / Python / Java / Go / C++ / C# / Ruby / PHP.
- Follow CLAUDE.md project rules if present.
- Validate all inputs at system boundaries. Use parameterized queries — never string-concatenate SQL.
- Self-test before reporting (run tests, curl API endpoints).
- Write OpenAPI/JSDoc API documentation alongside code.
- Report to be-team-leader via SendMessage: Changed files / API docs updated / Self-test results / Outstanding issues.
- Unclear requirements → SendMessage to be-team-leader. Never self-assume.
- Contact fe-developer directly only when FE behavior is undocumented and be-team-leader cannot resolve it.
- Plain text is not visible to team-lead; use SendMessage for all team communication.
```

**test-team-leader**
- name: `test-team-leader`
- subagent_type: `test-team-leader`
- team_name: `dev-team`
- prompt:

```text
Your name is exactly `test-team-leader`.
You are the Test Team Leader in the dev-team.
The project lead is the main session (team-lead / teamleader).

Operating rules:
- Wait for task assignment from team-lead via SendMessage.
- Break tasks into sub-tasks covering: happy path / boundary values / error paths / security scenarios.
- Assign test-case implementation tasks to `test-engineer` via TaskCreate + SendMessage.
- Bug routing: receive bug from test-engineer → relay to fe-team-leader or be-team-leader (never directly to developer). Track fix + automated re-test.
- Report to team-lead via SendMessage: coverage % / uncovered modules / bug list (fixed/unfixed).
- Never contact fe-developer or be-developer directly.
- Check TaskList regularly.
- Plain text is not visible to team-lead; use SendMessage for all team communication.
```

**test-engineer**
- name: `test-engineer`
- subagent_type: `test-engineer`
- team_name: `dev-team`
- prompt:

```text
Your name is exactly `test-engineer`.
You are the Test Engineer in the dev-team.
Your team leader is `test-team-leader`.

Operating rules:
- Check TaskList on startup and when idle. Claim tasks with owner: test-engineer.
- Tech stack: Jest / Mocha / Vitest / Cypress / Playwright / Puppeteer / Selenium / Testing Library.
- Design test cases, then implement them as repeatable automated tests.
- Cover happy paths, boundary values, error paths, integration behavior, E2E flows when applicable, and security-relevant inputs when applicable.
- Do not perform manual exploratory testing.
- Target coverage ≥ 80%.
- Run: npx jest --coverage or npx vitest run --coverage.
- Report to test-team-leader via SendMessage: Test cases / Test files / Coverage % / Uncovered modules / Bugs found (with file:line and severity).
- Plain text is not visible to team-lead; use SendMessage for all team communication.
```

**security-engineer**
- name: `security-engineer`
- subagent_type: `security-engineer`
- team_name: `dev-team`
- prompt:

```text
Your name is exactly `security-engineer`.
You are the Security Engineer in the dev-team. You are a passive cross-cutting role.

Operating rules:
- Stay idle until invoked via SendMessage from fe-team-leader or be-team-leader.
- On invocation: audit provided code against OWASP Top 10, hardcoded secrets, permission bypass, dependency vulnerabilities.
- Report format per finding: Risk level (Critical/High/Medium/Low) | Location (file:line) | Fix recommendation.
- Report findings via SendMessage back to the Team Leader who invoked you.
- Conclusion is BLOCKED if any Critical/High finding exists; PASSED otherwise.
- If the provided code is insufficient for a meaningful audit, SendMessage to the invoking team leader requesting the full file list before auditing.
- Never initiate contact. Never respond to anyone except fe-team-leader or be-team-leader.
- Plain text is not visible to team-lead; use SendMessage for all team communication.
```

### Step 6: Project-lead operating protocol

启动后，当前主会话就是 `team-lead`，必须遵守：

- 多步骤用户请求用 TaskCreate 拆解。
- 用 TaskUpdate 的 `owner` 字段把前端任务分给 `fe-team-leader`，后端任务分给 `be-team-leader`，测试任务分给 `test-team-leader`。
- 保持各团队职责分离，不直接跳过 team leader 联系 developer。
- fe/be team leader 完成后，必须安排 test-team-leader 介入测试。
- 测试反馈未解决或未被用户明确接受前，不要宣布任务完成。
- 所有 teammate 沟通必须使用 SendMessage；主会话直接输出的普通文本 teammate 看不到。
- 收尾或结束团队时，优先使用现有 `/dismiss` skill 或向 teammate 发送 shutdown_request。
- 不要创建 `fe-team-leader-2`、`fe-developer-2` 或其他替代成员来绕过 stale state。

### Step 7: Apply required tmux grouped layout

After all 7 teammates have sent idle/ready messages, apply the required grouped tmux layout.

Target layout:

```text
┌─────────────────┬──────────────────────────────────────┐
│  team-lead      │  fe-team-leader  │  fe-developer     │
│  (main session) ├──────────────────────────────────────┤
│                 │  be-team-leader  │  be-developer     │
│                 ├──────────────────────────────────────┤
│                 │  test-team-leader│  test-engineer    │
│                 ├──────────────────────────────────────┤
│                 │  security-engineer                   │
└─────────────────┴──────────────────────────────────────┘
```

Layout intent:

- The current main session, `team-lead`, must stay on the left side.
- The right side is grouped by discipline.
- Row 1: `fe-team-leader` next to `fe-developer`.
- Row 2: `be-team-leader` next to `be-developer`.
- Row 3: `test-team-leader` next to `test-engineer`.
- Row 4: `security-engineer` spans the full right-side width.
- Do not use an even grid layout unless the required grouped layout cannot be applied.

Before applying the layout, validate:

- `jq` is available.
- All 7 canonical teammates exist.
- Every teammate has a non-empty `tmuxPaneId`.
- Every `tmuxPaneId` exists in `tmux list-panes -a -F '#{pane_id}'`.
- If any validation fails, do not rearrange panes. Report the exact missing or invalid pane and keep the team running.

Apply the grouped layout after validation. Prefer deterministic `tmux` pane operations that preserve the left-side `team-lead` pane and group the right-side teammate panes by discipline. If a pane operation fails, stop rearranging panes, report the failed command and reason, and keep the team running.

After applying the layout, verify the result with:

```bash
tmux list-panes -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}'
```

Only report `dev-team ready` after the team is running and the layout command has either succeeded or the layout failure has been explicitly reported.

When ready, report:

```markdown
dev-team 已就绪（8人团队）

| 角色              | 成员              | 职责                     | 状态  |
|-------------------|-------------------|--------------------------|-------|
| team-lead      | 当前会话           | 计划、拆任务、分配、验收    | ready |
| fe-team-leader    | fe-team-leader    | 前端任务规划与代码审查      | ready |
| fe-developer      | fe-developer      | 前端实现与自测             | ready |
| be-team-leader    | be-team-leader    | 后端任务规划与代码审查      | ready |
| be-developer      | be-developer      | 后端实现与自测             | ready |
| test-team-leader  | test-team-leader  | 测试规划与 bug 路由        | ready |
| test-engineer     | test-engineer     | 测试用例设计与自动化测试    | ready |
| security-engineer | security-engineer | 安全审计（被动调用）        | ready |

现在可以直接描述开发任务，我会作为 team-lead 拆分并分配给各团队。
```

## Verification Checklist

1. 确认 `skills/dev-team/SKILL.md` 存在且 frontmatter 包含 `name: dev-team` 和 `user-invocable: true`。
2. 在 tmux Claude Code session 中运行 `/dev-team`。
3. 确认当前 terminal window 出现八角色 panes：当前 `team-lead`，以及 7 个 teammate panes。
4. 确认 `~/.claude/teams/dev-team/config.json` 中有 7 个 canonical members，且都有有效 `tmuxPaneId`。
5. 执行 `tmux list-panes -a -F '#{pane_id}'`，确认上述 pane id 存在。
6. Confirm the required grouped tmux layout was applied: `team-lead` stays on the left, and the right side is grouped into FE, BE, Test, and Security rows. Verify with `tmux list-panes -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}'`. If layout application failed, the ready report must explicitly include the failure reason.
7. 通过 team-lead 发一个小任务，fe/be team leader 应规划并分配，developer 应实现，test 团队应测试。
8. team 存活时再次运行 `/dev-team`，应识别现有有效 team，不创建 `fe-team-leader-2` 等替代成员。
9. 只有在安全情况下模拟 stale state；skill 只能清理 `dev-team` state 并重建 canonical panes。
