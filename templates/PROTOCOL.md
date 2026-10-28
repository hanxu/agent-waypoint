# Waypoint 协议（完整版）

> 本文件是 Waypoint 协议的单一真相源（single source of truth）。
> 项目根目录的 `AGENTS.md` 只是本协议的薄摘要；两者冲突时以本文件为准。

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
├── LOCK             # 任务锁：当前哪个客户端在跑（防并行）
└── archive/         # 已完结任务的归档（原 .waypoint 文件移入）
```

分工要点：

- **HANDOFF.md** 给「下一个 agent」：浓缩上下文，硬性一页以内，宁可短不可长；溢出内容沉入 JOURNAL
- **JOURNAL.md** 给「三天后的你」：完整历史，只追加、永不改写
- 一个负责「新」，一个负责「全」，所以一个重写、一个追加

## 3. 三个仪式

### 3.1 接管仪式（Resume）

触发：用户说「继续任务」/「/resume」，或会话开场即有 HANDOFF.md。

1. 依序读 `HANDOFF.md` → `TASK.md` → `PLAN.md`，再 `git log --oneline -10` + `git status`
2. 核对叙事状态与 git 现状；**不一致时以 git 为准**并明确指出差异
3. 检查 `LOCK`：若属于其他客户端，停下询问用户
4. 用固定格式复述（生成即理解，给用户一个纠偏机会）：

   > 我已接管任务「XXX」。当前状态：…；已完成：…；下一步：…；发现差异：…。若无误我将从「YYY」继续。

5. 写 `LOCK`：`<客户端名> <ISO 时间>`
6. 从 HANDOFF 标注的「下一步」开始执行

### 3.2 交出仪式（Checkpoint）

触发：用户说「checkpoint」/「告一段落」/「我要切到 XX 了」；或每完成一个迭代主动做。

1. 确认工作区状态：默认必须干净。确有不应提交的文件，逐个列入 HANDOFF 的 Intentionally Dirty 段
2. 勾选 `PLAN.md`；向 `JOURNAL.md` **追加**一条（格式见 §4.4）
3. **整体重写** `HANDOFF.md`（模板见 §4.3），必须包含 Do Not Redo 与 Intentionally Dirty
4. `git add -A && git commit -m "waypoint: <一句话摘要>"` —— 状态文件与代码原子提交
5. 删除 `LOCK`
6. 向用户输出交接摘要（一段话即可）

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

任一条不过 → 让它 `cat AGENTS.md` 验证文件是否被加载，退回 §5 换注入方式。

## 7. 自动化演进（可选）

- **waypoint CLI**（`scripts/waypoint.sh`）：`init` / `checkpoint` / `status`，checkpoint 自动抓取 git 事实预填交接模板
- **waypoint-mcp**：MCP server 暴露 `get_state` / `checkpoint` / `lock` 三个工具；工具调用比读文件更不易被遗漏，Qoder/WorkBuddy/Trae/Cursor 均支持挂载。纯文件协议永远是兜底
- **git hook**（可选）：pre-commit 检查代码改动但 JOURNAL 无新条目时提醒
- **状态面板**（可选）：读所有项目的 `.waypoint/` 渲染任务总览

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| 状态文件与代码漂移 | checkpoint 强制绑 commit；git 为最终真相 |
| HANDOFF 越写越长 | 硬性一页限制，溢出沉入 JOURNAL |
| Agent 忽略协议 | 触发词显式触发；AGENTS.md 两层化（薄摘要+深协议）提高遵守率 |
| 两客户端并行 | LOCK 互斥；发现他人锁先询问 |
| 敏感信息入库 | `.waypoint/` 加入 .gitignore，退化为本机共享 |
