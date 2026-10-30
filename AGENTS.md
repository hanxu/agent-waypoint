# AGENTS.md — 项目协作协议（Waypoint）

本项目使用 Waypoint 协议管理任务状态。任何 AI 客户端（Qoder / Trae / WorkBuddy / 其他）都是无状态执行器：所有跨会话需要记住的东西都在 `.waypoint/` 目录里，不在你的记忆里。

完整协议见 `.waypoint/PROTOCOL.md`。本文件只保留**每次会话都必须执行**的行为，保持精简。

## 会话启动（每次会话开始时）

1. 若 `.waypoint/HANDOFF.md` 存在 → 先读它，然后执行下方「接管仪式」
2. 先归摞自动落盘的原料：`scripts/waypoint.sh capture drain --target .`（hook 采的用户原话与回答全文；没装 hook 就直接跑，不报错）
3. 运行 `git status --short --branch` 和 `git log --oneline -5`
4. 若 `.waypoint/` 中的叙事状态与 git 实际状态冲突，**以 git 为准**，并向用户说明差异
5. 若 `.waypoint/locks/` 下有未过期的租约且 owner 不是本客户端 → 停下，询问用户（确认后才能 `--force` 抢占）

## 触发词

| 用户说 | 执行 |
|---|---|
| 「继续任务」/「/resume」 | 接管仪式（Resume） |
| 「checkpoint」/「告一段落」/「我要切到 XX 了」 | 交出仪式（Checkpoint） |
| 「任务完成」 | 归档仪式（Archive） |
| 「任务看板」/「各端进度」 | `scripts/waypoint.sh board`（含本机其他项目仓库的任务状态） |
| 「自动落盘」/「收件箱」/「这一轮原料」 | `scripts/waypoint.sh capture show --target .` 看待归摞，`capture drain --target .` 归成机器事实进 JOURNAL |
| 「页面看板」/「看板页面」/「没法直接看命令行」 | `scripts/waypoint.sh dash --open`（起本地看板服务并开浏览器，页面自己刷新；要后台常驻用 `dash --daemon`，停用 `dash stop`） |

## 接管仪式（摘要）

读 `HANDOFF.md` → `TASK.md` → `PLAN.md`，然后向用户**复述**：

> 我已接管任务「XXX」。当前状态：…；已完成：…；下一步：…；发现的差异：…。

随后取锁（`scripts/waypoint.sh lock --target .`，写 `.waypoint/locks/`，租约 45 分钟），从 HANDOFF 标注的下一步继续。**绝不从头重做已完成的工作。**

## 交出仪式（摘要）

1. 先 `scripts/waypoint.sh capture drain --target .` 把本轮自动落盘的原料归进 JOURNAL；勾选 `PLAN.md` 已完成项；向 `JOURNAL.md` **追加**本轮迭代一条（不改写历史）
2. **整体重写** `HANDOFF.md`（一页以内，必须含「Do Not Redo」与「Intentionally Dirty」两段）
3. `git add -A && git commit -m "waypoint: <一句话摘要>"`（状态文件与代码原子提交）
4. 释放锁：`scripts/waypoint.sh unlock --target .`

## 硬性规则

- **采集默认走 hook，不靠模型记性**：装了 hook（`plugins/install.sh --target . --apply`）后，用户原话、回答全文、git 事实、会话全文指针都由宿主写进 `.waypoint/inbox/`，额度耗尽也照样落盘；模型只做浓缩。没装 hook 的端才退回手工 checkpoint
- `.waypoint/` 是任务状态的唯一真相源；验收标准以 `TASK.md` 的 DoD 为准，不得擅自扩大范围
- 一次只跑一个客户端（`locks/` 租约互斥）；`locks/` 不入库，也不要把它加进用户的 `.gitignore`（`init` 已写入 `.git/info/exclude`）
- 重大取舍（选型、放弃的方案及原因）写入 `.waypoint/DECISIONS.md`
- 本机若用了全局任务库（`~/.waypoint`），跨项目/跨端的任务总览看 `board`，接管前先 `resume` 列候选让用户选（见 PROTOCOL §9）
- 本文件刻意精简；任何细节疑问查 `.waypoint/PROTOCOL.md`，不要靠猜
