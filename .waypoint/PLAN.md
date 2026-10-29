# 计划

## 1. 数据侧：让 board --json 足以支撑页面

- [x] 给会话补 `title` / `parent` / `journal` / `dir` / `project` / `cur` 字段
- [x] 给项目仓库补 `title` / `branch` 字段
- [x] `json_escape` 额外转义 `<` `>`，保证可安全内嵌进 `<script>`
- [x] `--json` 增加 `stale_days`，页面与命令行共用同一陈旧阈值

## 2. 页面：单文件 HTML 模板

- [x] `dashboard/index.html`：暗/亮自适应、统计块、筛选 chips、搜索（`/` 聚焦）
- [x] 任务线分组卡片 + 会话行（进度条 / 相对时间 / 锁与陈旧标记 / 下一步）
- [x] 详情抽屉：目录、父会话、JOURNAL 条数、项目锚、下一步全文、可复制命令
- [x] 空态引导（库里没任务时给出 `new` 命令）
- [x] 无障碍：行可 Tab 聚焦、抽屉 role=dialog + 焦点陷阱 + inert 关闭态、轮询不抢焦点

## 3. 命令：dash

- [x] `dash [--out F] [--open] [--serve [--port N]]`，默认输出 `~/.waypoint/dashboard.html`
- [x] 占位符替换用 awk substr 级替换（整行替换会把 `<script>` 标签吃掉）
- [x] 产物落在库内时写入 `.git/info/exclude`，避免 checkpoint 判脏
- [x] `--serve` 走 `dashboard/serve.py`（python3 标准库，仅 127.0.0.1），`/api/board` 每次现算

## 4. 验证

- [x] 冒烟测试新增第 9 组（页面生成/标签完整/占位符已替换/JSON 可解析/产物不脏库/serve.py 语法）
- [x] 浏览器实测：渲染、筛选、搜索、抽屉、键盘、407px 窄屏、5 秒轮询、console 无报错
- [x] 三种反直觉回归钉住：usage 自引用打印整脚本、assert_contains 的 SIGPIPE 假失败、`$VAR` 紧跟中文标点

## 5. 收尾

- [x] 文档同步（README / QUICKSTART / PROTOCOL / AGENTS / INSTALL_FOR_AGENTS / comparison）
- [x] 提交本轮改动（代码 + 状态文件同一提交，父提交 1da636e）
- [ ] 真实库 `~/.waypoint` 仍是旧版初始化：缺 locks/repos.txt，PROTOCOL.md 与 RULES_SNIPPET.md 为旧版，需刷新（等用户确认）
