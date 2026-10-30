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

echo "── 11. 自动落盘 hook（capture）──────────────"
# 立场：hook 不用 LLM，只归集原料；因此这一节的断言全部应该在没有模型时成立
HOOK="$KIT/plugins/waypoint-qoder-hook/bin/waypoint-hook"
CP="$TMP/capture"
mkdir -p "$CP/.waypoint" "$CP/.git/info"
git -C "$CP" init -q
for f in TASK PLAN HANDOFF JOURNAL DECISIONS; do cp "$KIT/templates/$f.md" "$CP/.waypoint/$f.md" 2>/dev/null || true; done
printf '.waypoint/inbox/\n' >> "$CP/.git/info/exclude"
git -C "$CP" add -A >/dev/null 2>&1; git -C "$CP" commit -q -m "init 协议"
cp_run() { ( cd "$CP" && WAYPOINT_INBOX="$CP/.waypoint/inbox" WAYPOINT_INBOX_MODE=project "$HOOK" "$1" ); }

printf '{"prompt":"额度快没了怎么办"}' | cp_run prompt
printf '{"hookEventName":"SessionStart","session_id":"s1"}' | cp_run probe
sleep 2
[[ -f "$CP/.waypoint/inbox/prompts.log" ]] && ok "prompts.log 已落盘" || bad "prompts.log 未生成"
if grep -q '额度快没了怎么办' "$CP/.waypoint/inbox/prompts.log" 2>/dev/null; then ok "用户输入原文零 LLM 进入收件箱"; else bad "输入原文丢失"; fi
if grep -q '"hookEventName":"SessionStart"' "$CP/.waypoint/inbox/hook-probe.log" 2>/dev/null; then ok "stdin 原文留档（schema 可事后校正）"; else bad "探针未留档"; fi
[[ -f "$CP/.waypoint/inbox/.last-head" ]] && ok "基线 HEAD 已记录" || bad "未记录基线 HEAD"
[[ -z "$(git -C "$CP" status --porcelain)" ]] && ok "收件箱不污染 git status（info/exclude 生效）" || bad "收件箱污染工作区" "$(git -C "$CP" status --porcelain | head -3)"

assert_contains "capture show 列出待归摞" "待归摞" run capture show --target "$CP"
assert_contains "capture drain 归摞进 JOURNAL" "自动落盘（hook 捕获" run capture drain --target "$CP"
grep -q '额度快没了怎么办' "$CP/.waypoint/JOURNAL.md" 2>/dev/null && ok "JOURNAL 拿到原料" || bad "JOURNAL 未含输入原文"
assert_contains "再次 drain 幂等（游标已前进）" "没有待归摞的原料" run capture drain --target "$CP"

git -C "$CP" commit -q --allow-empty -m "改写 handler 透传"; sleep 2
printf '{"prompt":"再来一条"}' | cp_run prompt; sleep 2
if grep -q '改写 handler 透传' "$CP/.waypoint/inbox/commits.log" 2>/dev/null; then ok "提交增量按 last_head 捕获（问 git 不问 LLM）"; else bad "commits.log 未捕获增量"; fi
assert "drain --commit 只提交 JOURNAL 与游标" 0 run capture drain --target "$CP" --commit
[[ -z "$(git -C "$CP" status --porcelain)" ]] && ok "归摞提交后工作区干净" || bad "归摞提交后仍脏" "$(git -C "$CP" status --porcelain | head -3)"
assert "capture 未知子命令要报错" nonzero run capture frobnicate --target "$CP"
# 没装 waypoint 时 hook 必须空转：不建目录、不写文件、不碰用户仓库
STRAY="$TMP/stray"; mkdir -p "$STRAY"; git -C "$STRAY" init -q
printf 'keep\n' > "$STRAY/a.txt"; git -C "$STRAY" add -A; git -C "$STRAY" commit -q -m "init"
BEFORE="$(git -C "$STRAY" status --porcelain)"
( cd "$STRAY" && env -u WAYPOINT_INBOX -u WAYPOINT_INBOX_MODE -u WAYPOINT_FALLBACK_INBOX \
    HOME="$TMP/fakehome" WAYPOINT_HOME="$TMP/no-such-lib" "$HOOK" prompt <<< '{"prompt":"x"}' ) >/dev/null 2>&1
AFTER="$(git -C "$STRAY" status --porcelain)"
[[ "$BEFORE" == "$AFTER" ]] && ok "找不到 waypoint 时 hook 不碰无关仓库" || bad "hook 改动了无关仓库" "$AFTER"
[[ ! -e "$STRAY/.waypoint" ]] && ok "hook 不在陌生仓库里造 .waypoint" || bad "hook 造了 .waypoint"
[[ ! -e "$TMP/fakehome/.waypoint" ]] && ok "hook 不伪造 HOME" || bad "污染了假 HOME"

# 关键回归：Qoder 真实走的是自动探测分支（不给 WAYPOINT_INBOX）
#   该分支曾因 INBOX_DIR 未赋值而崩，而上一条空转断言恰好会掩盖它，所以必须分模式正断
printf '{"prompt":"自动探测分支实跑"}' | ( cd "$CP" && env -u WAYPOINT_INBOX -u WAYPOINT_INBOX_MODE -u WAYPOINT_PROJECT \
  HOME="$TMP/fakehome" WAYPOINT_HOME="$TMP/no-lib" "$HOOK" prompt )
sleep 2
if grep -q '|project|.*自动探测分支实跑' "$CP/.waypoint/inbox/prompts.log" 2>/dev/null; then
  ok "自动探测：落进项目收件箱（Qoder 真实路径）"
else
  bad "自动探测未落盘" "$(tail -3 "$CP/.waypoint/inbox/prompts.log" 2>/dev/null)"
fi
if grep -q '|project|prompt|'"$CP"'|master|' "$CP/.waypoint/inbox/snapshots.log" 2>/dev/null; then
  ok "快照的 git 事实取自收件箱所属仓库（不是家目录）"
else
  bad "快照取错了仓库" "$(tail -2 "$CP/.waypoint/inbox/snapshots.log" 2>/dev/null)"
fi
# 全局模式：cwd 不在任何装了协议的仓库里 → 收件箱落任务库根，且不脏库
printf '{"prompt":"全局模式一条"}' | ( cd "$STRAY" && env -u WAYPOINT_INBOX -u WAYPOINT_INBOX_MODE \
  HOME="$TMP/fakehome" WAYPOINT_HOME="$H" "$HOOK" prompt )
sleep 2
if grep -q '|home|.*全局模式一条' "$H/inbox/prompts.log" 2>/dev/null; then
  ok "自动探测：退回全局库收件箱"
else
  bad "全局库收件箱未落盘" "$(ls -A "$H/inbox" 2>/dev/null)"
fi
[[ -z "$(git -C "$H" status --porcelain)" ]] && ok "库收件箱不脏库（init-home 已排除 inbox/）" || bad "库收件箱把库弄脏了" "$(git -C "$H" status --porcelain | head -3)"

echo "── 11b. 落盘路由与 agent 回答（实测 schema）──────────────"
# 实测：宿主把 hook 的进程 cwd 设为插件安装目录，项目位置在 payload 的 cwd 字段里（且常为 workspace 根）
REG="$TMP/libreg"; mkdir -p "$REG"; printf '%s\n' "$CP" > "$REG/repos.txt"
printf '{"hook_event_name":"UserPromptSubmit","prompt":"从 workspace 根路由","cwd":"%s"}' "$TMP" | \
  ( cd "$STRAY" && env -u WAYPOINT_INBOX -u WAYPOINT_INBOX_MODE -u WAYPOINT_PROJECT \
      HOME="$TMP/fakehome" WAYPOINT_HOME="$REG" "$HOOK" prompt )
sleep 2
case "$(tail -3 "$CP/.waypoint/inbox/prompts.log" 2>/dev/null)" in
  *"|project-registered|py|从 workspace 根路由"*) ok "路由：payload cwd 是父目录时经登记表定位到项目收件箱" ;;
  *) bad "路由未生效" "$(tail -3 "$CP/.waypoint/inbox/prompts.log" 2>/dev/null)" ;;
esac

# agent 回答：Stop 自带 last_assistant_message，原文必须保留换行（所以落 .md 不落索引行）
# JSON 里只能给 \n 转义（给真换行会让 json.loads 直接失败）
TRANSCRIPT="$TMP/tr.jsonl"
printf '{"r":"user"}\n{"r":"assistant"}\n{"r":"assistant"}\n' > "$TRANSCRIPT"
printf '{"hook_event_name":"Stop","session_id":"deadbeef-1111","transcript_path":"%s","cwd":"%s","last_assistant_message":"方案结论第一段\\n第二段带 **markdown** 与表格"}' "$TRANSCRIPT" "$CP" | \
  cp_run stop
sleep 1
ANSF="$(ls "$CP/.waypoint/inbox/answers/"*.md 2>/dev/null | head -1)"
if [[ -n "$ANSF" ]] && grep -q '第二段带 \*\*markdown\*\* 与表格' "$ANSF" 2>/dev/null; then
  ok "agent 回答原文零 LLM 落盘（换行与 markdown 保留）"
else
  bad "回答原文未落盘" "$(ls "$CP/.waypoint/inbox/answers/" 2>/dev/null)"
fi
case "$(cat "$CP/.waypoint/inbox/answers.log" 2>/dev/null)" in
  *"|deadbeef-1111|"*) ok "answers.log 索引导向原文文件" ;;
  *) bad "索引行缺失" "$(tail -2 "$CP/.waypoint/inbox/answers.log" 2>/dev/null)" ;;
esac
case "$(cat "$CP/.waypoint/inbox/sessions.log" 2>/dev/null)" in
  *"|$TRANSCRIPT|"*"|3") ok "sessions.log 记下 transcript 指针与行数" ;;
  *) bad "会话指针缺失" "$(tail -2 "$CP/.waypoint/inbox/sessions.log" 2>/dev/null)" ;;
esac
# 同一会话只记一次指针（PreToolUse 每次都进来，不能刷成洪水）
printf '{"hook_event_name":"PreToolUse","session_id":"deadbeef-1111","transcript_path":"%s","cwd":"%s","tool_name":"Bash"}' "$TRANSCRIPT" "$CP" | cp_run probe
sleep 1
[[ "$(wc -l < "$CP/.waypoint/inbox/sessions.log" | tr -d ' ')" == "1" ]] && ok "同一会话的指针不重复登记" || bad "指针重复登记" "$(wc -l < "$CP/.waypoint/inbox/sessions.log")"

assert_contains "capture show 把回答列为待归摞" "answers.log: 共 1 行｜已归摞 0｜待归摞 1" run capture show --target "$CP"
assert_contains "drain --full 把正文内联进输出" "第二段带 **markdown** 与表格" run capture drain --target "$CP" --full --commit
assert_contains "drain 后 show 仍能看到回答行数" "answers.log: 共 1 行" run capture show --target "$CP"
grep -q '原文：' "$CP/.waypoint/JOURNAL.md" 2>/dev/null && ok "JOURNAL 里留有回答原文的路径" || bad "JOURNAL 缺原文路径"
grep -q '第二段带 \*\*markdown\*\* 与表格' "$CP/.waypoint/JOURNAL.md" 2>/dev/null && ok "JOURNAL 里拿到回答正文（--full）" || bad "JOURNAL 缺回答正文"
grep -q "$TRANSCRIPT" "$CP/.waypoint/JOURNAL.md" 2>/dev/null && ok "JOURNAL 里留了会话全文指针" || bad "JOURNAL 缺会话指针"
assert_contains "再次 drain 幂等（回答游标也前进了）" "没有待归摞的原料" run capture drain --target "$CP"
[[ -z "$(git -C "$CP" status --porcelain)" ]] && ok "回答落盘不污染工作区（answers/ 也在 exclude 内）" || bad "回答把仓库弄脏了" "$(git -C "$CP" status --porcelain | head -3)"

echo
echo "── 11c. 看板数据源：board --json 带出收件箱 ──────"
# 面板只认 board --json 一个数据源，落盘不进这里就等于面板上看不见
printf '%s\n' "$CP" >> "$H/repos.txt"
run board --json > "$TMP/board.json" 2>"$TMP/board.err"
if [[ -s "$TMP/board.err" ]]; then bad "board --json 不该往 stderr 写东西" "$(head -2 "$TMP/board.err")"; else ok "board --json 的 stderr 干净（游标按收件箱取，不依赖全局 INBOX）"; fi
PT_N="$(wc -l < "$CP/.waypoint/inbox/prompts.log" | tr -cd '0-9')"
PC_N="$(cat "$CP/.waypoint/inbox/.cursor/prompts" 2>/dev/null | tr -cd '0-9')"; PC_N="${PC_N:-0}"
python3 - "$TMP/board.json" "$CP" "$PT_N" "$PC_N" <<'PY' >"$TMP/board.check" 2>&1
import json, sys
d = json.load(open(sys.argv[1]))
owner, want_total, want_cur = sys.argv[2].rstrip("/"), int(sys.argv[3]), int(sys.argv[4])
ibs = d.get("capture", {}).get("inboxes", [])
hit = [x for x in ibs if x["owner"].rstrip("/") == owner]
assert hit, "capture 里没这个仓库的收件箱: %r" % [x["owner"] for x in ibs]
logs = {l["name"]: l for l in hit[0]["logs"]}
assert logs["prompts"]["total"] == want_total, (logs["prompts"], want_total)
assert logs["prompts"]["cursor"] == want_cur, (logs["prompts"], want_cur)
assert logs["prompts"]["pending"] == want_total - want_cur, logs["prompts"]
assert any(l["rows"] for l in hit[0]["logs"]), "rows 全空，面板没有可看的正文"
assert hit[0]["pending"] >= 0
# 面板是倒序看“刚落了什么”：每类 row 以 ISO 时间开头，必须新的在前
for l in hit[0]["logs"]:
    stamps = [r.split()[0] for r in l["rows"]]
    assert stamps == sorted(stamps, reverse=True), (l["name"], stamps)
assert int(hit[0]["last"]) > 0 and hit[0]["last_age"], hit[0]
print("ok")
PY
if grep -qx ok "$TMP/board.check"; then ok "面板拿到收件箱计数、游标、待归摞，且落盘按时间倒序"; else bad "board --json 的 capture 不对" "$(cat "$TMP/board.check")"; fi

echo
echo "═══ 通过 $PASS / 失败 $FAIL ═══"
[[ $FAIL -eq 0 ]] || exit 1
