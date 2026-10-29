#!/usr/bin/env bash
# USAGE-BEGIN
# waypoint.sh — Waypoint 协议辅助工具（无依赖，bash 3.2+ / macOS 兼容）
#
# 项目模式（状态装在项目内 .waypoint/，与代码原子提交）:
#   init [--target P]                        安装协议；若本机有任务库则登记进看板
#   checkpoint [--target P] [--allow-dirty]  抓取 git 事实，预填交接模板
#   status [--target P]                      项目模式状态摘要
#
# 全局模式（任务库 + 会话隔离，默认 ~/.waypoint）:
#   init-home [--home D]                     建库（独立 git 仓库；拒绝寄宿进别的仓库）
#   new <任务线> [--client C] [--sid S] [--project P]   开一条任务线并为其开一个会话
#   resume [--line L] [--sid S] [--client C] 不给参数=列出可接管会话；给了=接管并取锁
#   checkpoint --line L [--sid S] [--client C] [--allow-dirty]  交出（写回本会话）
#   board [--json] [--by-client] [--stale-days N]  ⭐ 各端任务总览（含项目模式）
#   dash [--out F] [--open] [--serve [--port N]]  📊 页面看板（单文件 HTML，双击即看）
#   tasks / switch <任务线> [会话] / status [--line L] [--sid S]
#   lock / unlock / who                       租约锁；项目模式 `lock --target P`，全局模式 `lock --line L --sid S`
#   migrate [--line L] [--client C]          旧版单文件布局 → 会话布局
#   repos ls                                 已登记的项目模式仓库
#
#   兼容别名：--task <线> 等价 --line；--task 缺省 sid 时取该线最近交出的会话
#
# 环境变量: WAYPOINT_HOME 覆盖库路径（--home 优先级更高）
# USAGE-END
set -euo pipefail

die() { echo "错误: $*" >&2; exit 1; }
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
usage() {  # 只取两个标记行之间的注释；用 ^...$ 锚点，否则会匹配到本函数自身而一路打印到文件末尾
  sed -n '/^# USAGE-BEGIN$/,/^# USAGE-END$/p' "$0" | sed -e '1d' -e '$d' -e 's/^# \{0,1\}//'
}

PRE=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target|--home|--line|--sid|--client|--project|--ttl|--stale-days|--task|-l|--out|--port)
      [[ $# -ge 2 ]] || die "缺少参数值: $1"
      if [[ "$1" == "--task" && "$2" == --* ]]; then PRE+=("$1"); shift; else PRE+=("$1" "$2"); shift 2; fi ;;
    --json|--by-client|--force|--allow-dirty|--open|--serve) PRE+=("$1"); shift ;;
    -h|--help) PRE+=("$1"); shift ;;
    -*) die "未知参数: $1" ;;
    *) break ;;
  esac
done
if [[ $# -eq 0 ]]; then
  if [[ ${#PRE[@]} -gt 0 ]]; then set -- "${PRE[@]}"; else set -- help; fi
fi
CMD="$1"; shift || true
if [[ ${#PRE[@]} -gt 0 ]]; then set -- "${PRE[@]}" "$@"; fi

TARGET="."
HOME_DIR="${WAYPOINT_HOME:-$HOME/.waypoint}"
ALLOW_DIRTY=0
LINE=""; SID=""; CLIENT=""; PROJ_PATH=""; TTL_MIN=45
BOARD_JSON=0; BY_CLIENT=0; STALE_DAYS=7; FORCE=0
DASH_OUT=""; DASH_OPEN=0; DASH_SERVE=0; DASH_PORT=8787
POS1=""; POS2=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --home) HOME_DIR="$2"; shift 2 ;;
    --project) PROJ_PATH="$2"; shift 2 ;;
    --client) CLIENT="$2"; shift 2 ;;
    --line|-l) LINE="$2"; shift 2 ;;
    --sid) SID="$2"; shift 2 ;;
    --ttl) TTL="$2"; shift 2; TTL="$(printf '%s' "$TTL" | tr -cd '0-9')"; TTL_MIN="${TTL:-45}" ;;
    --stale-days) STALE_DAYS="$2"; shift 2 ;;
    --json) BOARD_JSON=1; shift ;;
    --by-client) BY_CLIENT=1; shift ;;
    --out) DASH_OUT="$2"; shift 2 ;;
    --open) DASH_OPEN=1; shift ;;
    --serve) DASH_SERVE=1; shift ;;
    --port) DASH_PORT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    # v1 兼容：--task [线名]；不带值则用 CURRENT
    --task)
      if [[ $# -ge 2 && "$2" != --* ]]; then LINE="$2"; shift 2; else LINE="__CURRENT__"; shift; fi ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "未知参数: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$POS1" ]]; then POS1="$1"; elif [[ -z "$POS2" ]]; then POS2="$1";
      else echo "多余参数: $1" >&2; exit 1; fi
      shift ;;
  esac
done

# ---------- 小工具 ----------

now_iso() { date +%Y-%m-%dT%H:%M:%S%z; }
now_epoch() { date +%s; }
count_of() {  # 计数；无匹配或文件不存在都归 0（grep 报错时输出为空）
  local n; n="$(grep -cE "$1" "$2" 2>/dev/null || true)"; printf '%s' "${n:-0}"
}

# 任务线名：空格/斜杠 → -，去首尾 -
slug() {
  local s; s="$(printf '%s' "$1" | tr ' /' '--' | sed 's/^-*//;s/-*$//')"
  [[ -n "$s" ]] || die "任务线名不能为空"
  printf '%s' "$s"
}
# 会话名（端）：小写，只留 [a-z0-9._-]
norm_sid() {
  local s; s="$(printf '%s' "${1:-}" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9._-')"
  [[ -n "$s" ]] || s="default"
  printf '%s' "$s"
}

# 安全取 git 输出（无提交/非仓库不炸，修 P0-3）
safe_git() { local fb="$1"; shift; local r; r="$(git "$@" 2>/dev/null || true)"; printf '%s' "${r:-$fb}"; }

is_repo() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }
require_git() { is_repo "$1" || die "$1 不是 git 仓库，先 git init"; }
repo_root() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || true; }

# 把运行时产物（锁等）排除在版本跟踪与 git status 之外，不动用户 .gitignore（修 P0-2）
# 用 .git/info/exclude（本地生效、从不入库）；worktree/子模块的 .git 是文件时跳过并告警
ensure_excluded() {  # $1=仓库内任一路径 $2=pattern
  local root; root="$(repo_root "$1")"; [[ -n "$root" ]] || return 0
  local gd="$root/.git"
  if [[ ! -d "$gd" ]]; then
    echo "提示: $gd 不是目录（worktree/子模块），未能自动排除 '$2'；请手工加入 .gitignore" >&2
    return 0
  fi
  local f="$gd/info/exclude"
  mkdir -p "$gd/info"
  [[ -f "$f" ]] || : > "$f"
  grep -qxF "$2" "$f" 2>/dev/null || printf '%s\n' "$2" >> "$f"
  return 0
}

# ---------- 元数据（key=value 纯文本，便于 bash 3.2 解析）----------

meta_get() {  # $1=file $2=key
  [[ -f "$1" ]] || return 0
  local v; v="$(grep -m1 "^$2=" "$1" 2>/dev/null || true)"
  printf '%s' "${v#*=}"
}

session_epoch() {  # 会话最近活动时间：优先 .session 的 epoch，退回文件 mtime
  local sdir="$1" ep
  ep="$(meta_get "$sdir/.session" last_epoch)"
  [[ -n "$ep" ]] || ep="$(mtime_of "$sdir/HANDOFF.md")"
  printf '%s' "${ep:-0}"
}

mtime_of() {
  [[ -f "$1" ]] || { echo 0; return; }
  local m; m="$(stat -f %m "$1" 2>/dev/null || true)"          # BSD/macOS
  [[ -n "$m" ]] || m="$(stat -c %Y "$1" 2>/dev/null || true)"  # GNU
  printf '%s' "${m:-0}"
}

humanize_age() {  # 秒 → 中文相对时间
  local d=$(( $(now_epoch) - $1 ))
  [[ $d -lt 0 ]] && d=0
  if   [[ $d -lt 90 ]];   then echo "刚刚"
  elif [[ $d -lt 5400 ]]; then echo "$(( d / 60 )) 分钟前"
  elif [[ $d -lt 86400 ]];then echo "$(( d / 3600 )) 小时前"
  elif [[ $d -lt 2592000 ]];then echo "$(( d / 86400 )) 天前"
  else echo "$(( d / 2592000 )) 个月前"
  fi
}

plan_counts() {  # $1=PLAN.md → "已勾/总数"
  [[ -f "$1" ]] || { echo "-"; return; }
  local d t; d="$(count_of '^[[:space:]]*-[[:space:]]*\[[xX]\]' "$1")"
  t=$(( d + $(count_of '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$1") ))
  [[ $t -gt 0 ]] && echo "$d/$t" || echo "-"
}

handoff_next() {  # 取 HANDOFF 的「下一步」首条实质内容，截断
  local f="$1" line=""
  [[ -f "$f" ]] || { echo ""; return; }
  while IFS= read -r l; do
    case "$l" in
      "## "*|"") continue ;;
      *[![:space:]]*) line="$(printf '%s' "$l" | sed 's/^[0-9]*[.)][[:space:]]*//' | sed 's/^-[[:space:]]*//' | cut -c1-72)"; break ;;
    esac
  done <<EOF
$(sed -n '/^## 下一步/,/^## /p' "$f" 2>/dev/null || true)
EOF
  printf '%s' "$line"
}

handoff_client() {  # 交接快照标题行里的客户端名；缺则回退同目录 .session
  local f="$1" v=""
  [[ -f "$f" ]] || { echo "未知"; return 0; }
  v="$(meta_head_client "$f")"
  [[ -n "$v" ]] || v="$(meta_get "$(dirname "$f")/.session" client)"
  printf '%s' "${v:-未知}"
  return 0
}
meta_head_client() {
  [[ -f "$1" ]] || return 0
  local h; h="$(head -1 "$1" 2>/dev/null || true)"
  case "$h" in
    *"by "*) printf '%s' "${h##*by }" | tr -d ' \r' ;;
    *) printf '' ;;
  esac
}

json_escape() {  # 转义成 JSON 字符串内容；`<`/`>` 也转，保证可内嵌进 <script>
  printf '%s' "$1" | tr -d '\001\002\r\n' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/</\\u003c/g' -e 's/>/\\u003e/g'
}

# ---------- 锁：落在 <库或仓库>/locks/，已被 exclude，不再污染 git status ----------

lock_file() {  # $1=base $2=line $3=sid
  printf '%s/locks/%s__%s.lock' "$1" "$(printf '%s' "$2" | tr ' /' '--')" "$(printf '%s' "$3" | tr ' /' '--')"
}

# 锁文件字段：owner / kind / target / at(ISO) / lease(epoch) / pid
# pid=0 表示会话锁（只看租约）；非 0 表示后台作业锁（进程死了即视为过期）
lock_write() {  # $1=file $2=owner $3=kind $4=target $5=ttl_min $6=at_iso $7=pid
  mkdir -p "$(dirname "$1")"
  local exp=$(( $(now_epoch) + ${5:-45} * 60 ))
  { echo "owner=${2}"; echo "kind=${3}"; echo "target=${4}"; echo "at=${6}"; echo "lease=${exp}"; echo "pid=${7:-0}"; } > "$1"
  chmod 600 "$1" 2>/dev/null || true
  return 0
}

lock_state() {  # $1=file → 打印 "alive:<owner>" / "expired:<owner>" / "none"
  [[ -f "$1" ]] || { echo none; return; }
  local owner lease pid
  owner="$(meta_get "$1" owner)"; lease="$(meta_get "$1" lease)"; pid="$(meta_get "$1" pid)"
  if [[ -n "$pid" && "$pid" != "0" ]] && ! kill -0 "$pid" 2>/dev/null; then
    echo "expired:${owner:-?}"; return
  fi
  if [[ -n "$lease" && "$(now_epoch)" -lt "$lease" ]]; then echo "alive:${owner:-?}"; else echo "expired:${owner:-?}"; fi
}

lock_check() {  # $1=file $2=me $3=force → 他人有效锁则拒绝
  [[ $FORCE -eq 1 ]] && return 0
  local st; st="$(lock_state "$1")"
  case "$st" in
    alive:*)
      local who="${st#alive:}"
      [[ "$who" == "$2" ]] && return 0
      die "会话被 '$who' 锁住且租约未过期。确认对端已停手后加 --force 抢占（会记入 JOURNAL）"
      ;;
  esac
}

# ---------- 会话模型解析 ----------

require_lib() { [[ -d "$HOME_DIR/tasks" ]] || die "全局库未初始化: ${HOME_DIR}（先运行: waypoint.sh init-home）"; }

sessions_of() {  # $1=line → 每行一个 sid（含 legacy "default"）
  local ld="$HOME_DIR/tasks/$1" s
  if [[ -d "$ld/sessions" ]]; then
    for s in "$ld"/sessions/*/; do [[ -d "$s" ]] && basename "$s"; done
  fi
  # legacy：线目录里直接有 HANDOFF.md，视为会话 default
  if [[ -f "$ld/HANDOFF.md" ]]; then echo "default"; fi
}

latest_session_of() {  # $1=line → 最近交出的 sid（无则 default/首个）
  local ld="$HOME_DIR/tasks/$1" best="" best_ep=-1 s ep
  for s in $(sessions_of "$1"); do
    if [[ "$s" == "default" ]]; then ep="$(session_epoch "$ld")"; else ep="$(session_epoch "$ld/sessions/$s")"; fi
    if [[ "$ep" -gt "$best_ep" ]]; then best_ep="$ep"; best="$s"; fi
  done
  [[ -n "$best" ]] || { s="$(sessions_of "$1" | head -1)"; best="${s:-}"; }
  printf '%s' "$best"
}

resolve_ctx() {  # 依 LINE/SID/CURRENT 定出 LINE/SID/SESS_DIR/LOCK_FILE
  # $1=1 时会话目录必须存在；$1=0 时允许不存在（由调用方创建，用于跨端接管开新会话）
  require_lib
  local cur=""
  if [[ -f "$HOME_DIR/CURRENT" ]]; then cur="$(cat "$HOME_DIR/CURRENT")"; fi
  if [[ -z "$LINE" ]]; then
    [[ -n "$cur" ]] || die "无当前任务（CURRENT 缺失）。用: waypoint.sh new <任务线> 或 resume 查看候选"
    LINE="${cur%%/*}"; [[ -z "$SID" && "$cur" == */* ]] && SID="${cur#*/}"
  fi
  LINE="$(slug "${LINE#__CURRENT__}")"
  [[ -d "$HOME_DIR/tasks/$LINE" ]] || die "任务线不存在: ${LINE}（用 tasks 或 resume 查看）"
  if [[ -z "$SID" ]]; then SID="$(latest_session_of "$LINE")"; fi
  [[ -n "$SID" ]] || die "任务线 $LINE 还没有会话。先: waypoint.sh new $LINE --client <你的客户端>"
  SID="$(norm_sid "$SID")"
  sess_dir_of "$LINE" "$SID"
  if [[ $1 -eq 1 ]]; then
    [[ -d "$SESS_DIR" ]] || die "会话不存在: $LINE/${SID}（该线候选: $(sessions_of "$LINE" | tr '\n' ' ')）"
  fi
  LOCK_FILE="$(lock_file "$HOME_DIR" "$LINE" "$SID")"
  CLIENT_RESOLVED="${CLIENT:-$(meta_get "$SESS_DIR/.session" client)}"
  if [[ -z "$CLIENT_RESOLVED" ]]; then CLIENT_RESOLVED="$SID"; fi
  return 0
}

# 会话目录：legacy 单文件布局的 default 在线目录里，其余在 sessions/<端>
sess_dir_of() {  # $1=line $2=sid → 赋值 SESS_DIR
  if [[ "$2" == "default" && ! -d "$HOME_DIR/tasks/$1/sessions/default" && -f "$HOME_DIR/tasks/$1/HANDOFF.md" ]]; then
    SESS_DIR="$HOME_DIR/tasks/$1"
  else
    SESS_DIR="$HOME_DIR/tasks/$1/sessions/$2"
  fi
}

session_files_copy() {  # $1=源会话目录 $2=目标会话目录；带不存在的用模板兜底
  local f
  for f in PLAN.md HANDOFF.md JOURNAL.md DECISIONS.md; do
    if [[ -f "$1/$f" ]]; then cp "$1/$f" "$2/$f"; else cp "$KIT_DIR/templates/$f" "$2/$f"; fi
  done
  return 0
}

write_session_meta() {  # $1=sdir $2=line $3=sid $4=client $5=parent $6=last_epoch
  printf 'line=%s\nsid=%s\nclient=%s\ncreated_at=%s\nparent=%s\nstatus=open\nlast_checkpoint=-\nlast_epoch=%s\nlast_head=-\nlast_project_head=-\n' \
    "$2" "$3" "$4" "$(now_iso)" "$5" "$6" > "$1/.session"
  return 0
}

set_current() { printf '%s/%s\n' "$1" "$2" > "$HOME_DIR/CURRENT"; }

# ---------- 项目模式 ----------

cmd_init() {
  [[ -d "$TARGET" ]] || die "目标路径不存在: $TARGET"
  TARGET="$(cd "$TARGET" && pwd)"
  require_git "$TARGET"
  local WP="$TARGET/.waypoint"
  if [[ -d "$WP" ]]; then
    die "$WP 已存在。如需重装请先手工处理（协议文件可能含任务状态，勿随意删除）"
  fi
  mkdir -p "$WP/archive" "$WP/locks"
  ensure_excluded "$WP" ".waypoint/locks/"
  for f in PROTOCOL.md TASK.md PLAN.md HANDOFF.md JOURNAL.md DECISIONS.md; do
    cp "$KIT_DIR/templates/$f" "$WP/$f"
  done
  echo "已创建 $WP/{PROTOCOL,TASK,PLAN,HANDOFF,JOURNAL,DECISIONS}.md、archive/ 与 locks/（后者已排除在版本跟踪外）"

  if [[ ! -f "$TARGET/AGENTS.md" ]]; then
    cp "$KIT_DIR/templates/AGENTS.md" "$TARGET/AGENTS.md"
    echo "已安装 AGENTS.md"
  else
    echo "提示: 项目已有 AGENTS.md，未覆盖。请手工合并指针段落（见 INSTALL_FOR_AGENTS.md §2）"
  fi
  # 登记到本机任务库看板（无库则跳过；修 P0-4：提示先提交安装）
  if [[ -d "$HOME_DIR/tasks" ]]; then
    mkdir -p "$HOME_DIR"; touch "$HOME_DIR/repos.txt"
    grep -qxF "$TARGET" "$HOME_DIR/repos.txt" 2>/dev/null || printf '%s\n' "$TARGET" >> "$HOME_DIR/repos.txt"
    echo "已登记到看板: $HOME_DIR/repos.txt（waypoint.sh board 可见）"
  fi
  echo "完成。下一步:"
  echo "  1. git add -A && git commit -m \"chore: install waypoint protocol\"   ← 先提交安装，否则 checkpoint 会判为脏"
  echo "  2. 填写 .waypoint/TASK.md 与 PLAN.md 立项"
}

cmd_checkpoint() {
  [[ -d "$TARGET" ]] || die "目标路径不存在: $TARGET"
  TARGET="$(cd "$TARGET" && pwd)"
  require_git "$TARGET"
  local WP="$TARGET/.waypoint"
  [[ -d "$WP" ]] || die "未安装协议，先运行: waypoint.sh init --target $TARGET"

  local dirty; dirty="$(git -C "$TARGET" status --porcelain)"
  if [[ -n "$dirty" && $ALLOW_DIRTY -eq 0 ]]; then
    echo "$dirty"
    die "工作区不干净。先 commit，或确认故意不提交后加 --allow-dirty（并在交接快照 Intentionally Dirty 中逐个列出）"
  fi
  local lk="$WP/locks" st=""
  mkdir -p "$lk"; ensure_excluded "$WP" ".waypoint/locks/"
  echo "=== 交接事实（项目模式，由 waypoint.sh 抓取，agent 补齐叙事后整体重写 .waypoint/HANDOFF.md）==="
  echo
  echo "时间: $(now_iso)   ← 时间戳以此为准，勿自行编造"
  echo "客户端: ${CLIENT:-未指定}   ← 可用 --client <端名> 指定；HANDOFF 标题的 by <客户端名> 用它"
  echo "分支: $(safe_git "(未知)" -C "$TARGET" rev-parse --abbrev-ref HEAD)"
  echo "HEAD: $(safe_git "(无提交)" -C "$TARGET" log -1 --format='%h %s')"
  echo
  echo "最近 10 次提交:"
  git -C "$TARGET" log --oneline -10 2>/dev/null || echo "(尚无提交)"
  echo
  echo "本轮改动概览（工作区 vs HEAD，未跟踪文件见下方）:"
  git -C "$TARGET" diff --stat HEAD 2>/dev/null || true
  [[ -n "$(git -C "$TARGET" diff --stat HEAD 2>/dev/null)" ]] || echo "(工作区无改动)"
  echo
  if [[ -n "$dirty" ]]; then echo "故意未提交的文件（逐个写入 Intentionally Dirty）:"; echo "$dirty"; else echo "工作区: 干净"; fi
  cat <<'EOF'

=== JOURNAL 追加条目骨架 ===

## [<上面抓到的时间>] <客户端名> · 迭代<N>
- 做了什么：
- 改动：<diffstat 涉及的文件>
- 验证：<命令 → 结果>
- 踩坑：
- 下一步：
- commit：<上面 HEAD 的短 hash>
EOF
}

cmd_status() {
  [[ -d "$TARGET" ]] || die "目标路径不存在: $TARGET"
  TARGET="$(cd "$TARGET" && pwd)"
  require_git "$TARGET"
  local WP="$TARGET/.waypoint"
  if [[ ! -d "$WP" ]]; then echo "未安装协议（$WP 不存在）"; exit 0; fi
  echo "== Waypoint 状态（项目模式: ${TARGET}）=="
  local any=""; for f in "$WP"/locks/*.lock; do [[ -f "$f" ]] && any="$any $(basename "$f" .lock)"; done
  if [[ -n "$any" ]]; then
    for f in "$WP"/locks/*.lock; do [[ -f "$f" ]] || continue; echo "锁: $(basename "$f" .lock) → $(lock_state "$f")"; done
  elif [[ -f "$WP/LOCK" ]]; then echo "锁(旧版): $(cat "$WP/LOCK")"
  else echo "锁: 无"; fi
  for f in TASK PLAN HANDOFF JOURNAL DECISIONS; do
    [[ -f "$WP/$f.md" ]] && echo "$f.md: $(wc -l < "$WP/$f.md" | tr -d ' ') 行" || echo "$f.md: 缺失"
  done
  echo "计划进度: $(plan_counts "$WP/PLAN.md")"
  echo "-- 最近提交 --"
  git -C "$TARGET" log --oneline -5 2>/dev/null || echo "(尚无提交)"
  echo "-- 工作区 --"
  git -C "$TARGET" status --short --branch
  if [[ -f "$WP/HANDOFF.md" ]]; then echo "-- HANDOFF 下一步 --"; echo "  $(handoff_next "$WP/HANDOFF.md")"; fi
}

# ---------- 全局模式：建库 / 开线 ----------

cmd_init_home() {
  if [[ -d "$HOME_DIR" ]]; then HOME_DIR="$(cd "$HOME_DIR" && pwd)"
  else mkdir -p "$HOME_DIR"; HOME_DIR="$(cd "$HOME_DIR" && pwd)"; fi
  [[ -d "$HOME_DIR/tasks" ]] && die "$HOME_DIR 已是全局库（tasks/ 存在）。如需重建请先手工备份删除"

  # 修 P0-1：全局库必须是独立仓库，否则 git add/commit 会作用到宿主仓库
  if is_repo "$HOME_DIR"; then
    local root; root="$(repo_root "$HOME_DIR")"
    if [[ "$root" != "$HOME_DIR" && $FORCE -eq 0 ]]; then
      die "$HOME_DIR 位于另一个 git 仓库内（${root}）。全局库需独立成库以免污染宿主仓库；换一个 --home，或确认嵌套可接受后加 --force"
    fi
  fi

  mkdir -p "$HOME_DIR/tasks" "$HOME_DIR/archive" "$HOME_DIR/locks"
  cp "$KIT_DIR/templates/PROTOCOL.md" "$HOME_DIR/PROTOCOL.md"
  : > "$HOME_DIR/repos.txt"

  cat > "$HOME_DIR/RULES_SNIPPET.md" <<EOF
# 本机 Waypoint 全局任务库（把本段贴进客户端的用户级/全局规则）

- 数据目录: ${HOME_DIR}（本行是权威路径记录，勿凭记忆猜）
- 脚本: $(cd "$KIT_DIR" && pwd)/scripts/waypoint.sh（若本路径已失效，重新 clone 后 init-home --home ${HOME_DIR}）
- 布局: 任务线 tasks/<线>/TASK.md（合同，共享）+ 会话 tasks/<线>/sessions/<端>/{PLAN,HANDOFF,JOURNAL,DECISIONS}.md；当前指针见 CURRENT（格式 <线>/<端>）
- 锁: ${HOME_DIR}/locks/（已被 .git/info/exclude 排除，不污染 git status；他人租约未过期时不要抢，先问用户）
- 端名: 本客户端固定用一个名字（如 qoder / codebuddy / trae），所有命令都带 \`--client <端名>\`；名字不一致会误开新会话
- 触发词:
  - 「继续任务」→ 先跑 \`waypoint.sh resume\` **列出可接管会话让用户选**（不得代选、不得直接接 CURRENT），再接管（复述状态后再动手）
  - 「checkpoint」→ 交出到**本端自己的会话**（绝不改别的端的文件）：更新会话文件 + 把 .session 的 last_epoch/last_checkpoint 改为今天 → 在 ${HOME_DIR} 内 git commit（前缀 waypoint:）→ \`unlock --line <线> --sid <端>\`
  - 「任务看板」/「各端进度」→ \`waypoint.sh board\`（--by-client 看端视图，--json 供面板）
  - 「新任务 <线名>」→ \`waypoint.sh new <线名> --client <端>\`
  - 「切换任务 <线名>」→ \`waypoint.sh switch <线名>\`
- 若任务线有 project.txt: 该项目仓库的代码改动仍在项目仓库提交，会话只记录锚定的 HEAD
- 完整协议: ${HOME_DIR}/PROTOCOL.md（冲突时以它为准）
EOF

  if ! is_repo "$HOME_DIR" || [[ "$(repo_root "$HOME_DIR")" == "$HOME_DIR" ]]; then
    git -C "$HOME_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || git -C "$HOME_DIR" init -q
  fi
  ensure_excluded "$HOME_DIR" "locks/"
  ensure_excluded "$HOME_DIR" "dashboard.html"   # 页面看板产物，不该把库弄脏
  git -C "$HOME_DIR" add -A
  if ! git -C "$HOME_DIR" commit -q -m "waypoint: init home library" 2>/dev/null; then
    echo "(全局库首次提交未完成：多为 git 身份未配置。请设置 git config --global user.name/user.email 后手工提交)"
  fi

  echo "全局任务库已建立: $HOME_DIR"
  echo "  PROTOCOL.md        协议本体"
  echo "  RULES_SNIPPET.md   ⭐ 注入文本——贴进客户端用户级规则"
  echo "  CURRENT            当前会话指针（<线>/<端>）"
  echo "  tasks/<线>/sessions/<端>/   会话隔离布局"
  echo "  locks/             租约锁（不入库）"
  echo "  dashboard.html     dash 生成的页面看板（不入库）"
  echo "  repos.txt          项目模式仓库登记（board 用）"
  echo
  echo "下一步: 1) 把 RULES_SNIPPET.md 贴进各客户端用户级规则  2) $0 new <任务线> --client <端>"
}

cmd_new() {
  require_lib
  [[ -n "$POS1" ]] || die "用法: waypoint.sh new <任务线> [--client <端>] [--sid <名>] [--project <路径>]"
  LINE="$(slug "$POS1")"
  local ld="$HOME_DIR/tasks/$LINE"
  local sid; sid="$(norm_sid "${SID:-${CLIENT:-main}}")"
  local sdir="$ld/sessions/$sid"
  if [[ -d "$sdir" ]]; then
    if [[ $FORCE -eq 0 ]]; then die "会话已存在: $LINE/${sid}（换 --sid，或用 resume $LINE/$sid 继续它）"; fi
  fi
  mkdir -p "$sdir"
  for f in PLAN.md HANDOFF.md JOURNAL.md DECISIONS.md; do cp "$KIT_DIR/templates/$f" "$sdir/$f"; done
  if [[ ! -f "$ld/TASK.md" ]]; then cp "$KIT_DIR/templates/TASK.md" "$ld/TASK.md"; fi
  write_session_meta "$sdir" "$LINE" "$sid" "${CLIENT:-$sid}" "-" "$(now_epoch)"

  if [[ -n "$PROJ_PATH" ]]; then
    local pp; pp="$(cd "$PROJ_PATH" 2>/dev/null && pwd || true)"
    [[ -n "$pp" ]] || die "--project 路径不存在: ${PROJ_PATH}"
    echo "$pp" > "$ld/project.txt"
    echo "已锚定项目: ${pp}（checkpoint 时记录该项目 HEAD）"
  fi
  set_current "$LINE" "$sid"
  git -C "$HOME_DIR" add "tasks/$LINE" CURRENT
  git -C "$HOME_DIR" commit -q -m "waypoint: 新任务 $LINE ($sid)" 2>/dev/null || true
  echo "已开任务线并接管会话: $LINE/$sid"
  echo "  合同（线级共享）: $ld/TASK.md"
  echo "  你的会话（端级隔离）: $sdir"
  echo "下一步: 填 $ld/TASK.md 的 DoD 与 $sdir/PLAN.md，然后干活；换端时用 waypoint.sh resume 查看候选。"
}

# ---------- 接管：列候选 / 真正接管 ----------

candidate_rows() {  # 输出 TSV: epoch \t 线/端 \t client \t 计划 \t 锁态 \t 下一步
  local ld s sdir ep lock
  for ld in "$HOME_DIR"/tasks/*/; do
    [[ -d "$ld" ]] || continue
    local line; line="$(basename "$ld")"
    for s in $(sessions_of "$line"); do
      if [[ "$s" == "default" && ! -d "$ld/sessions/default" ]]; then sdir="$ld"; else sdir="$ld/sessions/$s"; fi
      ep="$(session_epoch "$sdir")"
      lock="$(lock_state "$(lock_file "$HOME_DIR" "$line" "$s")")"
      printf '%s\t%s/%s\t%s\t%s\t%s\t%s\n' "$ep" "$line" "$s" \
        "$(meta_get "$sdir/.session" client)" "$(plan_counts "$sdir/PLAN.md")" "$lock" "$(handoff_next "$sdir/HANDOFF.md")"
    done
  done | sort -t"$(printf '\t')" -k1 -rn
}

cmd_resume() {
  require_lib
  # 形如 line/sid 的位置参数
  if [[ -n "$POS1" && "$POS1" == */* ]]; then LINE="${POS1%%/*}"; SID="${POS1#*/}"; fi
  [[ -n "$POS1" && -z "$LINE" ]] && LINE="$POS1"

  if [[ -z "$LINE" ]]; then            # —— 列出候选，让用户选（功能 2 的核心）
    local rows; rows="$(candidate_rows)"
    if [[ -z "$rows" ]]; then echo "没有可接管的会话。先: waypoint.sh new <任务线> --client <端>"; return 0; fi
    local cur=""; [[ -f "$HOME_DIR/CURRENT" ]] && cur="$(cat "$HOME_DIR/CURRENT")"
    echo "== 可接管会话（按最近交出时间排序；选一个继续，或用 resume <线>/<端> 指定）=="
    local ep full cli plan lock next mark age tag
    while IFS="$(printf '\t')" read -r ep full cli plan lock next; do
      [[ -n "$full" ]] || continue
      age="$(humanize_age "$ep")"
      mark=" "; [[ "$full" == "$cur" ]] && mark="*"
      tag=""; [[ "$lock" == alive:* ]] && tag="  🔒被锁:${lock#alive:}"
      [[ $(( ep + STALE_DAYS * 86400 )) -lt $(now_epoch) ]] && tag="$tag  ⚠陈旧>${STALE_DAYS}d"
      printf '  %s %s  端=%s  计划=%s  最近=%s%s\n     └ 下一步: %s\n' \
        "$mark" "$full" "${cli:-未知}" "$plan" "$age" "$tag" "${next:-（未填）}"
    done <<EOF
$rows
EOF
    echo
    echo "接管: waypoint.sh resume <线>/<端> --client <你的端名>（会取租约锁并打印必读清单）"
    return 0
  fi

  LINE="$(slug "$LINE")"
  [[ -d "$HOME_DIR/tasks/$LINE" ]] || die "任务线不存在: $LINE"
  if [[ -z "$SID" ]]; then
    local cs; cs="$(sessions_of "$LINE")"
    local cn; cn="$(printf '%s\n' "$cs" | grep -c . || true)"
    if [[ "$cn" -gt 1 && $FORCE -eq 0 ]]; then
      echo "任务线 $LINE 有多个会话，请指定其一（本端将继承所选会话）:"
      local c
      for c in $cs; do echo "  - $LINE/$c"; done
      return 0
    fi
    SID="$(latest_session_of "$LINE")"
  fi
  resolve_ctx 1
  local me; me="$(norm_sid "${CLIENT:-$SID}")"
  lock_check "$LOCK_FILE" "$me"
  local parent_sid="$SID" pdir="$SESS_DIR"
  if [[ "$SID" != "$me" ]]; then   # 跨端接管 → 为本端开新会话并从被接管会话继承
    SID="$me"; CLIENT="$SID"
    resolve_ctx 0
    if [[ ! -d "$SESS_DIR" ]]; then
      mkdir -p "$SESS_DIR"
      session_files_copy "$pdir" "$SESS_DIR"
      write_session_meta "$SESS_DIR" "$LINE" "$SID" "$CLIENT" "$parent_sid" "$(now_epoch)"
      echo "已为端 '$SID' 新建会话，继承自 '$LINE/$parent_sid'（PLAN/DECISIONS/HANDOFF/JOURNAL 已带入）"
    fi
  fi
  set_current "$LINE" "$SID"
  LOCK_FILE="$(lock_file "$HOME_DIR" "$LINE" "$SID")"
  # pid=0：接管它的是人和会话本身，不是某个短命进程，因此只看租约
  lock_write "$LOCK_FILE" "${CLIENT:-$SID}" "resume" "$LINE/$SID" "$TTL_MIN" "$(now_iso)" 0
  git -C "$HOME_DIR" add CURRENT 2>/dev/null || true
  git -C "$HOME_DIR" commit -q -m "waypoint: 接管 $LINE/$SID" 2>/dev/null || true

  echo "== 接管：$LINE/$SID =="
  echo "必读（按序）: tasks/$LINE/TASK.md → sessions/$SID/HANDOFF.md → sessions/$SID/PLAN.md → JOURNAL 末条"
  echo
  echo "合同 DoD:"; sed -n '/^## 目标/,/^## /p' "$HOME_DIR/tasks/$LINE/TASK.md" 2>/dev/null | sed 's/^/  /' | head -12
  echo "你的会话状态:"
  echo "  端: $(meta_get "$SESS_DIR/.session" client)  继承自: $(meta_get "$SESS_DIR/.session" parent)  计划: $(plan_counts "$SESS_DIR/PLAN.md")"
  echo "  下一步: $(handoff_next "$SESS_DIR/HANDOFF.md")"
  local anchor=""
  if [[ -f "$HOME_DIR/tasks/$LINE/project.txt" ]]; then
    anchor="$(head -1 "$HOME_DIR/tasks/$LINE/project.txt")"
    if [[ -n "$anchor" && -d "$anchor" ]]; then
      echo "  项目锚: $anchor  分支 $(safe_git "?" -C "$anchor" rev-parse --abbrev-ref HEAD)  HEAD $(safe_git "(无提交)" -C "$anchor" log -1 --format='%h %s')"
    else
      echo "  项目锚: ${anchor}（路径无效，请更新 project.txt）"
    fi
  fi
  echo "  锁: 已取（租约 ${TTL_MIN} 分钟，owner=${CLIENT:-$SID}）"
  echo
  echo "请按协议复述状态给用户确认后再动手。绝不从头重做已完成的工作。"
}

# ---------- 交出 ----------

cmd_checkpoint_task() {
  [[ -n "$LINE" || -n "$POS1" ]] && { [[ -z "$LINE" ]] && LINE="$POS1"; }
  resolve_ctx 1
  local me; me="$(norm_sid "${CLIENT:-$(meta_get "$SESS_DIR/.session" client)}")"
  [[ -n "$me" ]] || me="$SID"
  lock_check "$LOCK_FILE" "$me"

  local dirty; dirty="$(git -C "$HOME_DIR" status --porcelain)"
  if [[ -n "$dirty" && $ALLOW_DIRTY -eq 0 ]]; then
    echo "$dirty"
    die "全局库不干净。先 commit 状态文件，或加 --allow-dirty 并在 HANDOFF 的 Intentionally Dirty 中说明"
  fi
  echo "=== 交接事实（全局模式，会话 $LINE/${SID}；agent 补齐叙事后整体重写 HANDOFF.md，然后在全局库 commit）==="
  echo
  echo "任务线: $LINE     会话(端): $SID"
  echo "时间: $(now_iso)   ← 时间戳以此为准，勿自行编造"
  echo "客户端: ${me}   ← 若与实际不符请改用真实端名，并同步 .session 的 client="
  echo "会话目录: $SESS_DIR"
  echo "全局库: $HOME_DIR @ $(safe_git "(尚无提交)" -C "$HOME_DIR" log -1 --format='%h %s')"
  echo
  echo "本会话最近状态: 计划 $(plan_counts "$SESS_DIR/PLAN.md")   JOURNAL 条数 $(count_of '^## ' "$SESS_DIR/JOURNAL.md")"
  if [[ -f "$HOME_DIR/tasks/$LINE/project.txt" ]]; then
    local p; p="$(head -1 "$HOME_DIR/tasks/$LINE/project.txt")"
    if [[ -n "$p" && -d "$p" ]] && is_repo "$p"; then
      echo "关联项目: $p"
      echo "  分支: $(safe_git "?" -C "$p" rev-parse --abbrev-ref HEAD)"
      echo "  HEAD:  $(safe_git "(无提交)" -C "$p" log -1 --format='%h %s')"
      local pd; pd="$(git -C "$p" status --porcelain)"
      if [[ -n "$pd" ]]; then echo "  工作区: dirty（项目侧改动由你在项目仓库正常提交）"; echo "$pd" | sed 's/^/    /'; else echo "  工作区: clean"; fi
    else
      echo "关联项目: ${p}（路径无效或非 git 仓库，请更新 project.txt）"
    fi
  else
    echo "关联项目: 无"
  fi
  echo
  echo "同线其他会话（避免重复劳动，接管时先扫一眼）:"
  local s other
  for s in $(sessions_of "$LINE"); do
    [[ "$s" == "$SID" ]] && continue
    sess_dir_of "$LINE" "$s"; other="$SESS_DIR"
    echo "  - $LINE/$s  端=$(meta_get "$other/.session" client)  计划=$(plan_counts "$other/PLAN.md")  最近=$(humanize_age "$(session_epoch "$other")")  下一步: $(handoff_next "$other/HANDOFF.md")"
  done
  echo
  cat <<'EOF'
=== 交出动作清单（agent 执行）===
1. 勾选 sessions/<端>/PLAN.md 已完成项
2. 向 sessions/<端>/JOURNAL.md 追加一条（只追加，不改历史）
3. 整体重写 sessions/<端>/HANDOFF.md（一页内，含 Do Not Redo / Intentionally Dirty）
4. 更新 sessions/<端>/.session 的 last_epoch（秒）与 last_checkpoint（ISO 时间）← 看板排序靠它
5. 值得跨任务记住的东西 → 候选写入 memory/inbox/（人确认后入 memory/entries/）
6. git add tasks/<线> && git commit -m "waypoint: <一句话摘要>"
7. 释放锁: waypoint.sh unlock --line <线> --sid <端>
EOF
  echo "--- JOURNAL 条目骨架 ---"
  cat <<EOF
## [$(now_iso)] ${me} · 迭代<N>
- 做了什么：
- 改动：<涉及的任务文件 / 关联项目文件>
- 验证：<命令 → 结果>
- 踩坑：
- 下一步：
- 全局库 commit：<提交后的短 hash>
EOF
}

cmd_status_task() {
  [[ -n "$POS1" && -z "$LINE" ]] && LINE="$POS1"
  resolve_ctx 1
  echo "== Waypoint 会话: $LINE/$SID =="
  echo "锁: $(lock_state "$LOCK_FILE")"
  echo "端: $(meta_get "$SESS_DIR/.session" client)   继承自: $(meta_get "$SESS_DIR/.session" parent)   状态: $(meta_get "$SESS_DIR/.session" status)"
  echo "最近交出: $(humanize_age "$(session_epoch "$SESS_DIR")")"
  local f p
  for f in TASK PLAN HANDOFF JOURNAL DECISIONS; do
    p="$SESS_DIR/$f.md"; [[ "$f" == "TASK" ]] && p="$HOME_DIR/tasks/$LINE/TASK.md"
    if [[ -f "$p" ]]; then echo "$f.md: $(wc -l < "$p" | tr -d ' ') 行"; else echo "$f.md: 缺失"; fi
  done
  echo "计划进度: $(plan_counts "$SESS_DIR/PLAN.md")"
  if [[ -f "$HOME_DIR/tasks/$LINE/project.txt" ]]; then
    local p2; p2="$(head -1 "$HOME_DIR/tasks/$LINE/project.txt")"
    if [[ -d "$p2" ]] && is_repo "$p2"; then
      echo "项目锚: $p2  分支 $(safe_git "?" -C "$p2" rev-parse --abbrev-ref HEAD)  HEAD $(safe_git "(无提交)" -C "$p2" log -1 --format='%h %s')"
    else
      echo "项目锚: ${p2}（路径无效，请更新 project.txt）"
    fi
  fi
  echo "-- 全局库最近提交 --"
  git -C "$HOME_DIR" log --oneline -5 2>/dev/null || echo "(尚无提交)"
  echo "-- 全局库工作区 --"
  git -C "$HOME_DIR" status --short
  echo "-- HANDOFF 下一步 --"; echo "  $(handoff_next "$SESS_DIR/HANDOFF.md")"
}

cmd_tasks() {
  require_lib
  local cur=""; [[ -f "$HOME_DIR/CURRENT" ]] && cur="$(cat "$HOME_DIR/CURRENT")"
  echo "== Waypoint 任务库: ${HOME_DIR}（线 / 各端会话）=="
  local found=0 ld line title rows ep full cli plan lock next sid mark
  for ld in "$HOME_DIR"/tasks/*/; do
    [[ -d "$ld" ]] || continue; found=1
    line="$(basename "$ld")"
    title="$(head -1 "$ld/TASK.md" 2>/dev/null | sed 's/^# *//')"
    if [[ -z "$title" || "$title" == *\<* ]]; then title="(未立项)"; fi
    echo "* $line — $title"
    rows="$(candidate_rows)"
    while IFS="$(printf '\t')" read -r ep full cli plan lock next; do
      [[ -n "$full" ]] || continue
      [[ "${full%%/*}" == "$line" ]] || continue
      mark=""; [[ "$full" == "$cur" ]] && mark="→"
      local locktag=""; [[ "$lock" == alive:* ]] && locktag=" 🔒${lock#alive:}"
      sid="${full#*/}"
      printf '   %s %-16s 计划=%-6s 最近=%-10s%s\n' "$mark" "$sid" "$plan" "$(humanize_age "$ep")" "$locktag"
    done <<EOF
$rows
EOF
  done
  if [[ $found -eq 0 ]]; then echo "(空。用 new <任务线> --client <端> 立第一个任务)"; fi
  local arch; arch="$(ls "$HOME_DIR/archive" 2>/dev/null | grep -c . || true)"
  if [[ "$arch" != "0" ]]; then echo "  归档: $arch 条（archive/）"; fi
  return 0
}

cmd_switch() {
  require_lib
  [[ -n "$POS1" ]] || die "用法: waypoint.sh switch <任务线> [会话]"
  LINE="$(slug "$POS1")"; SID="${POS2:-}"
  [[ -d "$HOME_DIR/tasks/$LINE" ]] || die "任务线不存在: $LINE"
  [[ -z "$SID" ]] && SID="$(latest_session_of "$LINE")"
  [[ -n "$SID" ]] || die "任务线 $LINE 无会话"
  resolve_ctx 1
  set_current "$LINE" "$SID"
  git -C "$HOME_DIR" add CURRENT 2>/dev/null || true
  git -C "$HOME_DIR" commit -q -m "waypoint: 切换 → $LINE/$SID" 2>/dev/null || true
  echo "当前会话 → $LINE/$SID"
}

# ---------- 功能 1：各端任务看板 ----------

cmd_board() {
  require_lib
  local rows; rows="$(candidate_rows)"
  local now; now="$(now_epoch)"
  local ep full cli plan lock next line sid title parent journal sdir proj
  local cur=""; [[ -f "$HOME_DIR/CURRENT" ]] && cur="$(cat "$HOME_DIR/CURRENT")"
  if [[ $BOARD_JSON -eq 1 ]]; then
    printf '{"generated_at":"%s","home":"%s","stale_days":%s,"sessions":[' \
      "$(now_iso)" "$(json_escape "$HOME_DIR")" "$STALE_DAYS"
    local first=1
    while IFS="$(printf '\t')" read -r ep full cli plan lock next; do
      [[ -n "$full" ]] || continue
      line="${full%%/*}"; sid="${full#*/}"
      title="$(head -1 "$HOME_DIR/tasks/$line/TASK.md" 2>/dev/null | sed 's/^#* *//')"
      sess_dir_of "$line" "$sid"; sdir="$SESS_DIR"
      parent="$(meta_get "$sdir/.session" parent)"; [[ "$parent" == "-" ]] && parent=""
      journal="$(count_of '^## ' "$sdir/JOURNAL.md")"
      proj="$(head -1 "$HOME_DIR/tasks/$line/project.txt" 2>/dev/null || true)"
      if [[ $first -eq 0 ]]; then printf ','; fi
      first=0
      printf '{"line":"%s","sid":"%s","title":"%s","client":"%s","plan":"%s","last_epoch":%s,"last_age":"%s","lock":"%s","stale":%s,"next":"%s","parent":"%s","journal":%s,"dir":"%s","project":"%s","cur":%s}' \
        "$(json_escape "$line")" "$(json_escape "$sid")" "$(json_escape "$title")" \
        "$(json_escape "${cli:-未知}")" "$(json_escape "$plan")" "$ep" \
        "$(humanize_age "$ep")" "$(json_escape "$lock")" \
        "$(( now - ep > STALE_DAYS * 86400 ? 1 : 0 ))" "$(json_escape "$next")" \
        "$(json_escape "$parent")" "${journal:-0}" "$(json_escape "$sdir")" "$(json_escape "$proj")" \
        "$([[ "$full" == "$cur" ]] && echo 1 || echo 0)"
    done <<EOF
$rows
EOF
    printf '],"repos":['
    first=1
    if [[ -s "$HOME_DIR/repos.txt" ]]; then
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        if [[ $first -eq 0 ]]; then printf ','; fi
        first=0
        printf '{"path":"%s","installed":%s,"client":"%s","plan":"%s","last_age":"%s","worktree":"%s","next":"%s","title":"%s","branch":"%s"}' \
          "$(json_escape "$r")" "$([[ -d "$r/.waypoint" ]] && echo 1 || echo 0)" \
          "$(json_escape "$(handoff_client "$r/.waypoint/HANDOFF.md")")" \
          "$(json_escape "$(plan_counts "$r/.waypoint/PLAN.md")")" \
          "$(json_escape "$(humanize_age "$(mtime_of "$r/.waypoint/HANDOFF.md")")")" \
          "$([[ -n "$(git -C "$r" status --porcelain 2>/dev/null)" ]] && echo dirty || echo clean)" \
          "$(json_escape "$(handoff_next "$r/.waypoint/HANDOFF.md")")" \
          "$(json_escape "$(head -1 "$r/.waypoint/TASK.md" 2>/dev/null | sed 's/^#* *//')")" \
          "$(json_escape "$(git -C "$r" rev-parse --abbrev-ref HEAD 2>/dev/null || true)")"
      done < "$HOME_DIR/repos.txt"
    fi
    printf ']}'
    printf '\n'
    return 0
  fi

  echo "═══ Waypoint 看板 · $(now_iso) · 库 $HOME_DIR ═══"
  echo
  if [[ -z "$rows" ]]; then
    echo "(全局库还没有任何会话。先: waypoint.sh new <任务线> --client <端>)"
  else
    local cur=""; [[ -f "$HOME_DIR/CURRENT" ]] && cur="$(cat "$HOME_DIR/CURRENT")"
    local line_shown="" tag
    while IFS="$(printf '\t')" read -r ep full cli plan lock next; do
      [[ -n "$full" ]] || continue
      line="${full%%/*}"; sid="${full#*/}"
      if [[ "$line" != "$line_shown" ]]; then echo "▸ $line"; line_shown="$line"; fi
      tag=""
      if [[ "$full" == "$cur" ]]; then tag="当前"; fi
      if [[ $(( ep + STALE_DAYS * 86400 )) -lt $now ]]; then tag="$tag 陈旧>${STALE_DAYS}d"; fi
      if [[ "$lock" == alive:* ]]; then tag="$tag 🔒${lock#alive:}"; fi
      printf '   %-12s%-16s 端=%-12s 计划=%-6s 最近=%-9s\n' "$tag" "$sid" "${cli:-?}" "$plan" "$(humanize_age "$ep")"
      if [[ -n "$next" ]]; then printf '        下一步: %s\n' "$next"; fi
    done <<EOF
$rows
EOF
  fi

  # 端视图
  if [[ $BY_CLIENT -eq 1 ]]; then
    echo
    echo "── 按端汇总 ──"
    if [[ -z "$rows" ]]; then echo "   (无)"; else
      printf '%s\n' "$rows" | awk -F'\t' -v now="$now" '
        { c = ($3=="" ? "未知" : $3); n[c]++; if ($1+0 > mx[c]+0) mx[c] = $1; if ($5 ~ /^alive:/) busy[c]++ }
        END { for (k in n) { a = now - mx[k]; if (a<3600) s=int(a/60)"分钟前"; else if (a<86400) s=int(a/3600)"小时前"; else s=int(a/86400)"天前";
                printf "   %-14s 会话=%-3s 活跃锁=%-3s 最近活动=%s\n", k, n[k], (busy[k]==""?"0":busy[k]), s } }' | sort
    fi
  fi

  # 项目模式
  if [[ -s "$HOME_DIR/repos.txt" ]]; then
    echo
    echo "── 项目模式仓库（repos.txt 登记）──"
    local r nx
    while IFS= read -r r; do
      [[ -n "$r" ]] || continue
      if [[ ! -d "$r/.waypoint" ]]; then printf '   %s  ⚠ 未安装协议或已移除\n' "$r"; continue; fi
      nx="$(handoff_next "$r/.waypoint/HANDOFF.md")"
      printf '   %s\n      端=%s 计划=%s 最近=%s 工作区=%s\n      下一步: %s\n' \
        "$r" "$(handoff_client "$r/.waypoint/HANDOFF.md")" "$(plan_counts "$r/.waypoint/PLAN.md")" \
        "$(humanize_age "$(mtime_of "$r/.waypoint/HANDOFF.md")")" \
        "$([[ -n "$(git -C "$r" status --porcelain 2>/dev/null)" ]] && echo dirty || echo clean)" \
        "${nx:-(未填)}"
    done < "$HOME_DIR/repos.txt"
  fi
  echo
  echo "提示: board --json 供面板/其他端消费；board --by-client 看端视图；接管用 waypoint.sh resume"
  return 0
}

# ---------- 页面看板：board --json → 单文件 HTML ----------

dash_template() {
  local t
  for t in "$KIT_DIR/dashboard/index.html" "$HOME_DIR/dashboard.tpl"; do
    [[ -f "$t" ]] && { printf '%s' "$t"; return 0; }
  done
  return 1
}

cmd_dash() {
  require_lib
  local tpl; tpl="$(dash_template)" || die "找不到看板模板（应为 $KIT_DIR/dashboard/index.html）"

  local json; json="$(BOARD_JSON=1 cmd_board)"
  [[ -n "$json" ]] || die "board --json 没有输出，页面无法生成"

  if [[ $DASH_SERVE -eq 1 ]]; then
    local py="$KIT_DIR/dashboard/serve.py"
    [[ -f "$py" ]] || die "找不到 $py"
    command -v python3 >/dev/null 2>&1 || die "--serve 需要 python3（仅用标准库；不想装就用不带 --serve 的 dash 生成静态页）"
    local extra=""
    [[ $DASH_OPEN -eq 1 ]] && extra="--open"
    echo "端口 ${DASH_PORT}；库: ${HOME_DIR}（页面每 5 秒自动刷新）"
    exec python3 "$py" --waypoint "$0" --home "$HOME_DIR" --template "$tpl" \
      --port "$DASH_PORT" --stale-days "$STALE_DAYS" ${extra:+"$extra"}
  fi

  local out="${DASH_OUT:-$HOME_DIR/dashboard.html}"
  mkdir -p "$(dirname "$out")"
  # 产物落在库里时排除，否则下一次 checkpoint 会因“库不干净”被拒
  case "$out" in
    "$HOME_DIR"/*) ensure_excluded "$HOME_DIR" "${out#"$HOME_DIR"/}" ;;
  esac
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/wpjson.XXXXXX")"
  printf '%s' "$json" > "$tmp"
  awk -v jf="$tmp" '
    BEGIN { json = ""; while ((getline l < jf) > 0) json = json l; tok = "__WAYPOINT_DATA__" }
    {
      out = $0
      while ((i = index(out, tok)) > 0)
        out = substr(out, 1, i - 1) json substr(out, i + length(tok))
      print out
    }
  ' "$tpl" > "$out"
  rm -f "$tmp"

  local n; n="$(printf '%s' "$json" | grep -o '"line":' | wc -l | tr -d ' ' || true)"
  echo "已生成页面看板: ${out}　（${n:-0} 个会话）"
  if [[ $DASH_OPEN -eq 1 ]]; then
    if command -v open >/dev/null 2>&1; then open "$out"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$out"
    else echo "（没找到 open/xdg-open，请手动打开上面的文件）"; fi
  else
    echo "打开方式: open \"${out}\"　或重跑: waypoint.sh dash --open"
  fi
  return 0
}

# ---------- 锁命令 ----------

# 项目模式锁：锁落在 <仓库>/.waypoint/locks/，一个仓库一个执行体
proj_lock() {
  TARGET="$(cd "$TARGET" 2>/dev/null && pwd || true)"
  [[ -n "$TARGET" && -d "$TARGET/.waypoint" ]] || die "项目模式需先 init：未找到 $TARGET/.waypoint"
  require_git "$TARGET"
  ensure_excluded "$TARGET/.waypoint" ".waypoint/locks/"
  PROJ_LOCK="$TARGET/.waypoint/locks/$(norm_sid "${SID:-main}").lock"
}

cmd_lock() {
  [[ -n "$POS1" && -z "$LINE" ]] && LINE="$POS1"
  if [[ -z "$LINE" && -z "$SID" ]]; then     # 项目模式
    proj_lock
    local me; me="$(norm_sid "${CLIENT:-main}")"
    lock_check "$PROJ_LOCK" "$me"
    lock_write "$PROJ_LOCK" "$me" "resume" "$TARGET" "$TTL_MIN" "$(now_iso)" 0
    echo "已取锁（项目模式）: $PROJ_LOCK owner=$me 租约=${TTL_MIN}分钟"
    return 0
  fi
  resolve_ctx 1
  local me; me="$(norm_sid "${CLIENT:-$SID}")"
  lock_check "$LOCK_FILE" "$me"
  lock_write "$LOCK_FILE" "$me" "manual" "$LINE/$SID" "$TTL_MIN" "$(now_iso)" 0
  echo "已取锁: $LINE/$SID owner=$me 租约=${TTL_MIN}分钟 → $LOCK_FILE"
}

cmd_unlock() {
  [[ -n "$POS1" && -z "$LINE" ]] && LINE="$POS1"
  if [[ -z "$LINE" && -z "$SID" ]]; then     # 项目模式
    proj_lock
    if [[ -f "$PROJ_LOCK" ]]; then rm -f "$PROJ_LOCK"; echo "已释放锁: $PROJ_LOCK"; else echo "无锁可释放: $PROJ_LOCK"; fi
    return 0
  fi
  resolve_ctx 1
  if [[ -f "$LOCK_FILE" ]]; then rm -f "$LOCK_FILE"; echo "已释放锁: $LINE/$SID"; else echo "无锁可释放: $LINE/$SID"; fi
}

cmd_who() {
  require_lib
  local any=0 f r
  echo "== 有效租约锁（$HOME_DIR/locks/）=="
  for f in "$HOME_DIR"/locks/*.lock; do
    [[ -f "$f" ]] || continue; any=1
    printf '   %-40s %s\n' "$(basename "$f" .lock)" "$(lock_state "$f")"
  done
  if [[ $any -eq 0 ]]; then echo "   (无)"; fi
  if [[ -f "$HOME_DIR/repos.txt" ]]; then
    while IFS= read -r r; do
      [[ -n "$r" && -d "$r/.waypoint/locks" ]] || continue
      for f in "$r/.waypoint"/locks/*.lock; do
        [[ -f "$f" ]] && printf '   %-40s %s\n' "$r/$(basename "$f" .lock)" "$(lock_state "$f")"
      done
    done < "$HOME_DIR/repos.txt"
  fi
  return 0
}

# ---------- 旧布局迁移 ----------

cmd_migrate() {
  require_lib
  local moved=0
  for ld in "$HOME_DIR"/tasks/*/; do
    [[ -d "$ld" ]] || continue
    local line; line="$(basename "$ld")"
    [[ -f "$ld/HANDOFF.md" ]] || continue
    [[ -d "$ld/sessions/default" ]] && continue
    local sid="default"
    local c; c="$(meta_head_client "$ld/HANDOFF.md")"
    [[ -n "$c" ]] && sid="$(norm_sid "$c")"
    mkdir -p "$ld/sessions/$sid"
    for f in PLAN.md HANDOFF.md JOURNAL.md DECISIONS.md; do
      [[ -f "$ld/$f" ]] && mv "$ld/$f" "$ld/sessions/$sid/$f"
    done
    printf 'line=%s\nsid=%s\nclient=%s\ncreated_at=%s\nparent=-\nstatus=open\nlast_checkpoint=%s\nlast_epoch=%s\nlast_head=-\nlast_project_head=-\n' \
      "$line" "$sid" "${sid}" "$(now_iso)" "$(now_iso)" "$(mtime_of "$ld/sessions/$sid/HANDOFF.md")" > "$ld/sessions/$sid/.session"
    set_current "$line" "$sid"
    echo "已迁移: $line → sessions/${sid}（TASK.md/project.txt 留在线级）"
    moved=1
  done
  if [[ $moved -eq 1 ]]; then
    git -C "$HOME_DIR" add -A 2>/dev/null || true
    git -C "$HOME_DIR" commit -q -m "waypoint: 迁移到会话隔离布局" 2>/dev/null || true
    echo "完成。旧版 .waypoint/LOCK（若有）已由 locks/ 取代，可手工删除。"
  else
    echo "没有需要迁移的旧布局任务线。"
  fi
}

cmd_repos() {
  require_lib
  echo "== 已登记的项目模式仓库 =="
  [[ -f "$HOME_DIR/repos.txt" ]] || { echo "  (repos.txt 不存在或为空)"; return; }
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    [[ -d "$r/.waypoint" ]] && echo "  ✅ $r" || echo "  ⚠ ${r}（.waypoint 不存在）"
  done < "$HOME_DIR/repos.txt"
}

# ---------- 分发 ----------

case "$CMD" in
  init) cmd_init ;;
  init-home) cmd_init_home ;;
  new) cmd_new ;;
  resume) cmd_resume ;;
  board) cmd_board ;;
  dash) cmd_dash ;;
  tasks) cmd_tasks ;;
  switch) cmd_switch ;;
  lock) cmd_lock ;;
  unlock) cmd_unlock ;;
  who) cmd_who ;;
  migrate) cmd_migrate ;;
  repos) cmd_repos ;;
  # checkpoint / status：给了线或会话参数 → 全局会话模式；否则 → 项目模式
  checkpoint)
    if [[ -n "$LINE" || -n "$SID" || -n "$POS1" ]]; then cmd_checkpoint_task; else cmd_checkpoint; fi ;;
  status)
    if [[ -n "$LINE" || -n "$SID" || -n "$POS1" ]]; then cmd_status_task; else cmd_status; fi ;;
  -h|--help|help|"") usage ;;
  *) echo "未知子命令: $CMD" >&2; usage; exit 1 ;;
esac
exit 0
