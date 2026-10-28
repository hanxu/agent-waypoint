# agent-waypoint 🪢

**任务薪火相传，客户端只是执炬人。**
**A cross-client task handoff protocol: continue your task in any AI agent client exactly where the last one left off — never start over.**

Waypoint 是一个跨 AI 客户端的任务接续协议。你在 Qoder 里跑到一半的任务，切到 Trae / WorkBuddy / 任何 agent 客户端，说一句「继续任务」，就能从断点无缝接续——不重做、不丢上下文。

它不是插件，也不装在任何一个客户端里：协议以纯文本文件（`AGENTS.md` + `.waypoint/` 目录）的形式住在你的仓库里，任何能读写文件的 agent 都是读者。

## 特性

- 📄 **纯 Markdown 协议**，零依赖，任何客户端通用；AGENTS.md 薄启动文件 + `.waypoint/PROTOCOL.md` 完整协议两层化
- 🔁 **两个固定仪式**：接管（Resume）与交出（Checkpoint），由触发词显式驱动，交接前强制复述状态
- 🚫 **Do Not Redo / Intentionally Dirty**：明确告诉下一个 agent 别重做什么、哪些文件故意不提交
- 🔒 **git 原子提交**：checkpoint 时状态文件与代码一并 commit，代码是最终真相
- 🧩 **可选自动化**：无依赖 shell 脚本（init/checkpoint/status）预填交接模板；MCP server 演进路线（`get_state` / `checkpoint` / `lock`）
- 🤖 **Agent 可自装**：`INSTALL_FOR_AGENTS.md` 让任何 agent 按指令完成安装

## 快速开始

```bash
git clone https://github.com/hanxu/agent-waypoint.git
cd your-project
bash /path/to/agent-waypoint/scripts/waypoint.sh init --target .
```

然后在任何客户端里立任务（填 `.waypoint/TASK.md` + `PLAN.md`），干活，说「checkpoint」交接，换客户端说「继续任务」接力。详见 [QUICKSTART.md](./QUICKSTART.md) 与协议本体 [templates/PROTOCOL.md](./templates/PROTOCOL.md)。

## 目录

```text
agent-waypoint/
├── README.md
├── QUICKSTART.md            # 5 分钟上手
├── INSTALL_FOR_AGENTS.md    # 给 agent 看的安装指令
├── templates/               # 协议与状态文件模板（init 时复制进目标项目）
├── scripts/waypoint.sh      # init / checkpoint / status
└── docs/comparison.md       # 与 agent-handoff-kit 等同类项目的对比
```

## 与 agent-handoff-kit 的差异

[agent-handoff-kit](https://github.com/jimozo/agent-handoff-kit) 是同领域的优秀先行者，但它面向**团队多 agent 并发协作**（分支-per-agent + 人类 review 合并）。Waypoint 面向**个人跨客户端串行接力**：不引入分支纪律，以状态文件 + LOCK 管理互斥，补充任务契约（DoD）、决策记录与 MCP 演进路线。详细对比见 [docs/comparison.md](./docs/comparison.md)。

## Roadmap

- [x] 协议模板 + shell 脚本
- [ ] 真实客户端验证矩阵（Qoder / WorkBuddy / Trae）
- [ ] `waypoint-mcp` MCP server
- [ ] 状态总览面板

## License

MIT
