# Waypoint 协议（完整版）

> 本文件是 Waypoint 协议的单一真相源（single source of truth）。
> 项目根目录的 `AGENTS.md` 只是本协议的薄摘要；两者冲突时以本文件为准。

## 0. 部署模式

两种部署模式，仪式与文件模板完全一致，仅状态存放位置和注入方式不同：

| | 项目模式（§2-§8） | 全局模式（§9） |
|---|---|---|
| 适用 | 任务绑定某个代码仓库 | 全机一份任务库，任务不绑定项目（调研/跨项目事务/个人待办） |
| 状态位置 | 项目内 `.waypoint/` | `~/.waypoint/tasks/<任务线>/sessions/<端>/`（`--home`/`WAYPOINT_HOME` 可改） |
| 注入 | 项目根 AGENTS.md | 客户端**用户级规则**（RULES_SNIPPET.md，一次配置全项目生效） |
| 多任务 | 一仓库一任务 | 多任务线 × 多会话（端）并存，`board` 总览、`resume` 列表可选 |
| git 真相 | 项目仓库（状态与代码原子绑定） | 全局库自身是 git 仓库；代码状态靠 JOURNAL 锚定项目 HEAD |

## 1. 问题与思路

一个跑了 N 轮迭代的任务，其「进度」由四部分组成：

| 进度要素 | 存在哪 | 跨客户端？ |
|---|---|---|
| 代码/工件现状 | 文件系统 + git | ✅ 天然共享 |
| 任务目标与验收标准 | 客户端私有会话 | ❌ |
| 计划与剩余工作 | 客户端私有 todo | ❌ |
| 经验记忆（踩坑、决策） | 客户端私有上下文 | ❌ |

Waypoint 的做法：**把右侧三项外化为仓库内的纯文本文件**，让所有客户端退化为无状态执行器。会话格式（各家私有存储）不迁移——迁移的是状态的浓缩物，不是对话本身。

设计原则：

1. **状态外化**：跨轮次需要记住的东西全部落文件，不依赖任何客户端记忆
2. **文件协议是最低公分母**：任何能读写文件的 agent 都能参与；MCP/CLI 只是增强
3. **交接靠仪式不靠自觉**：两个固定仪式由 AGENTS.md 注入，用触发词显式触发
4. **git 是最终真相**：每次交接绑定 commit，代码与状态永不漂移；冲突时以 git 为准

## 2. 目录结构

```
.waypoint/
├── TASK.md          # 任务合同：背景、目标、DoD 验收标准（很少改动）
├── PLAN.md          # 计划 checklist，随进度勾选
├── HANDOFF.md       # ⭐ 交接快照：唯一"热"文件，每次交出时整体重写
├── JOURNAL.md       # append-only 编年日志，每轮迭代追加一条
├── DECISIONS.md     # 决策记录（选型、放弃的方案及原因）
├── locks/           # 租约锁：<会话>.lock（本地运行时产物，不入库）
└── archive/         # 已完结任务的归档（原 .waypoint 文件移入）
```

**`locks/` 不入版本库**：`init` 会把 `.waypoint/locks/` 写进 `.git/info/exclude`（本地生效、不改动用户 `.gitignore`、不会被提交）。锁是运行时状态，不是任务状态，把它 commit 进仓库会污染工作区并让下一次 checkpoint 误判为脏。

分工要点：

- **HANDOFF.md** 给「下一个 agent」：浓缩上下文，硬性一页以内，宁可短不可长；溢出内容沉入 JOURNAL
- **JOURNAL.md** 给「三天后的你」：完整历史，只追加、永不改写
- 一个负责「新」，一个负责「全」，所以一个重写、一个追加

## 3. 三个仪式

### 3.1 接管仪式（Resume）

触发：用户说「继续任务」/「/resume」，或会话开场即有 HANDOFF.md。

1. **先列候选再动手**：全局模式下运行 `waypoint.sh resume`（不带参数）列出所有可接管会话，交给用户选；项目模式直接读本仓库 `.waypoint/HANDOFF.md`
2. 依序读 `HANDOFF.md` → `TASK.md` → `PLAN.md`，再 `git log --oneline -10` + `git status`
3. 核对叙事状态与 git 现状；**不一致时以 git 为准**并明确指出差异
4. 检查锁：若租约属于其他端且未过期，停下询问用户（确认后 `--force` 抢占，别静默抢）
5. 用固定格式复述（生成即理解，给用户一个纠偏机会）：

   > 我已接管任务「XXX」。当前状态：…；已完成：…；下一步：…；发现差异：…。若无误我将从「YYY」继续。

6. 取锁：`waypoint.sh lock --target .`（写 `.waypoint/locks/`，租约默认 45 分钟；全局模式则是 `resume <线>/<端>` 自动取锁）
7. 从 HANDOFF 标注的「下一步」开始执行

### 3.2 交出仪式（Checkpoint）

触发：用户说「checkpoint」/「告一段落」/「我要切到 XX 了」；或每完成一个迭代主动做。

1. 确认工作区状态：默认必须干净。确有不应提交的文件，逐个列入 HANDOFF 的 Intentionally Dirty 段
2. 勾选 `PLAN.md`；向 `JOURNAL.md` **追加**一条（格式见 §4.4）
3. **整体重写** `HANDOFF.md`（模板见 §4.3），必须包含 Do Not Redo 与 Intentionally Dirty
4. （全局模式）更新本会话 `.session` 的 `last_epoch`/`last_checkpoint`（看板与候选排序以此为准）
5. `git add -A && git commit -m "waypoint: <一句话摘要>"` —— 状态文件与代码原子提交
6. 释放锁：`waypoint.sh unlock --target .`（全局模式：`unlock --line <线> --sid <端>`）
7. 向用户输出交接摘要（一段话即可）

核心原则：**下一个工具读的是已提交状态，不是你的记忆。**

### 3.3 归档仪式（Archive）

触发：用户说「任务完成」，或 PLAN.md 全部勾选且 DoD 全部验证通过。

1. 跑一遍完整验收清单，逐条确认 DoD
2. 最后一次 checkpoint（正常执行 §3.2）
3. 在 `HANDOFF.md` 顶部标注 `# ✅ 已完结`
4. 将本次任务的五个状态文件移入 `.waypoint/archive/<日期>-<任务短名>/`
5. 在 `.waypoint/` 根下为新任务重建空白模板

## 4. 文件模板

### 4.1 TASK.md（立项时写一次）

```markdown
# 任务：<一句话标题>

## 背景
为什么做这件事（1-3 句）

## 目标（DoD 验收标准）
- [ ] <可验证的标准，不含"差不多">

## 约束
技术栈、不许动的东西、风格要求
```

### 4.2 PLAN.md

```markdown
# 计划

- [ ] 步骤 1：<动词开头，粒度以一个迭代能完成为宜>
- [ ] 步骤 2：…
```

### 4.3 HANDOFF.md（每次交出整体重写）

```markdown
# 交接快照 — <ISO 时间> by <客户端名>

## 任务一句话
<从 TASK.md 提炼>

## 当前状态
<处于哪个阶段；最近一次验证结果（测试/编译/运行），逐条列出命令与结果>

## 已完成（≤5 条）
-

## 下一步（具体到可直接执行的第一条指令）
1.

## Do Not Redo（已做过、勿重做勿回退的工作）
-

## Intentionally Dirty（未提交但属故意的文件）
- 无 / <路径：原因>

## 关键坑与约束（≤5 条）
-

## 恢复入口
- 必读：.waypoint/TASK.md、.waypoint/PLAN.md、git log -10
```

### 4.4 JOURNAL.md 条目（只追加）

```markdown
## [<ISO 时间>] <客户端名> · 迭代<N>
- 做了什么：
- 改动：<文件列表>
- 验证：<命令 → 结果>
- 踩坑：<可空>
- 下一步：
- commit：<短 hash>
```

### 4.5 DECISIONS.md 条目（只追加）

```markdown
## [<日期>] <决策一句话>
- 备选方案：
- 选择及原因：
- 放弃方案的原因：
```

## 5. 客户端接入

任何客户端按优先级三选一：

1. **读 AGENTS.md** → 零成本接入
2. **项目规则文件**（`.trae/rules/`、自定义指令等）→ 放一行指针：`本项目的 AI 协作协议见根目录 AGENTS.md（任务接管/交出仪式），必须遵守`
3. **兜底 bootstrap 提示词**（接管时粘贴）：

```text
接管任务：阅读 .waypoint/HANDOFF.md、.waypoint/TASK.md、.waypoint/PLAN.md，
执行 git log --oneline -10 核对状态，复述当前进度和下一步，
等我确认后继续执行。全程遵守 AGENTS.md 中的协作协议。
```

已知客户端：

- **Qoder**：原生读 AGENTS.md（`/init` 初始化）；首次使用跑一次 `/init` 确认加载
- **Trae**：支持 AGENTS.md，也可在 `.trae/rules/project_rules.md` 放指针
- **WorkBuddy**：支持自定义指令与 MCP；规则里放指针；派任务时把触发词写进任务描述
- **Cursor / Codex / ZCode 等**：同规则 1 或 2

## 6. 验收清单（每个新客户端接入后验一次）

- [ ] 新开会话不提示背景，问「这个项目的协作协议是什么」→ 能说出 `.waypoint/` 和仪式
- [ ] 说「继续任务」→ 读了 HANDOFF 并复述状态，而非从头开始
- [ ] 说「checkpoint」→ 重写 HANDOFF、追加 JOURNAL 并 commit
- [ ] 换下一个客户端重复以上 → 状态无缝衔接
- [ ] 全局模式：说「各端进度」/「任务看板」→ 能跑 `board` 并按端报出进度
- [ ] 全局模式：说「继续任务」→ **先列候选会话让我选**，而不是直接接 CURRENT 或 自己猜一个
- [ ] 全局模式：`dash` 能起看板服务并打开页面，页面上的会话数/锁标记与 `board` 一致，且数据变化后不刷新也能自动更新

任一条不过 → 让它 `cat AGENTS.md` 验证文件是否被加载，退回 §5 换注入方式。

## 7. 自动化演进（可选）

- **waypoint CLI**（`scripts/waypoint.sh`）：`init` / `checkpoint` / `status` / `resume` / `board` / `dash`，checkpoint 自动抓取 git 事实预填交接模板
- **waypoint-mcp**（演进）：MCP server 暴露 `get_state` / `list_sessions` / `checkpoint` / `lock`；工具调用比读文件更不易被遗漏，Qoder/WorkBuddy/Trae/Cursor 均支持挂载。纯文件协议永远是兜底
- **git hook**（可选）：pre-commit 检查代码改动但 JOURNAL 无新条目时提醒
- **状态面板**：`board --json` 是稳定输出契约，`dash` 基于它做成**本地看板服务**（HTTP + SSE 推送，全局会话 + 项目模式仓库两部分）；后续的面板/小程序/机器间同步都从同一份 JSON 出发，不要在页面或服务里另写数据采集逻辑

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| 状态文件与代码漂移 | checkpoint 强制绑 commit；git 为最终真相 |
| HANDOFF 越写越长 | 硬性一页限制，溢出沉入 JOURNAL |
| Agent 忽略协议 | 触发词显式触发；AGENTS.md 两层化（薄摘要+深协议）提高遵守率 |
| 两客户端并行 | `locks/` 租约锁按会话互斥（不同线/不同端可并行）；他人有效租约拒绝接管，只能 `--force` 显抢占 |
| 锁文件污染工作区 | 锁落在 `locks/` 并写入 `.git/info/exclude`，不入版本库 |
| 任务库误建进别人的仓库 | `init-home` 检测 `repo_root != HOME` 则拒绝（需 `--home` 换路径或 `--force` 确认） |
| 客户端名字写错会开新会话 | 端名归一化为 `[a-z0-9._-]`；RULES_SNIPPET 中约定每个客户端固定用一个名字，`board --by-client` 可校对 |
| 敏感信息入库 | 项目模式：`.waypoint/` 加 .gitignore；全局模式：库不 push 到公共远程 |

## 9. 全局模式（home 模式）

适用：任务不绑定单一项目，或希望全机只维护一份任务库。默认目录 `~/.waypoint`，`init-home --home <目录>` 或环境变量 `WAYPOINT_HOME` 可指定。

### 9.1 两层对象：任务线 × 会话

- **任务线（line）**：一件事的「合同，很少变」——`TASK.md`（目标与 DoD）、`project.txt`（可选项目锚）。同一条线可以被多个端接力。
- **会话（session，按端隔离）**：某个客户端在这件事上的**工作日程**——`PLAN/HANDOFF/JOURNAL/DECISIONS.md` + `.session` 元数据。

为什么要分会话：多个客户端各自 `checkpoint` 时，如果共写一份 HANDOFF，后来者会覆盖前者；拆成会话后，**「多少个端交过手」变成「多少个可接管任务」**，接管时由用户选，而不是静默拿到别人的上下文。

```
~/.waypoint/                    # 全局库（自身是独立 git 仓库）
├── PROTOCOL.md                 # 本协议副本
├── RULES_SNIPPET.md            # ⭐ 注入文本：贴进各客户端用户级规则（路径权威记录）
├── CURRENT                     # 当前会话指针，格式 <线>/<端>
├── repos.txt                   # 项目模式已登记仓库（board 读取）
├── locks/<线>__<端>.lock     # 租约锁，不入库
├── tasks/<线>/
│   ├── TASK.md                 # 线级：背景/目标/DoD（共享）
│   ├── project.txt             # 可选：锚定的项目仓库绝对路径（首行）
│   └── sessions/<端>/
│       ├── PLAN.md HANDOFF.md JOURNAL.md DECISIONS.md
│       └── .session            # line/sid/client/parent/status/last_epoch/last_head
└── archive/                    # 完结任务归档（<完结日期>-<线>/）
```

`.session` 关键字段：`parent` 记本会话从哪个端继承（接链可追溯）；`last_epoch` 是看板排序与陈旧判定的唯一依据（交出时必更新）。旧版单文件布局（状态文件直放线目录）仍可读，`migrate` 一键归位到 `sessions/<端>/`。

### 9.2 命令（scripts/waypoint.sh）

```
init-home [--home D] [--force]                建库（独立仓库；发现寄宿则拒绝）
new <线> [--client C] [--sid S] [--project P]  开一条线并为本端开会话
resume                                         ⭐ 列出全部可接管会话（按最近交出排序）
resume <线>/<端> [--client C] [--force]      接管并取锁；本端无会话则从源会话继承新建
checkpoint [--line L] [--sid S] [--client C]  交出到本端会话（预填 git 事实）
board [--json] [--by-client] [--stale-days N]  ⭐ 各端任务总览（含项目模式仓库）
dash [serve] [--port N] [--open] [--daemon]   🖥️ 看板服务（默认取法；stop/status 管控）
dash export [--out F] [--open]                导出离线快照（转发/看历史用）
tasks / switch <线> [端] / status [--line L] [--sid S]
lock / unlock / who                            手动租约锁（默认 45 分钟）
migrate [--force]                              旧布局 → 会话布局
repos ls                                       已登记的项目模式仓库
```

全局参数 `--home/--line/--sid/--client/--json` 等写在子命令前后都成立；`--task <线>` 是 v1 兼容别名。

### 9.3 两个核心行为

**接管先列候选**（对应“多个客户端 checkpoint 后下次可选”）：

1. `waypoint.sh resume` 输出每行的：线/端、端名、计划进度、最近交出时间、锁定/陈旧标记、下一步摘要
2. agent **不得代选**：把候选给用户，除非用户已明说接哪一个
3. 选定后：若本端已有会话→直接接管；若没有→自动新建 `sessions/<本端>` 并从源会话拷贝 PLAN/HANDOFF/JOURNAL/DECISIONS，`parent` 记录来源

**看板**（对应“看到各端任务情况”）：`board` 同时读全局会话与 `repos.txt` 登记的项目仓库，一行一个执行体；`--by-client` 看端视图（每个端多少会话、有无活跃锁、最近活动）；`--json` 输出可发面板。

**看板服务**（给人看的，不需要终端）：`dash` 在 `127.0.0.1:8787` 起一个只读看板服务（仅 python3 标准库），打开页面即见：按任务线分组的会话行、计划进度条、锁/陈旧/继承标记、点行展开详情（目录、父会话、JOURNAL 条数、下一步全文）并一键复制接管命令。数据由服务端每 5 秒采集一次并通过 SSE 推送给所有页面——**多个标签页也只跑一次 `board --json`**，页面无需轮询、无需刷新。`--daemon` 让服务后台常驻（pid/端口写 `dash.run`，日志 `dash.log`，均不入库），`dash stop` 停、`dash status` 看健康。`dash export` 是次要形态：把数据注入单文件 HTML 存成离线快照，用于转发给别人或看历史（`file://` 下没有服务，页面会显示“离线快照”）。

### 9.4 仪式差异（相对 §3）

- **接管**：先 `resume` 列候选让用户选；默认只看 CURRENT
- **交出**：只写**本端会话目录**（别动别人的）→ 若有 project.txt，在 JOURNAL 记录该项目分支与 HEAD → 更新 `.session` 的 `last_epoch` → 在全局库 `git add tasks/<线> && git commit -m "waypoint: <摘要>"` → `unlock`
- **归档**：`mv tasks/<线> archive/<完结日期>-<线>` 后 commit
- 关联项目的**代码提交仍在项目仓库正常进行**；全局库只存任务叙事状态，两者靠 JOURNAL 记录的项目 HEAD 锚定

### 9.5 注入（关键差异）

项目模式靠项目 AGENTS.md；全局模式注入进客户端的**用户级/全局规则**（对所有会话生效）：

- 把 `RULES_SNIPPET.md` 的内容贴进：Qoder 的用户级 Rules / Trae 的 `user_rules.md` / 其他客户端的全局指令
- **每个客户端在规则里固定一个端名**（如 `qoder`/`codebuddy`/`trae`），所有命令都带 `--client <端名>`——这是会话隔离能成立的前提
- RULES_SNIPPET 中记录的数据目录路径是**权威记录**，agent 不得凭记忆猜路径
- 兜底：新会话粘贴 bootstrap——「接管任务：数据目录见全局规则（默认 ~/.waypoint），先跑 `waypoint.sh resume` 列出候选让我选，然后读所选会话的 HANDOFF.md，复述状态后继续，遵守 ~/.waypoint/PROTOCOL.md」
