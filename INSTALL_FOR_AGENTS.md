# INSTALL_FOR_AGENTS.md — Agent 安装指南

> 本文件供 AI agent 执行：当用户要求「在这个项目里安装 waypoint」时，按下述步骤操作。
> 人类用户可直接运行 `scripts/waypoint.sh init --target <项目路径>`，效果相同。

## 前提

- 目标项目是 git 仓库（不是的话先 `git init`）
- 本 kit 已 clone 到本地任意位置

## 安装步骤

### 1. 复制状态目录

```bash
cp -r <kit路径>/templates/ <目标项目>/.waypoint/
```

复制后 `.waypoint/` 内应含：PROTOCOL.md、TASK.md、PLAN.md、HANDOFF.md、JOURNAL.md、DECISIONS.md。

### 2. 接入根指令文件（谨慎操作）

- 若目标项目**没有** `AGENTS.md`：把 `<kit路径>/templates/AGENTS.md` 复制到项目根目录
- 若**已有** `AGENTS.md`：**不要覆盖**。读取现有内容，把以下段落合并进去（保留原有内容）：

```markdown
## 任务接续协议（Waypoint）
本项目使用 .waypoint/ 目录管理任务状态，任何 AI 客户端都是无状态执行器。
- 触发词：「继续任务」→ 接管仪式；「checkpoint」→ 交出仪式
- 会话开始先读 .waypoint/HANDOFF.md 并复述状态；绝不从头重做已完成工作
- 完整协议：.waypoint/PROTOCOL.md
```

- 同理适用于 `CLAUDE.md`、`.trae/rules/project_rules.md` 等：只放一行指针 `协作协议见根目录 AGENTS.md`，不复制全文

### 3. 归档目录与忽略规则

```bash
mkdir -p <目标项目>/.waypoint/archive
```

仅当任务涉密、用户明确要求时，才把 `.waypoint/` 加入 `.gitignore`（默认应入库以获得跨机器能力）。

### 4. 验证安装

```bash
ls <目标项目>/.waypoint/          # 应看到 6 个模板文件
bash <kit路径>/scripts/waypoint.sh status --target <目标项目>   # 应输出初始化状态
```

然后向用户报告：协议已安装，立一个任务的方式是填 `.waypoint/TASK.md` 和 `PLAN.md`，之后在任何客户端说「继续任务」即可接力。

## 禁止事项

- 不得覆盖目标项目已有的 AGENTS.md / CLAUDE.md / rules 文件
- 不得修改 `.waypoint/PROTOCOL.md`（协议本体，升级时整体替换并 diff）
- 不得把 `.waypoint/` 模板文件改成空文件占位
