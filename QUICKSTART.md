# QUICKSTART

## 路线 A：全局模式（推荐个人使用）

全机一份任务库（默认 `~/.waypoint`），任务不绑定项目，在任何客户端、任何目录说「继续任务」都接得上。

```bash
# 1. 建库（--home 可指定目录；此后所有全局命令都可用 WAYPOINT_HOME 或 --home 覆盖）
bash /path/to/agent-waypoint/scripts/waypoint.sh init-home

# 2. 立任务（--project 可选：锚定一个代码仓库，checkpoint 时会记录该项目 HEAD）
bash /path/to/agent-waypoint/scripts/waypoint.sh new 优化网关 [--project ~/work/tsy-gateway]

# 3. 注入（一次）：把 ~/.waypoint/RULES_SNIPPET.md 的内容贴进 Qoder 用户级 Rules / Trae user_rules.md
```

日常循环：任何客户端说「继续任务」接管 → 干活 → 「checkpoint」交出（它在全局库 commit）。
多任务：`waypoint.sh tasks` 列出，`waypoint.sh switch <短名>` 切换，或直接对客户端说「切换任务 <短名>」。

## 路线 B：项目模式

状态装在项目内，与代码原子提交，适合任务和仓库强绑定的场景。

### 1. 安装协议到你的项目（30 秒）

```bash
bash /path/to/agent-waypoint/scripts/waypoint.sh init --target /path/to/your-project
```

或在任何 agent 客户端里说：

> 按 INSTALL_FOR_AGENTS.md 把 https://github.com/hanxu/agent-waypoint 安装到本项目

### 2. 立项（2 分钟）

填 `.waypoint/TASK.md`（背景 + DoD 验收标准）和 `.waypoint/PLAN.md`（步骤清单）。

### 3. 日常循环

在客户端 A（如 Qoder）干活，每个迭代结束时说：

> checkpoint

它会勾选计划、追加日志、重写交接快照并 commit。

切换到客户端 B（如 Trae / WorkBuddy），说：

> 继续任务

它会读交接快照、复述状态，然后从「下一步」接着干。

## 收尾（两种模式相同）

DoD 全部通过后说「任务完成」：项目模式归档进 `.waypoint/archive/`；全局模式 `mv tasks/<短名> archive/<完结日期>-<短名>` 后在全局库 commit。

## 客户端不支持用户级规则/AGENTS.md？

把这段粘贴给它（兜底 bootstrap）：

```text
接管任务：阅读 .waypoint/HANDOFF.md、.waypoint/TASK.md、.waypoint/PLAN.md，
执行 git log --oneline -10 核对状态，复述当前进度和下一步，
等我确认后继续执行。全程遵守 AGENTS.md 中的协作协议。
```
