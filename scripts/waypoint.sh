#!/usr/bin/env bash
# waypoint.sh — Waypoint 协议辅助工具（无依赖，bash 3.2+ / macOS 兼容）
#
# 用法:
#   waypoint.sh init [--target <项目路径>]                 安装协议到目标项目
#   waypoint.sh checkpoint [--target <项目路径>] [--allow-dirty]
#                                                          抓取 git 事实，预填交接模板
#   waypoint.sh status [--target <项目路径>]               打印任务状态摘要
set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="."
ALLOW_DIRTY=0
CMD="${1:-help}"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

TARGET="$(cd "$TARGET" && pwd)"
WP="$TARGET/.waypoint"

die() { echo "错误: $*" >&2; exit 1; }

require_git() { git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "$TARGET 不是 git 仓库，先 git init"; }

# ---------- init ----------
cmd_init() {
  require_git
  if [[ -d "$WP" ]]; then
    die "$WP 已存在。如需重装请先手工处理（协议文件可能含任务状态，勿随意删除）"
  fi
  mkdir -p "$WP/archive"
  for f in PROTOCOL.md TASK.md PLAN.md HANDOFF.md JOURNAL.md DECISIONS.md; do
    cp "$KIT_DIR/templates/$f" "$WP/$f"
  done
  echo "已创建 $WP/{PROTOCOL,TASK,PLAN,HANDOFF,JOURNAL,DECISIONS}.md 与 archive/"

  # 根指令文件：不存在则安装，存在则提示手工合并
  if [[ ! -f "$TARGET/AGENTS.md" ]]; then
    cp "$KIT_DIR/templates/AGENTS.md" "$TARGET/AGENTS.md"
    echo "已安装 AGENTS.md"
  else
    echo "提示: 项目已有 AGENTS.md，未覆盖。请手工合并以下指针段落:"
    cat <<'EOF'
  ## 任务接续协议（Waypoint）
  本项目使用 .waypoint/ 目录管理任务状态，任何 AI 客户端都是无状态执行器。
  - 触发词:「继续任务」→ 接管仪式;「checkpoint」→ 交出仪式
  - 会话开始先读 .waypoint/HANDOFF.md 并复述状态; 绝不从头重做已完成工作
  - 完整协议: .waypoint/PROTOCOL.md
EOF
  fi
  echo "完成。下一步: 填写 .waypoint/TASK.md 与 PLAN.md 立项。"
}

# ---------- checkpoint ----------
cmd_checkpoint() {
  require_git
  [[ -d "$WP" ]] || die "未安装协议，先运行: $0 init --target $TARGET"

  local dirty
  dirty="$(git -C "$TARGET" status --porcelain)"
  if [[ -n "$dirty" && $ALLOW_DIRTY -eq 0 ]]; then
    echo "$dirty"
    die "工作区不干净。先 commit，或确认这些文件属故意不提交后加 --allow-dirty（并在交接快照 Intentionally Dirty 中逐个列出）"
  fi

  local now agent branch head log diffstat
  now="$(date +%Y-%m-%dT%H:%M:%S%z)"
  agent="${WAYPOINT_AGENT:-unknown}"
  branch="$(git -C "$TARGET" rev-parse --abbrev-ref HEAD)"
  head="$(git -C "$TARGET" log -1 --format='%h %s')"
  log="$(git -C "$TARGET" log --oneline -10)"
  diffstat="$(git -C "$TARGET" diff HEAD~1 --stat 2>/dev/null || echo '(首次提交，无 diff)')"

  cat <<EOF
=== 交接事实（由 waypoint.sh 抓取，agent 补齐叙事部分后整体重写 .waypoint/HANDOFF.md）===

时间: $now
客户端: $agent
分支: $branch
HEAD: $head

最近 10 次提交:
$log

最近一次改动概览:
$diffstat

工作区: 干净
EOF
  if [[ -n "$dirty" ]]; then
    echo "故意未提交的文件（需逐个写入 Intentionally Dirty）:"
    echo "$dirty"
  fi

  cat <<'EOF'

=== JOURNAL 追加条目骨架 ===

## [<上面抓到的时间>] <客户端名> · 迭代<N>
- 做了什么：
- 改动：<上面 diffstat 涉及的文件>
- 验证：<命令 → 结果>
- 踩坑：
- 下一步：
- commit：<HEAD 短 hash>
EOF
}

# ---------- status ----------
cmd_status() {
  require_git
  if [[ ! -d "$WP" ]]; then
    echo "未安装协议（$WP 不存在）"
    exit 0
  fi
  echo "== Waypoint 状态 =="
  if [[ -f "$WP/LOCK" ]]; then
    echo "锁: $(cat "$WP/LOCK")"
  else
    echo "锁: 无"
  fi
  for f in TASK PLAN HANDOFF JOURNAL DECISIONS; do
    [[ -f "$WP/$f.md" ]] && echo "$f.md: $(wc -l < "$WP/$f.md" | tr -d ' ') 行" || echo "$f.md: 缺失"
  done
  echo "-- 最近提交 --"
  git -C "$TARGET" log --oneline -5 2>/dev/null || echo "(尚无提交)"
  echo "-- 工作区 --"
  git -C "$TARGET" status --short --branch
  [[ -f "$WP/HANDOFF.md" ]] && { echo "-- HANDOFF 下一步 --"; sed -n '/## 下一步/,/^## /p' "$WP/HANDOFF.md" | head -6; }
}

case "$CMD" in
  init) cmd_init "$@" ;;
  checkpoint) cmd_checkpoint "$@" ;;
  status) cmd_status "$@" ;;
  *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
