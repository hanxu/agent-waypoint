# agent-waypoint 🪢

**任务薪火相传，客户端只是执炬人。**
**A cross-client task handoff protocol: continue your task in any AI agent client exactly where the last one left off — never start over.**

Waypoint 是一个跨 AI 客户端的任务接续协议。你在 Qoder 里跑到一半的任务，切到 Trae / WorkBuddy / 任何 agent 客户端，说一句「继续任务」，就能从断点无缝接续——不重做、不丢上下文。

它不是插件，也不装在任何一个客户端里：协议以纯文本文件（`AGENTS.md` + `.waypoint/` 目录）的形式住在你的仓库里，任何能读写文件的 agent 都是读者。

## 特性

- 📄 **纯 Markdown 协议**，零依赖，任何客户端通用；AGENTS.md 薄启动文件 + `.waypoint/PROTOCOL.md` 完整协议两层化
- 🏠 **两种部署模式**：项目模式（状态与代码原子提交）或全局模式（`~/.waypoint` 机器级任务库，不绑定项目，目录可指定）
- 🧵 **任务线 × 会话两级模型**：同一条任务可以被 Qoder、Trae、WorkBuddy 各交一份手，彼此不覆盖；下次接管时**多个候选并立，由你选**
- 📊 **任务看板**：`board` 一行一个执行体，看得到各端进度、计划勾选、多久没动、 谁拿着锁；`--by-client` 出端视图，`--json` 可直接给面板用
- 🖥️ **页面看板**：`dash` 把 `board --json` 注入单文件 HTML（零前端依赖），双击即看；按任务线分组、进度条、锁/陈旧标记、点行看详情并一键复制接管命令；`dash --serve` 起本地服务后每 5 秒自动刷新
- 🔁 **两个固定仪式**：接管（Resume）与交出（Checkpoint），由触发词显式驱动，交接前强制复述状态
- 🚫 **Do Not Redo / Intentionally Dirty**：明确告诉下一个 agent 别重做什么、哪些文件故意不提交
- 🔒 **git 原子提交**：checkpoint 时状态文件与代码一并 commit，代码是最终真相；租约锁落在 `locks/` 且写入 `.git/info/exclude`，不污染工作区
- 🧩 **可选自动化**：无依赖 shell 脚本（init/checkpoint/status/new/resume/board/dash/tasks/switch/lock/migrate）预填交接模板；MCP server 演进路线（`get_state` / `list_sessions` / `checkpoint` / `lock`）
- 🧪 **自带冒烟测试**：`bash tests/smoke.sh` 一条命令跑完 90 项断言（含 P0 回归、页面看板与旧布局兼容，全部在临时目录内，不碰你的真实库）
- 🤖 **Agent 可自装**：`INSTALL_FOR_AGENTS.md` 让任何 agent 按指令完成安装

## 快速开始

全局模式（推荐个人使用——全机一份任务库，任何客户端、任何目录都能「继续任务」）：

```bash
git clone https://github.com/hanxu/agent-waypoint.git
cd agent-waypoint
bash scripts/waypoint.sh init-home                        # 建库 ~/.waypoint（--home 可指定）
bash scripts/waypoint.sh new 登录重构 --client qoder      # 开一条任务线，并为 qoder 这个端开会话
# 把 ~/.waypoint/RULES_SNIPPET.md 的内容贴进各客户端的用户级规则（一次）；
# 每个客户端固定用各自的 --client 名，这是会话隔离能成立的前提
```

在 Qoder 里干完活说「checkpoint」，它只写 `tasks/登录重构/sessions/qoder/`。换到另一个客户端：

```bash
bash scripts/waypoint.sh board                            # 各端现在各停在哪儿
bash scripts/waypoint.sh dash --open                      # 页面看板（生成 ~/.waypoint/dashboard.html 并打开）
bash scripts/waypoint.sh resume                           # 列出可接管会话，你选一个
bash scripts/waypoint.sh resume 登录重构/qoder --client trae   # trae 还没有会话 → 自动从 qoder 的快照继承一份
```

项目模式（状态与某个代码仓库绑定）：

```bash
cd your-project
bash /path/to/agent-waypoint/scripts/waypoint.sh init --target .
```

然后在任何客户端里立任务，干活，说「checkpoint」交接，换客户端说「继续任务」接力。详见 [QUICKSTART.md](./QUICKSTART.md) 与协议本体 [templates/PROTOCOL.md](./templates/PROTOCOL.md)。

从旧版（一个任务一份状态文件）升上来：库里的旧布局仍可读，跑一次 `bash scripts/waypoint.sh migrate` 即归位到 `sessions/<端>/`；项目模式的 `.waypoint/LOCK` 已由 `locks/` 取代，可手工删除。

## 目录

```text
agent-waypoint/
├── README.md
├── QUICKSTART.md            # 5 分钟上手
├── INSTALL_FOR_AGENTS.md    # 给 agent 看的安装指令
├── templates/               # 协议与状态文件模板（init 时复制进目标项目）
├── scripts/waypoint.sh      # init / new / resume / board / dash / checkpoint / status / lock / migrate
├── dashboard/               # 页面看板：index.html 模板 + serve.py（可选本地服务）
├── tests/smoke.sh           # 冒烟测试（无依赖，临时目录内跑）
└── docs/comparison.md       # 与 agent-handoff-kit 等同类项目的对比
```

## 与 agent-handoff-kit 的差异

[agent-handoff-kit](https://github.com/jimozo/agent-handoff-kit) 是同领域的优秀先行者，但它面向**团队多 agent 并发协作**（分支-per-agent + 人类 review 合并）。Waypoint 面向**个人跨客户端接力**：不引入分支纪律，以状态文件 + 租约锁管理互斥，补充任务契约（DoD）、决策记录与 MCP 演进路线。详细对比见 [docs/comparison.md](./docs/comparison.md)。

## Roadmap

- [x] 协议模板 + shell 脚本
- [x] 全局任务库：任务线 × 会话隔离，接管时多候选可选
- [x] `board` 命令行看板（含 `--json` 输出契约）
- [x] 页面看板 `dash`（单文件 HTML + 可选 `--serve` 自动刷新）
- [ ] 真实客户端验证矩阵（Qoder / WorkBuddy / Trae）
- [ ] 看板面板增强（搜索历史、跨库聚合、导出）
- [ ] `waypoint-mcp` MCP server

## License

MIT
