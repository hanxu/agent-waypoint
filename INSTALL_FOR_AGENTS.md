# INSTALL_FOR_AGENTS.md — Agent 安装指南

> 本文件供 AI agent 执行：当用户要求「在这个项目里安装 waypoint」时，按下述步骤操作。
> 先问清用户要哪种模式：**项目模式**（状态装在仓库内，§安装步骤）还是**全局模式**（全机一份任务库，§全局模式）。两种都装不冲突。

## 前提

- 目标项目是 git 仓库（不是的话先 `git init`）
- 本 kit 已 clone 到本地任意位置

## 安装步骤

### 1. 复制状态目录

首选跑脚本（它会建 `locks/`、写入 `.git/info/exclude`、并把仓库登记到本机看板）：

```bash
bash <kit路径>/scripts/waypoint.sh init --target <目标项目>
```

若脚本不可用才手工执行：

```bash
mkdir -p <目标项目>/.waypoint/archive <目标项目>/.waypoint/locks
cp <kit路径>/templates/{PROTOCOL,TASK,PLAN,HANDOFF,JOURNAL,DECISIONS}.md <目标项目>/.waypoint/
echo '.waypoint/locks/' >> "$(git -C <目标项目> rev-parse --show-toplevel)/.git/info/exclude"
```

复制后 `.waypoint/` 内应含：PROTOCOL.md、TASK.md、PLAN.md、HANDOFF.md、JOURNAL.md、DECISIONS.md 与 `locks/`。

### 2. 接入根指令文件（谨慎操作）

- 若目标项目**没有** `AGENTS.md`：把 `<kit路径>/templates/AGENTS.md` 复制到项目根目录
- 若**已有** `AGENTS.md`：**不要覆盖**。读取现有内容，把以下段落合并进去（保留原有内容）：

```markdown
## 任务接续协议（Waypoint）
本项目使用 .waypoint/ 目录管理任务状态，任何 AI 客户端都是无状态执行器。
- 触发词：「继续任务」→ 接管仪式；「checkpoint」→ 交出仪式；「任务看板」→ waypoint.sh board
- 会话开始先读 .waypoint/HANDOFF.md 并复述状态；绝不从头重做已完成工作
- 接管取锁 `waypoint.sh lock --target .`，交出后 `unlock --target .`；`locks/` 不入库
- 完整协议：.waypoint/PROTOCOL.md
```

- 同理适用于 `CLAUDE.md`、`.trae/rules/project_rules.md` 等：只放一行指针 `协作协议见根目录 AGENTS.md`，不复制全文

### 3. 归档目录

`init` 已建好 `.waypoint/archive/` 与 `.waypoint/locks/`。不要把 `locks/` 加进用户的 `.gitignore`（脚本用的是仓库本地的 `.git/info/exclude`，不污染仓库文件）。

仅当任务涉密、用户明确要求时，才把 `.waypoint/` 加入 `.gitignore`（默认应入库以获得跨机器能力）。

### 4. 验证安装

```bash
ls <目标项目>/.waypoint/          # 应看到 6 个模板文件 + archive/ + locks/
bash <kit路径>/scripts/waypoint.sh status --target <目标项目>   # 应输出初始化状态（零提交仓库也不报错）
bash <kit路径>/scripts/waypoint.sh board                        # 若本机有全局库，应列到刚装的仓库
bash <kit路径>/scripts/waypoint.sh dash --out /tmp/wp.html      # 页面看板应能生成（别用 --open 打扰用户）
```

然后向用户报告：协议已安装，并**提醒先提交安装产生的文件**（`git add -A && git commit`），否则第一次 checkpoint 会被判为脏树。立任务的方式是填 `.waypoint/TASK.md` 和 `PLAN.md`，之后在任何客户端说「继续任务」即可接力。

## 全局模式（机器级任务库）

用户想「不绑定项目、任何目录都能继续任务」或「多端各干一份、接管时能选」时：

```bash
bash <kit路径>/scripts/waypoint.sh init-home [--home <目录>]   # 默认 ~/.waypoint
bash <kit路径>/scripts/waypoint.sh new <任务线> --client <本端固定名>
```

- `init-home` 会拒绝把库建在别人的 git 仓库里（避免污染宿主仓库）；用户确认要嵌套时才加 `--force`
- 把生成的 `RULES_SNIPPET.md` 内容贴进客户端**用户级/全局规则**，并在规则里固定本端的 `--client` 名字（每个端一个、不变）
- 旧版单文件布局的库：跑一次 `waypoint.sh migrate` 归位到 `tasks/<线>/sessions/<端>/`
- 验收：`waypoint.sh board` 能列出会话；另一个端跑 `waypoint.sh resume` 应看到多个候选
- 用户嫌命令行不直观时，给页面看板：`dash --open` 生成 `~/.waypoint/dashboard.html` 并打开（零依赖）；想让它自己刷新就用 `dash --serve`（`127.0.0.1:8787`，需 python3）

## 禁止事项

- 不得覆盖目标项目已有的 AGENTS.md / CLAUDE.md / rules 文件
- 不得修改 `.waypoint/PROTOCOL.md`（协议本体，升级时整体替换并 diff）
- 不得把 `.waypoint/` 模板文件改成空文件占位
- 不得在用户的真实 `~/.waypoint` 上试命令；验证请带 `--home "$(mktemp -d)"` 或先问用户
- 不得把 `locks/` 提交进仓库，也不得替用户改 `.gitignore` 来排除它
