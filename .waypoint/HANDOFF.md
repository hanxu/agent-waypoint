# 交接快照 — 2026-10-29T11:45:00+0800 by qoder

## 任务一句话

把 waypoint 从"只有脚本"推进到"有页面看板的个人工作台"：`board --json` 保持唯一数据源，`dash` 起本地看板**服务**（HTTP + SSE 推送），页面自己跟着数据变。

## 当前状态

看板已从"静态页为主"改成"服务为主"，并通过浏览器实测：**页面不刷新也会自动更新**。提交后工作区干净。

最近一次验证（macOS / bash 3.2 + BSD 工具链 / python3 标准库）：

```
bash tests/smoke.sh                                  → 通过 104 / 失败 0（10 组）
dash --daemon --port 8799 && curl /api/ping          → {"ok": true, "home": "..."}
curl -N /api/events                                  → retry: 2000 + data: {...}
curl -s http://127.0.0.1:8799/ | grep wp-data        → 首屏已注入 JSON，占位符 0 残留
dash status                                          → 运行中 + 健康检查 OK
dash stop                                            → 已停止（pid/端口清理）
端口 8799 被占用时再次起服务                          → 自动落到 8800
```

浏览器验收（同一次导航内，`performance.getEntriesByType('navigation').length == 1`，未刷新）：

- 30 秒内会话行 **55 → 64**（后台每 5 秒写一条），meta 快照时间 11:41:30 → 11:42:13 持续前进
- 顶部按钮「实时 · 重连」、页脚「由本机看板服务推送（SSE，每 5 秒一次）」、meta 带「实时推送」
- 抽屉打开期间数据变化 → 内容跟着刷新，焦点仍在 `#d-close`；Escape 后焦点回到 `.row`
- console error 0；`/api/events` 响应头 `text/event-stream`
- 407px 视口 `scrollWidth == clientWidth == 407`

## 已完成（≤5 条）

- `dash` 默认起服务（`127.0.0.1:8787`，端口占用自动 +1），页面用 `EventSource` 订阅 `/api/events`，服务端每 5 秒推送一次 `board --json`；采集缓存 2 秒 → 多标签页只跑一次子进程
- `dash --daemon` 后台常驻 + `dash stop` + `dash status`（`dash.run` 存 pid/端口、`dash.log` 存日志，均已 exclude）；`dash_running` 强制单实例（否则 pid 文件互相覆盖、前者变孤儿）
- `dash export`（及 `dash --out`）保留为次要形态：注入式单文件 HTML，供转发/离线/`file://` 查看，页面自动显示「离线快照」
- 页面：抽屉内容抽成 `fillDrawer` 随推送刷新，焦点按 `data-key` 保持；轮询逻辑彻底移除
- 测试 93 → 104（第 10 组覆盖 daemon/pid 文件/单实例/`/api/board`/`/` 注入/SSE 首帧/运行期不脏库/stop）；文档与协议副本同步

## 下一步（具体到可直接执行的第一条指令）

1. 直接看效果：`bash scripts/waypoint.sh dash --open`（起服务并开浏览器；关终端就停。想常驻用 `dash --daemon`）
2. 等用户决策（阻塞项）：是否刷新真实库 `~/.waypoint`——旧版初始化，缺 `locks/` `repos.txt` `CURRENT`，`PROTOCOL.md` / `RULES_SNIPPET.md` 均为旧版（无「resume 先列候选不得代选」等新约定）。刷新须重新生成 `RULES_SNIPPET.md`（内含库路径与脚本路径），不能照抄模板
3. 同样等决策：是否在 `~/.waypoint` 建第一条真实任务线，让看板出现真正的会话行
4. 若继续开发：先 `bash tests/smoke.sh` 确认 104 项仍全绿，再动 `dashboard/serve.py` / `cmd_dash`
5. 欠账（记入 docs/comparison.md）：`validate` doctor、带版本号的 `--upgrade`

## Do Not Redo（已做过、勿重做勿回退的工作）

- 不要退回"页面 `setInterval` + `fetch('/api/board')`"轮询：已改 SSE，服务端缓存采集，多标签只跑一次
- 不要允许同时起多个 `--daemon`：pid 文件只有一个，前一个会变孤儿（`dash_running` 已拦）
- 不要用 awk「整行替换」注入占位符（`__WAYPOINT_DATA__` 与 `<script>` 同行）
- 不要在 `usage()` 里用未锚定的 `/# USAGE-BEGIN/,/# USAGE-END/p`
- 不要用 `printf | grep -q` 做断言（pipefail + SIGPIPE 会误报）
- 不要用 `git reset --hard` 清历史（用 `--soft`）
- 不要在页面或服务里新增数据采集逻辑：只消费 `board --json`

## Intentionally Dirty（未提交但属故意的文件）

- 无。`.waypoint/locks/`、`dash.run`、`dash.log`、`dashboard.html` 均已 exclude

## 关联项目（全局模式且锚定了项目时填，无则写"无"）

- 无（项目模式：状态与代码同在 `/Users/pc/study/agent-waypoint`）

## 关键坑与约束（≤5 条）

- SSE 长连接要 `protocol_version = "HTTP/1.1"` + `Connection: keep-alive`，并且**不要在 handler 里缓存 `self.wfile`**；浏览器关页面会抛 `BrokenPipe/ConnectionReset`，必须吞掉
- 每个 SSE 连接占一个线程：`ThreadingHTTPServer(daemon_threads=True)`，靠采集缓存把子进程数压到常数
- Browser 自动化在"每 5 秒重绘"的页面上会失效（uid 句柄过期、`press_key` 送不到页面）——验收要用 `evaluate_script` 取数/合成事件，别据此判页面故障
- 验收"数据会自己变"时，喂数据的节奏必须覆盖观测窗口；喂完再开测会得到假失败
- `mktemp -d` 在 macOS 返回 `/var` 符号链接路径，测试里要 `pwd -P`；`$VAR` 紧跟中文标点要写 `${VAR}`

## 恢复入口

- 必读：同目录 `TASK.md`、`PLAN.md`（§6 是服务化）、`PROTOCOL.md`（§9.3 看板服务）、`JOURNAL.md`（迭代 3/4 有全部踩坑）
- 代码入口：`scripts/waypoint.sh` 的 `cmd_dash` / `dash_serve` / `dash_running`；`dashboard/serve.py`（`Board` / `_events`）；`dashboard/index.html`（`connect()` / `fillDrawer`）
- 验证入口：`bash tests/smoke.sh`（10 组 104 项）；手动 `dash --daemon` + `curl /api/events` + `dash stop`
