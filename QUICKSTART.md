# QUICKSTART

## 路线 A：全局模式（推荐个人使用）

全机一份任务库（默认 `~/.waypoint`），任务不绑定项目，在任何客户端、任何目录说「继续任务」都接得上。

```bash
WP=/path/to/agent-waypoint/scripts/waypoint.sh

# 1. 建库（--home 可指定目录；也可用环境变量 WAYPOINT_HOME）
bash "$WP" init-home

# 2. 开一条任务线，并为当前这个端开会话（--project 可选：锚定代码仓库，checkpoint 时记录其 HEAD）
bash "$WP" new 优化网关 --client qoder [--project ~/work/tsy-gateway]

# 3. 注入（一次）：把 ~/.waypoint/RULES_SNIPPET.md 的内容贴进 Qoder 用户级 Rules / Trae user_rules.md
#    并在规则里固定本端的 --client 名字（下文均用同一个名字，否则会给同一端误开新会话）

# 4.（推荐）装 hook 自动落盘，采集这一半从此不经模型：
#    bash /path/to/agent-waypoint/plugins/install.sh --target <你的仓库> --apply
```

日常循环：在任何端说「继续任务」→ 它先 `resume` 列出候选让你选 → 接管后复述状态 → 干活 → 「checkpoint」交出（先 `capture drain` 把 hook 采到的原料归成机器事实，再只写本端会话，并在全局库 commit）。

```bash
bash "$WP" board          # ⭐ 各端任务总览：进度、多久没动、谁拿着锁（--by-client 看端视图，--json 给面板）
bash "$WP" dash --open     # 🖥️ 看板服务：起本地服务并打开浏览器，页面自己会刷新
bash "$WP" dash --daemon   # 想让它在后台常驻（关掉终端也活着），停用: dash stop
bash "$WP" resume         # 列出可接管会话（多个端交过手 = 多个候选）
bash "$WP" resume 优化网关/qoder --client trae   # 接手：trae 无会话则从 qoder 的快照继承一份
bash "$WP" tasks / switch <线> [端] / status / who / lock / unlock / migrate
bash "$WP" capture show [--target .]    # 🛰️ 收件箱：hook 采到的原料还有多少待归摞
bash "$WP" capture drain [--target .]  # 归摞进 JOURNAL（幂等，带游标）
```

多客户端并行同一条线是可以的：每个端各一份 PLAN/HANDOFF/JOURNAL，锁按「线/端」隔离，互不覆盖。想合并回一份？让一个端接管后把其它端的 JOURNAL 条目抄进来，再归档其余会话（`mv tasks/<线>/sessions/<端> archive/`）。

## 路线 B：项目模式

状态装在项目内，与代码原子提交，适合任务和仓库强绑定的场景。

### 1. 安装协议到你的项目（30 秒）

```bash
bash /path/to/agent-waypoint/scripts/waypoint.sh init --target /path/to/your-project
```

或在任何 agent 客户端里说：

> 按 INSTALL_FOR_AGENTS.md 把 https://github.com/hanxu/agent-waypoint 安装到本项目

### 1.5 装 hook 自动落盘（推荐，一次装好）

采集这一半不必经模型：宿主在每次工具调用与每轮回答结束时回调 hook，把用户原话、回答全文、git 事实、会话全文指针追写进 `.waypoint/inbox/`。**额度耗尽也照样落盘**，接手时不会两手空空。

```bash
bash /path/to/agent-waypoint/plugins/install.sh --target /path/to/your-project --apply
bash /path/to/agent-waypoint/scripts/waypoint.sh capture show --target .    # 看落了什么
bash /path/to/agent-waypoint/scripts/waypoint.sh capture drain --target .   # 归摞进 JOURNAL
```

装完新开会话即生效（执行体每次事件重新执行，不必重启 IDE）。跳过这步也行，交接退回手工 checkpoint，只是原料得靠模型记性。

### 2. 立项（2 分钟）

填 `.waypoint/TASK.md`（背景 + DoD 验收标准）和 `.waypoint/PLAN.md`（步骤清单）。

### 3. 日常循环

在客户端 A（如 Qoder）干活，每个迭代结束时说：

> checkpoint

它会勾选计划、追加日志、重写交接快照并 commit。

切换到客户端 B（如 Trae / WorkBuddy），说：

> 继续任务

它会读交接快照、复述状态，然后从「下一步」接着干。

## 收尾（两种模式相同）

DoD 全部通过后说「任务完成」：项目模式归档进 `.waypoint/archive/`；全局模式 `mv tasks/<线> archive/<完结日期>-<线>`（连 sessions/ 一起）后在全局库 commit。

改过代码后想确认没弄坏脚本：`bash tests/smoke.sh`（全部在临时目录跑，不碰你的真实库）。

## 客户端不支持用户级规则/AGENTS.md？

把这段粘贴给它（兜底 bootstrap）：

```text
接管任务：阅读 .waypoint/HANDOFF.md、.waypoint/TASK.md、.waypoint/PLAN.md，
执行 git log --oneline -10 核对状态，复述当前进度和下一步，
等我确认后继续执行。全程遵守 AGENTS.md 中的协作协议。
```
