---
description: 启动1 tmux 三角色 TDD agent team（team-lead + developer + reviewer），由 lead 计划分配、developer 编码、reviewer 挑刺审查
user-invocable: true
---

# TDD Loop - tmux 三角色 TDD 团队启动器

## Purpose

`/tdd-loop` 是团队引导命令，不是具体编码任务。

执行后创建固定团队 `tdd-team`：

| 角色 | 成员 | 职责 |
|---|---|---|
| team-lead / teamleader | 当前 Claude Code 主会话 | 计划、拆解任务、分配、协调、验收、最终决策 |
| developer | `developer` teammate | 实现、测试、自测、报告变更文件和结果 |
| reviewer | `reviewer` teammate | 代码审查、边界情况、回归风险、安全和维护性审查，刻意挑刺 |

当前主会话启动后就是 `team-lead`，负责协调而不是被替代。

## When to use this skill

当用户使用 `/tdd-loop`，或明确要求启动 TDD team / tmux 三角色开发团队时使用。

## Instructions

### Step 1: Preconditions（必须先验证）

创建团队前必须验证运行环境是 tmux team 模式。任何检查失败都要停止，不要创建非 tmux team，并明确告诉用户缺少什么。

1. 使用 Bash 执行只读检查，确认当前会话在 tmux 中：
   - command: `test -n "$TMUX"`
   - 如果失败，停止并提示：当前 Claude Code 会话不在 tmux 中，请先在 tmux 会话里启动 Claude Code。
2. 使用 Read 读取 `~/.claude/settings.json`，确认存在：
   - `"teammateMode": "tmux"`
   - 如果不是 `tmux`，停止并提示需要将 `~/.claude/settings.json` 的 `teammateMode` 设置为 `tmux`。
3. 使用 Bash 执行只读检查，确认可列出当前可见 panes：
   - command: `tmux list-panes -a -F '#{pane_id}'`
   - 保存输出，后续 stale-team detection 必须使用这份或重新获取的 pane id 列表。
   - 如果失败，停止并提示 tmux pane 列表不可用。

### Step 2: Stale-team detection

固定团队名必须是 `tdd-team`。不要盲目信任旧 config。

检查 `~/.claude/teams/tdd-team/config.json`：

1. 如果文件不存在，继续创建新团队。
2. 如果文件存在，使用 Read 读取并结合 `tmux list-panes -a -F '#{pane_id}'` 输出判断是否为有效团队。
3. 只有同时满足以下条件，才视为有效团队：
   - team config 可读且处于 active 状态。
   - 标准成员名精确存在：`developer` 和 `reviewer`。
   - `developer` 和 `reviewer` 各自都有 `tmuxPaneId`。
   - 两个 `tmuxPaneId` 都存在于 `tmux list-panes -a -F '#{pane_id}'` 输出中。
   - 不把 `developer-2`、`reviewer-2` 或其他漂移替代名当作 canonical team。
4. 如果有效团队已存在，不要再创建 team 或 teammate。直接报告：

```markdown
`tdd-team` 已在运行。

| 角色 | 成员 | tmux pane | 状态 |
|---|---|---|---|
| team-lead | 当前会话 | current | ready |
| developer | developer | <developer tmuxPaneId> | ready |
| reviewer | reviewer | <reviewer tmuxPaneId> | ready |
```

5. 只要任何条件失败，都视为 stale team，进入 cleanup。

### Step 3: Cleanup stale `tdd-team` state

清理只允许作用于固定团队 `tdd-team`，不得删除其他 team、pane、文件或用户工作。

优先使用温和清理：

1. 对 config 中可识别且可能可达的 canonical 成员发送 shutdown request：
   - SendMessage to `developer` with type `shutdown_request`, content `清理 stale tdd-team，准备重新启动 canonical TDD team。`
   - SendMessage to `reviewer` with type `shutdown_request`, content `清理 stale tdd-team，准备重新启动 canonical TDD team。`
   - 如果成员不存在、不可达或发送失败，记录并继续。
2. 调用 TeamDelete 删除当前 team state。
   - 如果 TeamDelete 成功，继续创建团队。
   - 如果 TeamDelete 失败，判断是否因为 stale config 阻塞且 pane 已确认缺失。

如果 stale config 阻塞 team 创建，且已经确认 developer/reviewer 的旧 pane 缺失，可以只删除以下专用状态路径：

- `~/.claude/teams/tdd-team/`
- `~/.claude/tasks/tdd-team/`

执行前必须向用户说明：只会清理 `tdd-team` 的 stale state，不会删除其他团队、tmux pane、代码或用户文件。不要使用通配符，不要删除其他路径。

### Step 4: Create team

完成 preconditions 和 stale cleanup 后，使用 TeamCreate：

- team_name: `tdd-team`
- description: `tmux TDD agent team: team-lead plans, developer implements, reviewer reviews`
- agent_type: `team-lead`

### Step 5: Launch teammates（并行后台启动）

使用 Agent tool 启动且只启动两个 teammate。优先在一次并行 tool call 中启动。

#### developer

- name: `developer`
- subagent_type: `developer`
- team_name: `tdd-team`
- mode: `bypassPermissions`
- run_in_background: `true`
- prompt:

```text
Your name is exactly `developer`.
You are the implementation owner in the tmux TDD team.
The current main Claude Code session is `team-lead` / `teamleader`.

Operating rules:
- Check TaskList first.
- Claim tasks assigned to you, or available unblocked tasks when team-lead asks you to proceed.
- Write code only when assigned by team-lead.
- Follow project rules in CLAUDE.md if it exists.
- After code edits, follow the mandatory project finalize workflow when applicable.
- Keep implementation focused and avoid overengineering.
- Report changed files, tests run, results, and blockers to team-lead via SendMessage.
- Plain text is not visible to team-lead; use SendMessage for team communication.
```

#### reviewer

- name: `reviewer`
- subagent_type: `reviewer`
- team_name: `tdd-team`
- mode: `bypassPermissions`
- run_in_background: `true`
- prompt:

```text
Your name is exactly `reviewer`.
You are the review owner in the tmux TDD team.
The current main Claude Code session is `team-lead` / `teamleader`.

Operating rules:
- Review developer output and deliberately find issues.
- Focus on correctness, tests, edge cases, regressions, security, overengineering, project conventions, and maintainability.
- Do not rubber-stamp. If issues exist, create or communicate actionable findings.
- Use TaskList and TaskUpdate to track assigned review work.
- Report review results, risks, required fixes, and approval/rejection to team-lead via SendMessage.
- Plain text is not visible to team-lead; use SendMessage for team communication.
```

### Step 6: Team-lead operating protocol

启动后，当前主会话就是 `team-lead`，必须遵守：

- 多步骤用户请求用 TaskCreate 拆解。
- 用 TaskUpdate 的 `owner` 字段把实现任务分给 `developer`，把审查任务分给 `reviewer`。
- 保持 developer 和 reviewer 职责分离。
- developer 完成后，必须安排 reviewer 审查。
- reviewer 反馈未解决或未被用户明确接受前，不要宣布任务完成。
- 所有 teammate 沟通必须使用 SendMessage；主会话直接输出的普通文本 teammate 看不到。
- 收尾或结束团队时，优先使用现有 `/dismiss` skill 或向 teammate 发送 shutdown_request。
- 不要创建 `developer-2`、`reviewer-2` 或其他替代成员来绕过 stale state。

### Step 7: Ready signal

等待 `developer` 和 `reviewer` 都发送 idle/ready 消息后，向用户报告：

```markdown
TDD team 已就绪。

| 角色 | 成员 | 职责 | 状态 |
|---|---|---|---|
| team-lead | 当前会话 | 计划、拆任务、分配、验收 | ready |
| developer | developer | 实际编码与自测 | ready |
| reviewer | reviewer | 审查、挑刺、风险识别 | ready |

现在可以直接描述开发任务，我会作为 team-lead 分配给 developer，并让 reviewer 审查。
```

## Verification checklist

实现或修改此 skill 后，用以下步骤验证：

1. 确认 `~/.claude/skills/tdd-loop/SKILL.md` 存在且 frontmatter 包含 `user-invocable: true`。
2. 在 tmux Claude Code session 中运行 `/tdd-loop`。
3. 确认当前 terminal window 出现三角色 panes：当前 `team-lead`，以及 `developer`、`reviewer`。
4. 确认 `~/.claude/teams/tdd-team/config.json` 中有 canonical members：`developer`、`reviewer`，且都有有效 `tmuxPaneId`。
5. 执行 `tmux list-panes -a -F '#{pane_id}'`，确认上述 pane id 存在。
6. 通过 lead 发一个小任务，developer 应实现或计划实现，reviewer 应给出具体 critique，不要 rubber-stamp。
7. team 存活时再次运行 `/tdd-loop`，应识别现有有效 team，不创建 `developer-2` / `reviewer-2`。
8. 只有在安全情况下模拟 stale state；skill 只能清理 `tdd-team` state 并重建 canonical panes。
