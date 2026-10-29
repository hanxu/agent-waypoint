# 日志（append-only，永不改写历史）

## [2026-10-29T11:02:41+0800] qoder · 迭代 3（页面看板）

- 做了什么：给 `waypoint.sh` 加 `dash` 子命令，把 `board --json` 注入单文件 HTML，产出可双击打开的页面看板；附 `--serve` 本地实时刷新。
- 改动：新增 `dashboard/index.html`（模板，占位符 `__WAYPOINT_DATA__`）、`dashboard/serve.py`（python3 标准库 HTTP，`/` 现渲染 + `/api/board`）、`tests/smoke.sh` 第 9 组；`scripts/waypoint.sh` 增 dashboard 逻辑与 JSON 字段，并修三处缺陷（见踩坑）。
- 验证：
  - `bash tests/smoke.sh` → 通过 93 / 失败 0（原 77，新增页面组 7 条 + 帮助回归 + 产品安全 3 条）
  - `bash scripts/waypoint.sh dash --out /tmp/x.html` → 生成 28KB 单文件，占位符 0 残留
  - 浏览器三轮回访：5 个统计块 / 3 张线卡 / 4 个会话行；筛选（被锁 1、陈旧 1）、搜索「支付」→ 1 行；抽屉字段齐全；407px 下 scrollWidth==clientWidth；5 秒轮询跨轮询保住键盘焦点；console 0 报错
- 踩坑：
  1. 占位符与 `<script id="wp-data">` 同在一行，awk 整行替换把标签一起吃 → 静态页白屏并把原始 JSON 当正文。改 substr 级替换。
  2. `usage()` 用 `sed -n '/USAGE-BEGIN/,/USAGE-END/p' "$0"` 读脚本自身，而函数定义行自身含这两个词，范围结束后被重新开启 → help 一路打印到文件末尾。改 `^...$` 锚定，并加回归断言。
  3. `assert_contains` 用 `printf | grep -q`，pipefail 下 grep 提前退出触发 SIGPIPE，大输出时误报失败。改纯 bash `case`。
  4. `$VAR` 紧跟中文全角标点会被并入变量名（`$DASH_PORT；` → unbound variable）。全量扫描后加花括号。
  5. 页面产物落在 `~/.waypoint/dashboard.html` 会把库弄脏，导致下次 checkpoint 被拒 → 写进 `.git/info/exclude`（与 locks/ 同法）。
  6. 项目模式 checkpoint 自身两个缺陷：客户端名输出字面 `${当前客户端名}`；「改动概览」误抓 `HEAD~1`（上一个提交）而不是工作区。两者都在本轮用自己工具给自己交出时暴露并修掉。
- 下一步：提交本轮改动；再决定是否刷新真实库 `~/.waypoint`（旧版 PROTOCOL.md / RULES_SNIPPET.md）。
- commit：随本提交落盘（父提交 `1da636e`）

## [2026-10-29T11:45:00+0800] qoder · 迭代 4（看板服务化）

- 做了什么：用户要求“看板做成服务，不是一个静态页面”→ `dash` 默认改为起本地 HTTP 服务，页面改 SSE 订阅；静态只保留为 `dash export`。
- 改动：`dashboard/serve.py` 重写（SSE 推送 + 2 秒采集缓存 + `/api/board` `/api/ping` + 端口自动 +1 + `--port-file`）；`dashboard/index.html` 换 EventSource（去轮询）、抽屉抽 `fillDrawer` 随推送刷新、文案区分实时/离线；`scripts/waypoint.sh` 新增 `dash serve|export|stop|status`、`--daemon`、单实例检查（`dash_running`）、`dash.run`/`dash.log` 排除。
- 验证：
  - `bash tests/smoke.sh` → 104 / 0（新增第 10 组 11 条：daemon、pid 文件、status 健康检查、单实例、/api/board、/ 注入、SSE 首帧、运行期不脏库、stop）
  - curl 实测：`/api/ping` → `{"ok":true}`；`/api/events` → `retry: 2000` + `data: {...}`；端口 8799 被占时自动降 8800
  - 浏览器：同一次导航内（`performance.now` 单调、`navigation.length=1`）行数 55 → 64，meta 快照时间 11:41:30 → 11:42:13；按钮“实时 · 重连”、页脚“服务推送（SSE）”；抽屉时焦点仍在 `#d-close`；console 0 错；407/407 无横向溢出；抽屉里“最近活动”从 4 分钟前变 5 分钟前（证明重绘）
- 踩坑：
  1. 连起两个 `--daemon` 时 pid 文件互相覆盖，前一个变孤儿（实测只能停掉后一个）→ 加 `dash_running` 单实例检查。
  2. 验收“行数增长”两次因为喂数据脚本比观测早跑完而假失败 → 服务与页面没问题，是受测编排的时序问题；第三次改成“观测窗口内持续喂”才拿到 55 → 64。
  3. Browser 侧 `press_key`/uid 点击在每 5 秒重绘下会失效（元素句柄过期、按键未送达），只能靠 evaluate_script 合成事件验证——这是工具限制，不是页面缺陷。
- 下一步：提交；再定是否刷新真实库并建第一条真任务线。
- commit：随本提交落盘
