# 任务：把 waypoint 从"只有脚本"推进到"有页面看板的个人工作台"

## 背景

协议与 shell 脚本已经能跑（任务线 × 会话、租约锁、board 命令），但所有状态都要在终端里读。实际使用时"我现在各端干到哪儿了"需要一眼能看到的界面，而不是滚终端输出。

## 目标（DoD 验收标准）

- [x] `waypoint.sh dash` 一条命令产出可双击打开的单文件 HTML 看板，零前端依赖、离线可用
- [x] 看板按任务线分组展示每个会话：端名、计划进度、最近活动、锁/陈旧/继承标记、下一步
- [x] 点行展开详情，并能一键复制接管命令（`resume 线/端 --client 端`、会话目录、status）
- [x] 底部展示 `repos.txt` 登记的项目模式仓库进度
- [x] `dash --serve` 提供本地实时刷新（每 5 秒），静态与实时两种形态共用同一份 `board --json`
- [x] 看板产物不污染任务库 git 状态（写入 `.git/info/exclude`）
- [x] 冒烟测试覆盖页面看板，全绿（93 项）
- [x] 文档同步：README / QUICKSTART / PROTOCOL §6§7§9 / AGENTS 触发词 / INSTALL_FOR_AGENTS / comparison

## 约束

- 运行期零依赖：只用 bash 3.2 + BSD 工具链；`--serve` 允许 python3 标准库，且必须是可选项
- 数据源唯一：页面只消费 `board --json`，不得在页面里另写采集逻辑（PROTOCOL §7）
- 不改协议语义：两份产物（board / dash）读同一份状态，看板不能成为第二真相
- 未经用户同意不得提交、不得改动 `~/.waypoint` 真实库
