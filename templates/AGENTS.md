# AGENTS.md — 项目协作协议（Waypoint）

本项目使用 Waypoint 协议管理任务状态。任何 AI 客户端（Qoder / Trae / WorkBuddy / 其他）都是无状态执行器：所有跨会话需要记住的东西都在 `.waypoint/` 目录里，不在你的记忆里。

完整协议见 `.waypoint/PROTOCOL.md`。本文件只保留**每次会话都必须执行**的行为，保持精简。

## 会话启动（每次会话开始时）

1. 若 `.waypoint/HANDOFF.md` 存在 → 先读它，然后执行下方「接管仪式」
2. 运行 `git status --short --branch` 和 `git log --oneline -5`
3. 若 `.waypoint/` 中的叙事状态与 git 实际状态冲突，**以 git 为准**，并向用户说明差异
4. 若存在 `.waypoint/LOCK` 且内容不是本客户端 → 停下，询问用户

## 触发词

| 用户说 | 执行 |
|---|---|
| 「继续任务」/「/resume」 | 接管仪式（Resume） |
| 「checkpoint」/「告一段落」/「我要切到 XX 了」 | 交出仪式（Checkpoint） |
| 「任务完成」 | 归档仪式（Archive） |

## 接管仪式（摘要）

读 `HANDOFF.md` → `TASK.md` → `PLAN.md`，然后向用户**复述**：

> 我已接管任务「XXX」。当前状态：…；已完成：…；下一步：…；发现的差异：…。

随后写入 `.waypoint/LOCK`（客户端名 + 时间），从 HANDOFF 标注的下一步继续。**绝不从头重做已完成的工作。**

## 交出仪式（摘要）

1. 勾选 `PLAN.md` 已完成项；向 `JOURNAL.md` **追加**一条（不改写历史）
2. **整体重写** `HANDOFF.md`（一页以内，必须含「Do Not Redo」与「Intentionally Dirty」两段）
3. `git add -A && git commit -m "waypoint: <一句话摘要>"`（状态文件与代码原子提交）
4. 删除 `.waypoint/LOCK`

## 硬性规则

- `.waypoint/` 是任务状态的唯一真相源；验收标准以 `TASK.md` 的 DoD 为准，不得擅自扩大范围
- 一次只跑一个客户端（LOCK 互斥）
- 重大取舍（选型、放弃的方案及原因）写入 `.waypoint/DECISIONS.md`
- 本文件刻意精简；任何细节疑问查 `.waypoint/PROTOCOL.md`，不要靠猜
