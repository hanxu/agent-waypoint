# QUICKSTART

## 1. 安装协议到你的项目（30 秒）

```bash
bash /path/to/agent-waypoint/scripts/waypoint.sh init --target /path/to/your-project
```

或在任何 agent 客户端里说：

> 按 INSTALL_FOR_AGENTS.md 把 https://github.com/hanxu/agent-waypoint 安装到本项目

## 2. 立项（2 分钟）

填 `.waypoint/TASK.md`（背景 + DoD 验收标准）和 `.waypoint/PLAN.md`（步骤清单）。

## 3. 日常循环

在客户端 A（如 Qoder）干活，每个迭代结束时说：

> checkpoint

它会勾选计划、追加日志、重写交接快照并 commit。

切换到客户端 B（如 Trae / WorkBuddy），说：

> 继续任务

它会读交接快照、复述状态，然后从「下一步」接着干。

## 4. 收尾

DoD 全部通过后说「任务完成」，状态文件归档进 `.waypoint/archive/`。

## 客户端不支持 AGENTS.md？

把这段粘贴给它（兜底 bootstrap）：

```text
接管任务：阅读 .waypoint/HANDOFF.md、.waypoint/TASK.md、.waypoint/PLAN.md，
执行 git log --oneline -10 核对状态，复述当前进度和下一步，
等我确认后继续执行。全程遵守 AGENTS.md 中的协作协议。
```
