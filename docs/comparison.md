# Waypoint 与同类项目对比

对比对象：[jimozo/agent-handoff-kit](https://github.com/jimozo/agent-handoff-kit)（2026-10 读取其仓库源码得出）。

## 定位差异

| | agent-handoff-kit | Waypoint |
|---|---|---|
| 核心场景 | 多个 agent **同时**在一个仓库干活，人类 review 后合并 | 一个人的任务在客户端之间**串行接力** |
| 状态载体 | git 分支（每 agent 一条 `codex/`、`claude/` 分支）+ 会话日志 | 仓库内状态文件（`.waypoint/`） |
| 交接粒度 | 三模式：同工具换会话 / 跨工具中途接力（CONTINUE.md）/ 完成交接 | 两仪式：接管 / 交出（+ 归档） |
| 多端并存 | 每 agent 一条分支 + SESSIONS.md 最近 4 条轮转 | **任务线 × 会话隔离**：`sessions/<端>/` 各一份，接管时列候选由人选 |
| 状态总览 | 无专用视图 | `board`（各端进度/陈旧/锁）+ `--by-client` 端视图 + `--json` 输出契约 |
| 可视化 | 无 | `dash`：本地看板**服务**（HTTP + SSE 推送，仅标准库），页面自动刷新、多标签也只采集一次；分组卡片/进度条/锁与陈旧标记/详情抽屉/一键复制接管命令；`dash export` 另存离线快照 |
| 防冲突 | 分支隔离 + 冲突处理规则 | `locks/` 租约锁（按线/端互斥，带过期与抢占提示） |
| 进度契约 | 无（无任务目标/验收标准概念） | TASK.md（DoD）+ PLAN.md |
| 自检 | `validate.sh`（占位符/字段/条目数 doctor）、`install.sh --upgrade` + 版本号 | `tests/smoke.sh` 冒烟测试（104 项断言，含看板服务与 SSE 回归）；尚无 doctor 与升级命令 |

它最贴近本需求的机制是 agent-switch handoff：先 commit 一个 WIP 检查点 → 留 CONTINUE.md 接力条 → 换工具读它 → 消费完删掉。原则："the next tool reads committed state, not uncommitted memory"。

## 从它吸收的设计

1. **Do Not Redo 段落**：交接快照明确列出"已做过、勿重做勿回退"的工作，防止新客户端好心重刷
2. **Intentionally Dirty 段落**：默认工作区必须干净；故意不提交的文件逐个列出并说明
3. **脚本预填交接信息**：`handoff.sh` 自动抓取 git 事实填模板，agent 只补叙事——Waypoint 的 `waypoint.sh checkpoint` 同思路
4. **AGENTS.md 两层化**：薄启动文件（每会话必读，越短遵守率越高）+ 深协议文档按需读
5. **INSTALL_FOR_AGENTS.md**：让 agent 自己按指令安装协议

## 有意保持的差异

1. **不采用分支-per-agent**：团队并发解法；个人接力用当前分支 + 会话目录隔离更简单
2. **不采用"接力条用后即删"（CONTINUE.md）**：Waypoint 的 HANDOFF.md 每个端永远只有一份且每次整体重写，不存在过时副本，且保留"三天后回来还能看到停在哪"的价值
3. **不采用 SESSIONS.md 只留最近 4 条的轮转**：HANDOFF（热）与 JOURNAL（冷，append-only）分工已防住日志膨胀
4. **补充它没有的**：任务契约（DoD）、决策记录、租约锁、跨端看板与会话隔离、触发词体系、客户端接入指南、MCP 化
5. **还欠它的**：安装自检 doctor（检查未填占位符/必填字段）、带版本号的 `--upgrade`。列入待做
