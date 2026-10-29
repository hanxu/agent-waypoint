#!/usr/bin/env bash
# tests/smoke.sh — Waypoint 脚本冒烟测试（无依赖，macOS bash 3.2 + BSD awk 兼容）
# 用法: bash tests/smoke.sh [-v]
# 覆盖: 会话隔离(功能2) / 看板(功能1) / 租约锁 / 旧布局迁移 / 项目模式 / 4 个 P0 回归
set -uo pipefail

WP="$(cd "$(dirname "$0")/.." && pwd)/scripts/waypoint.sh"
KIT="$(cd "$(dirname "$0")/.." && pwd)"
VERBOSE=0; [[ "${1:-}" == "-v" ]] && VERBOSE=1

PASS=0; FAIL=0
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"   # macOS /var 是符号链接，解实路径以对比 git toplevel
trap 'bash "$WP" --home "$H" dash stop >/dev/null 2>&1; rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); [[ $VERBOSE -eq 1 ]] && echo "  ✅ $1" || echo "✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; [[ -n "${2:-}" ]] && echo "     └ $2"; }
# assert <描述> <期望退出码(数字|nonzero)> <命令...>
assert() {
  local desc="$1" want="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [[ "$want" == "nonzero" ]]; then
    [[ $rc -ne 0 ]] && ok "$desc" || bad "$desc" "期望失败，实际 rc=0；输出: $(echo "$out" | tail -3)"
  else
    [[ $rc -eq "$want" ]] && ok "$desc" || bad "$desc" "rc=${rc}≠${want}；输出: $(echo "$out" | tail -5)"
  fi
}
# assert_contains <描述> <子串> <命令...>
assert_contains() {  # 用 case 而非 grep：管道 + pipefail 下 grep -q 提前退出会让 printf 吃 SIGPIPE 而误报失败
  local desc="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  case "$out" in
    *"$needle"*) ok "$desc" ;;
    *) bad "$desc" "缺子串 '$needle'；输出: $(echo "$out" | head -20)" ;;
  esac
}
assert_not_contains() {
  local desc="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  case "$out" in
    *"$needle"*) bad "$desc" "不应出现 '$needle'" ;;
    *) ok "$desc" ;;
  esac
}

H="$TMP/lib"
# 关键：全部写入临时目录，绝不碰真实 ~/.waypoint
export WAYPOINT_HOME="$H"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@local GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@local
run() { "$WP" --home "$H" "$@"; }

echo "── 1. 建库与 P0 回归 ──────────────────────────"
"$WP" help > "$TMP/help.txt" 2>&1
if grep -q "usr/bin/env" "$TMP/help.txt"; then bad "help 不含 shebang"; else ok "help 不含 shebang"; fi
if grep -q "USAGE-BEGIN" "$TMP/help.txt"; then bad "help 不含内部标记"; else ok "help 不含内部标记"; fi
assert_contains "help 列出 board/resume 等新子命令" "board" "$WP" help
assert_contains "help 列出 dash" "dash" "$WP" help
# usage 用 sed 读脚本自身：范围未锚定就会把函数定义行当结束标记、再从头打印到 EOF
assert_not_contains "help 不泄漏脚本正文" "PRE=()" "$WP" help
[[ "$(bash "$WP" help | wc -l | tr -d ' ')" -lt 40 ]] && ok "help 输出行数正常" || bad "help 输出异常长"

assert "init-home 建库" 0 "$WP" init-home --home "$H"
[[ -d "$H/tasks" && -f "$H/RULES_SNIPPET.md" ]] && ok "库结构齐备（tasks/ + RULES_SNIPPET.md）" || bad "库结构缺失"
[[ "$(git -C "$H" rev-parse --show-toplevel)" == "$H" ]] && ok "P0-1 回归：全局库是独立仓库根" || bad "P0-1 回归：库寄宿进父仓库"
assert_contains "P0-2 回归：locks/ 已被 info/exclude 排除" "locks/" cat "$H/.git/info/exclude"
[[ -z "$(git -C "$H" status --porcelain)" ]] && ok "建库后 git status 干净" || bad "建库后工作区不干净" "$(git -C "$H" status --porcelain)"

# P0-1：在已有 git 仓库内部建库要拒绝
mkdir -p "$TMP/host/sub"; git -C "$TMP/host" init -q
assert "P0-1 回归：拒绝把库建进别的仓库" nonzero "$WP" init-home --home "$TMP/host/sub"
assert "…但 --force 可显式允许" 0 "$WP" init-home --home "$TMP/host/sub" --force

echo "── 2. 会话隔离（功能 2）─────────────────────────"
assert "new 开线+开首个会话" 0 run new "登录重构" --client qoder
[[ -f "$H/tasks/登录重构/TASK.md" ]] && ok "线级合同 TASK.md" || bad "缺线级 TASK.md"
[[ -f "$H/tasks/登录重构/sessions/qoder/HANDOFF.md" ]] && ok "端级会话目录 sessions/qoder/" || bad "缺会话目录"
[[ "$(cat "$H/CURRENT")" == "登录重构/qoder" ]] && ok "CURRENT 记 <线>/<端>" || bad "CURRENT 内容异常: $(cat "$H/CURRENT")"

assert "同线再开第二个端" 0 run new "登录重构" --client codebuddy
[[ -d "$H/tasks/登录重构/sessions/codebuddy" ]] && ok "第二个会话独立存在" || bad "第二会话未创建"
assert "重复开同一会话要拒绝" nonzero run new "登录重构" --client codebuddy
assert "不存在的线要拒绝" nonzero run resume --line 不存在线

# 两个端各 checkpoint 一次 → 就是两个可接管任务
printf '## 下一步\n- 补齐 refresh token 用例\n' > "$H/tasks/登录重构/sessions/qoder/HANDOFF.md"
printf '## 下一步\n- 把验证码改为图形码\n' > "$H/tasks/登录重构/sessions/codebuddy/HANDOFF.md"
printf -- '- [x] 已完成项\n- [ ] 未完成项\n' > "$H/tasks/登录重构/sessions/qoder/PLAN.md"
echo "" >> "$H/tasks/登录重构/sessions/codebuddy/JOURNAL.md"
git -C "$H" add -A && git -C "$H" commit -q -m "test: 状态写回"
run checkpoint --line 登录重构 --sid qoder > "$TMP/ck1.txt" 2>&1
assert_contains "checkpoint --line 走全局会话模式" "会话 登录重构/qoder" cat "$TMP/ck1.txt"
assert_contains "checkpoint 提示同线其他会话" "codebuddy" cat "$TMP/ck1.txt"
echo "" >> "$H/tasks/登录重构/sessions/qoder/JOURNAL.md"   # 再造脏库
assert "脏库 checkpoint 拒绝" nonzero "$WP" checkpoint --line 登录重构 --sid qoder
git -C "$H" add -A && git -C "$H" commit -q -m "test: 追加日志"
assert "交出后锁不入库" 0 sh -c "git -C '$H' status --porcelain | grep locks && exit 1; exit 0"

echo "── 3. 接管候选 ─────────────────────────────────"
assert_contains "resume 无参数=列候选（多任务可选）" "可接管会话" run resume
assert_contains "候选含 qoder 会话" "登录重构/qoder" run resume
assert_contains "候选含 codebuddy 会话" "登录重构/codebuddy" run resume
assert_contains "候选带下一步摘要" "refresh token" run resume
assert "resume 指定线/端可接管" 0 run resume 登录重构/codebuddy
[[ "$(cat "$H/CURRENT")" == "登录重构/codebuddy" ]] && ok "接管后 CURRENT 跟随" || bad "CURRENT 未更新"

# 换第三个端接管 → 为本端开新会话并继承
assert "跨端接管自动为本端开新会话" 0 run resume 登录重构/qoder --client claude
[[ -d "$H/tasks/登录重构/sessions/claude" ]] && ok "新会话 sessions/claude 已建" || bad "跨端接管未建会话"
[[ "$(grep -m1 '^parent=' "$H/tasks/登录重构/sessions/claude/.session")" == "parent=qoder" ]] \
  && ok "新会话记录继承来源 parent=qoder" || bad "parent 未记录"
assert_contains "接管输出取锁提示" "租约" run resume 登录重构/claude

echo "── 4. 锁与互斥 ──────────────────────────────────"
assert "先释放接管留下的锁" 0 run unlock --line 登录重构 --sid claude
assert "显式取锁（owner=zzz）" 0 run lock --line 登录重构 --sid claude --client zzz --ttl 5
assert_contains "who 显示有效锁" "登录重构__claude" run who
assert "同名会话被他人锁住时拒绝接管" nonzero run resume 登录重构/claude
assert "…--force 可抢占（不静默抢锁）" 0 run resume 登录重构/claude --force
assert "源会话被锁时跳端接管也拒绝" nonzero run resume 登录重构/codebuddy --client windows
assert "…加 --force 后为新端开会话" 0 run resume 登录重构/codebuddy --client windows --force
[[ -d "$H/tasks/登录重构/sessions/windows" ]] && ok "新端会话已建" || bad "跳端接管未建会话"
assert "租约过期可直接接管（pid=0 也看 lease）" 0 sh -c "printf 'owner=ghost\nkind=resume\ntarget=x\nat=1\nlease=1\npid=0\n' > '$H/locks/登录重构__qoder.lock'; '$WP' --home '$H' resume 登录重构/qoder"
assert "死进程的作业锁视为过期（租约未满也能接）" 0 sh -c "printf 'owner=job\nkind=job\ntarget=x\nat=1\nlease=9999999999\npid=999999\n' > '$H/locks/登录重构__claude.lock'; '$WP' --home '$H' resume 登录重构/claude"
assert "逐个释放" 0 sh -c "for d in '$H'/tasks/*/sessions/*/; do s=\$(basename \"\$d\"); '$WP' --home '$H' unlock --line 登录重构 --sid \"\$s\" >/dev/null 2>&1; done; '$WP' --home '$H' unlock --line 登录重构 --sid ghost >/dev/null 2>&1; true"
assert_contains "全部释放后 who 报 (无)" "(无)" run who

echo "── 5. 看板（功能 1）────────────────────────────"
assert_contains "board 列出全部会话" "▸ 登录重构" run board
assert_contains "board 显示端名" "claude" run board
assert_contains "board 显示计划进度" "计划=1/2" run board
assert "board --json 是合法 JSON" 0 sh -c "'$WP' --home '$H' board --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d[\"sessions\"])>=3, d; print(\"sessions:\", len(d[\"sessions\"]))'"
assert_contains "json 含 repos 字段" "\"repos\"" run board --json
assert_contains "board --by-client 出端视图" "按端汇总" run board --by-client
sed -i.bak 's/^last_epoch=.*/last_epoch=1000000000/' "$H/tasks/登录重构/sessions/codebuddy/.session" 2>/dev/null \
  || sed -i 's/^last_epoch=.*/last_epoch=1000000000/' "$H/tasks/登录重构/sessions/codebuddy/.session"
assert_contains "陈旧阈值生效" "陈旧" run board --stale-days 7
assert_not_contains "陈旧标记可被关掉（阈值放宽）" "陈旧" run board --stale-days 999999

echo "── 6. 项目模式与 P0-3 回归 ──────────────────────"
mkdir -p "$TMP/proj"; git -C "$TMP/proj" init -q
assert "未安装协议时 status 不报错" 0 "$WP" status --target "$TMP/proj"
assert "init 安装协议到空仓库" 0 "$WP" init --target "$TMP/proj"
assert_contains "P0-3 回归：零提交仓库 status 不崩" "(尚无提交)" "$WP" status --target "$TMP/proj"
[[ -f "$TMP/proj/.waypoint/PROTOCOL.md" && -f "$TMP/proj/AGENTS.md" ]] && ok "协议文件已安装" || bad "安装不完整"
assert_contains "init 后登记进 repos.txt" "$TMP/proj" cat "$H/repos.txt"
assert_contains "board 能看到项目模式仓库" "项目模式仓库" run board
assert "P0-2 回归：项目 locks/ 不污染 git status" 0 sh -c "mkdir -p '$TMP/proj/.waypoint/locks'; printf 'owner=x\nkind=t\nlease=9999999999\npid=0\n' > '$TMP/proj/.waypoint/locks/t.lock'; git -C '$TMP/proj' status --porcelain | grep -q locks && exit 1 || exit 0"
assert "脏树 checkpoint 拒绝" nonzero "$WP" checkpoint --target "$TMP/proj"
assert "…--allow-dirty 放行" 0 "$WP" checkpoint --target "$TMP/proj" --allow-dirty
# 项目模式 checkpoint 曾把客户端名写成字面 ${当前客户端名}，且拿 HEAD~1 当“本轮改动”
assert_not_contains "checkpoint 不泄漏变量占位符" '${' "$WP" checkpoint --target "$TMP/proj" --allow-dirty --client qoder
assert_contains "checkpoint 报到本轮改动" "本轮改动概览" "$WP" checkpoint --target "$TMP/proj" --allow-dirty --client qoder
assert_not_contains "checkpoint 不再误抓 HEAD~1" "templates/" "$WP" checkpoint --target "$TMP/proj" --allow-dirty --client qoder
assert "项目模式取锁" 0 "$WP" lock --target "$TMP/proj" --client qoder
assert_contains "项目锁计入 who（owner 可见）" "alive:qoder" "$WP" who --home "$H"
assert "项目锁被他人持有时拒绝" nonzero "$WP" lock --target "$TMP/proj" --client other
assert "项目模式释放锁" 0 "$WP" unlock --target "$TMP/proj"

echo "── 7. 旧布局迁移 ───────────────────────────────"
mkdir -p "$H/tasks/旧任务"
printf '# 旧任务\n## 目标\n- x\n' > "$H/tasks/旧任务/TASK.md"
printf '# 交接快照 by aider\n## 下一步\n- 继续写迁移\n' > "$H/tasks/旧任务/HANDOFF.md"
printf -- '- [ ] 项\n' > "$H/tasks/旧任务/PLAN.md"
assert "migrate 迁移旧线" 0 run migrate
[[ -f "$H/tasks/旧任务/sessions/aider/HANDOFF.md" ]] && ok "旧状态归位到 sessions/aider" || bad "迁移未建会话目录"
[[ -f "$H/tasks/旧任务/TASK.md" ]] && ok "TASK.md 留在线级" || bad "迁移误动 TASK.md"
assert_contains "迁移后看板可见旧线" "▸ 旧任务" run board
assert_contains "迁移后旧会话入看板" "aider" run board
assert_contains "迁移后 TASK.md 标题入 tasks" "旧任务" run tasks

echo "── 8. 兼容与健壮 ───────────────────────────────"
assert "v1 别名 --task 仍可用" 0 run checkpoint --task 登录重构 --sid qoder
assert "未初始化目录给清晰指引" nonzero "$WP" board --home "$TMP/nolink"
assert "未知子命令退出非零" 1 "$WP" 不存在的命令
assert "非法 --ttl 不产生算式错误" 0 run lock --line 登录重构 --sid qoder --ttl "abc"
assert "unlock 无锁时不报错" 0 run unlock --line 登录重构 --sid qoder
assert_contains "RULES_SNIPPET 写明多任务可选" "列出可接管会话让用户选" cat "$H/RULES_SNIPPET.md"

echo "── 9. 页面看板 ───────────────────────────────"
PAGE="$TMP/page.html"
assert "dash --out 自动走导出" 0 run dash --out "$PAGE"
[[ -s "$PAGE" ]] && ok "页面非空" || bad "页面为空"
# 占位符与 <script> 包裹同在一行：替换时必须只换数据，不能把标签一起吃算
if grep -qF 'id="wp-data" type="application/json">{"generated_at"' "$PAGE"; then
  ok "数据注在 <script> 内（标签未被破坏）"
else
  bad "占位符替换破坏了 <script> 标签"
fi
grep -qF '__WAYPOINT_DATA__' "$PAGE" && bad "占位符未被替换" || ok "占位符已替换"
grep -qF '"sid":"qoder"' "$PAGE" && ok "会话数据已内嵌" || bad "页面里找不到会话数据"
assert "dash export 默认产物落库" 0 run dash export
[[ -f "$H/dashboard.html" ]] && ok "默认输出到库根 dashboard.html" || bad "默认产物位置不对"
# 产物必须被 exclude，否则库变脏、下次 checkpoint 直接被拒
if [[ -z "$(git -C "$H" status --porcelain)" ]]; then ok "生成看板后库仍干净（已 exclude）"; else bad "看板产物污染了库" "$(git -C "$H" status --porcelain | head -3)"; fi
if command -v python3 >/dev/null 2>&1; then
  python3 - "$PAGE" <<'PY' && ok "内嵌 JSON 可被解析且含会话" || bad "内嵌 JSON 解析失败"
import json, re, sys
txt = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'type="application/json">(.*?)</script>', txt, re.S)
data = json.loads(m.group(1))
assert isinstance(data.get("sessions"), list) and len(data["sessions"]) >= 3
assert "repos" in data and "home" in data
PY
  python3 -c "import sys;compile(open(sys.argv[1],encoding='utf-8').read(),sys.argv[1],'exec')" \
    "$KIT/dashboard/serve.py" 2>/dev/null && ok "serve.py 语法通过" || bad "serve.py 语法错误"
fi

echo "── 10. 看板服务（默认形态）──────────────────"
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  TD_PORT=$(( 18000 + RANDOM % 500 ))
  assert "dash --daemon 后台起服务" 0 run dash --daemon --port "$TD_PORT"
  TD_PID=""; TD_PORT2=""
  [[ -s "$H/dash.run" ]] && read -r TD_PID TD_PORT2 < "$H/dash.run" || true
  [[ -n "$TD_PORT2" ]] && ok "dash.run 记录 pid 与端口（${TD_PORT2}）" || bad "没写出 dash.run"
  assert_contains "dash status 报运行中" "运行中" run dash status
  # pid 文件只有一个，多开会互相覆盖、前者变孤儿 → 必须拒绝第二个实例
  assert_contains "重复 dash --daemon 不开新实例" "已在运行" run dash --daemon --port "$TD_PORT"
  if [[ -n "$TD_PORT2" ]]; then
    TD_B="$(curl -fsS --max-time 5 "http://127.0.0.1:${TD_PORT2}/api/board" 2>/dev/null)"
    case "$TD_B" in *'"sessions"'*) ok "/api/board 返回 JSON" ;; *) bad "/api/board 无响应" ;; esac
    TD_P="$(curl -fsS --max-time 5 "http://127.0.0.1:${TD_PORT2}/" 2>/dev/null)"
    case "$TD_P" in *'id="wp-data" type="application/json">{"generated_at"'*) ok "/ 返回已注入数据的页面" ;; *) bad "/ 页面异常" ;; esac
    case "$TD_P" in *'__WAYPOINT_DATA__'*) bad "/ 页面残留占位符" ;; *) ok "/ 页面占位符已替换" ;; esac
    TD_E="$(curl -sN --max-time 3 "http://127.0.0.1:${TD_PORT2}/api/events" 2>/dev/null | head -c 300)"
    case "$TD_E" in *'data: {"generated_at"'*) ok "SSE 首帧带数据" ;; *) bad "SSE 无首帧（页面不会自动刷新）" ;; esac
  fi
  if [[ -z "$(git -C "$H" status --porcelain)" ]]; then ok "服务运行期库仍干净（dash.run/log 已 exclude）"; else bad "dash.run/log 污染了库" "$(git -C "$H" status --porcelain | head -3)"; fi
  assert "dash stop 停止服务" 0 run dash stop
  assert_contains "stop 后 status 报未运行" "未在后台运行" run dash status
else
  echo "  (跳过：缺 python3 或 curl)"
fi

echo
echo "═══ 通过 $PASS / 失败 $FAIL ═══"
[[ $FAIL -eq 0 ]] || exit 1
