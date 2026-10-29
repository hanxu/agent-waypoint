# 交接快照 — 2026-10-29T11:02:41+0800 by qoder

## 任务一句话

把 waypoint 从"只有脚本"推进到"有页面看板的个人工作台"：`board --json` 保持唯一数据源，`dash` 把它渲染成可双击打开的单文件页面。

## 当前状态

功能完成、验证通过、**已落盘**。本轮合成一个提交（父提交 `1da636e`，本提交 hash 见 `git log -1`）；提交后工作区干净，`status --target .` 显示计划 18/19（剩一项等你决策）。

最近一次验证（本机 macOS / bash 3.2 + BSD 工具链）：

```
bash tests/smoke.sh                → 通过 93 / 失败 0
bash scripts/waypoint.sh help      → 22 行（不再泄漏脚本正文）
bash scripts/waypoint.sh dash --out /tmp/x.html → 生成 ~28KB，占位符 0 残留
bash scripts/waypoint.sh checkpoint --target . --allow-dirty --client qoder → 事实输出正常
```

浏览器三轮回访（Playwright/CDP 视口 407 宽与 1440 宽）：5 个统计块、3 张任务线卡、4 个会话行；筛选「被锁」1 行、「陈旧」1 行；搜索「支付」1 行；抽屉字段齐全且命令可复制；407px 下 `scrollWidth == clientWidth`；`--serve` 下 5 秒轮询跨轮询保持键盘焦点；console 0 报错。

## 已完成（≤5 条）

- `scripts/waypoint.sh`：新增 `dash`（`--out/--open/--serve/--port`），`board --json` 补 `title/parent/journal/dir/project/cur/branch/stale_days`，`json_escape` 转义 `<`/`>`
- `dashboard/index.html`：单文件页面看板（统计/分组卡片/进度条/筛选/搜索/详情抽屉/可复制命令/空态/暗亮自适应）
- `dashboard/serve.py`：python3 标准库本地服务，`/` 现渲染、`/api/board` 现算，仅监听 127.0.0.1
- `tests/smoke.sh`：从 77 → 93 项断言，新增页面看板组与三条反直觉回归
- 文档同步：README / QUICKSTART / PROTOCOL（§6 §7 §9.2 §9.3） / AGENTS 触发词 / INSTALL_FOR_AGENTS / docs/comparison.md

## 下一步（具体到可直接执行的第一条指令）

1. **等用户决策（阻塞项）**：是否刷新真实库 `~/.waypoint`——它是旧版初始化，缺 `locks/` `repos.txt` `CURRENT`，且 `PROTOCOL.md` / `RULES_SNIPPET.md` 是旧版（没有“resume 先列候选不得代选”等新约定）。刷新必须重新生成 `RULES_SNIPPET.md`（含库路径与脚本路径）而非照抄模板
2. 同样等决策：是否在 `~/.waypoint` 建第一条真实任务线（`new <线> --client <端>`）并出真实数据版 `dash`
3. 若继续开发：先跑 `bash tests/smoke.sh` 确认 93 项仍全绿，再动 `cmd_dash` / `dashboard/index.html`
4. 欠账（已记入 docs/comparison.md）：`validate` doctor、带版本号的 `--upgrade`
5. 可选：真实客户端验证矩阵（Qoder / WorkBuddy / Trae）——用 `--client` 各跑一轮接管/交出

## Do Not Redo（已做过、勿重做勿回退的工作）

- 不要再用 awk「整行替换」注入占位符：`__WAYPOINT_DATA__` 与 `<script id="wp-data">` 同行，必须 substr 级替换
- 不要在 `usage()` 里用未锚定的 `/# USAGE-BEGIN/,/# USAGE-END/p`：函数自身定义行会重新开启范围
- 不要用 `printf | grep -q` 做断言：pipefail 下会因 SIGPIPE 误报
- 不要再让 `dash` 产物落在库内而不 exclude：会让 `checkpoint` 判脏
- 不要用 `git reset --hard 1da636e` 清历史：会丢工作区改动，用 `--soft`
- 不要在页面里新增数据采集逻辑：只消费 `board --json`

## Intentionally Dirty（未提交但属故意的文件）

- 无。本轮改动已随前述单个提交落盘；`.waypoint/locks/` 已被 `.git/info/exclude` 排除

## 关联项目（全局模式且锚定了项目时填，无则写"无"）

- 无（项目模式：状态与代码同在 `/Users/pc/study/agent-waypoint`）

## 关键坑与约束（≤5 条）

- macOS 无 GNU awk 的 `systime/strftime`、BSD sed 无 `\|` 交替：候选列表与时间格式化一律用纯 bash 或只用算术
- `set -e` 下函数末尾的 `[[ ]] && cmd` 失败会让脚本以 1 退出；脚本末尾显式 `exit 0`
- `$VAR` 紧跟中文标点会被并入变量名，双引号内一律写 `${VAR}`
- `mktemp -d` 在 macOS 返回 `/var` 符号链接路径，与 `git rev-parse --show-toplevel` 实路径不一致，测试里要 `pwd -P`
- 测试与演示一律用 `--home "$(mktemp -d)"`，绝不写真实库 `~/.waypoint`

## 恢复入口

- 必读：同目录 `TASK.md`、`PLAN.md`、`PROTOCOL.md`（协议本体）、`JOURNAL.md`（迭代 3 有全部踩坑细节）
- 代码入口：`scripts/waypoint.sh` 的 `cmd_dash` / `cmd_board` / `dash_template`；页面模板 `dashboard/index.html`；服务 `dashboard/serve.py`
- 验证入口：`bash tests/smoke.sh`（9 组 93 项，全临时目录）
- 看板：`bash scripts/waypoint.sh dash --open`
