#!/usr/bin/env bash
# waypoint.sh — Waypoint 协议辅助工具（无依赖，bash 3.2+ / macOS 兼容）
#
# 项目模式（状态装在项目内 .waypoint/，与代码原子提交）:
#   waypoint.sh init [--target <项目路径>]                       安装协议到目标项目
#   waypoint.sh checkpoint [--target <项目路径>] [--allow-dirty] 抓取 git 事实，预填交接模板
#   waypoint.sh status [--target <项目路径>]                     打印任务状态摘要
#
# 全局模式（全机一份任务库，不绑定项目，默认 ~/.waypoint）:
#   waypoint.sh init-home [--home <目录>]                        初始化全局任务库（git 仓库）
#   waypoint.sh new <任务短名> [--home D] [--project <路径>]     新建任务并设为当前（--project 可选锚定）
#   waypoint.sh tasks [--home D]                                 列出所有任务（标当前）
#   waypoint.sh switch <任务短名> [--home D]                     切换当前任务
#   waypoint.sh status --task [任务短名] [--home D]              任务状态摘要（默认当前任务）
#   waypoint.sh checkpoint --task [任务短名] [--home D] [--allow-dirty]
#
# 环境变量: WAYPOINT_HOME 覆盖全局库默认路径（--home 优先级更高）
set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="."
ALLOW_DIRTY=0
HOME_DIR="${WAYPOINT_HOME:-$HOME/.waypoint}"
TASK_NAME=""
CMD="${1:-help}"
shift || true
POS_NAME=""

while [[ $# -gt 0 ]]; do
  # new/switch 的第一个非 flag 参数是任务短名（位置参数）
  if [[ "$CMD" == "new" || "$CMD" == "switch" ]] && [[ "$1" != --* ]] && [[ -z "$POS_NAME" ]]; then
    POS_NAME="$1"; shift; continue
  fi
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --home) HOME_DIR="$2"; shift 2 ;;
    --project) PROJ_PATH="$2"; shift 2 ;;
    --task)
      # --task 可带值（下一个参数不以 -- 开头时消费它），不带值则用 CURRENT
      TASK_NAME="__CURRENT__"
      if [[ $# -ge 2 && "$2" != --* ]]; then TASK_NAME="$2"; shift; fi
      shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

die() { echo "错误: $*" >&2; exit 1; }
usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

require_git() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "$1 不是 git 仓库，先 git init"; }

# 任务短名 → 目录名：空格换 -，去首尾 -，禁止路径分隔符
slug() { echo "$1" | tr ' /' '--' | sed 's/^-*//;s/-*$//' | grep -v '^$' \
  || die "任务短名不能为空"; }

resolve_task_dir() {  # 依赖 HOME_DIR 与 TASK_NAME
  [[ -d "$HOME_DIR/tasks" ]] || die "全局库未初始化，先运行: $0 init-home --home $HOME_DIR"
  if [[ "$TASK_NAME" == "__CURRENT__" || -z "$TASK_NAME" ]]; then
    [[ -f "$HOME_DIR/CURRENT" ]] || die "无当前任务（CURRENT 缺失）。用: $0 new <任务短名> 或 switch <任务短名>"
    TASK_NAME="$(cat "$HOME_DIR/CURRENT")"
  fi
  TASK_DIR="$HOME_DIR/tasks/$TASK_NAME"
  [[ -d "$TASK_DIR" ]] || die "任务不存在: ${TASK_NAME}（现有: $0 tasks 查看）"
}

# 打印任务关联项目的 git 锚定信息（若有）
project_anchor() {
  local p="$1"
  [[ -f "$p/project.txt" ]] || { echo "关联项目: 无"; return; }
  local path; path="$(head -1 "$p/project.txt")"
  if [[ -d "$path" && $(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null) == "true" ]]; then
    echo "关联项目: $path"
    echo "  分支: $(git -C "$path" rev-parse --abbrev-ref HEAD)"
    echo "  HEAD:  $(git -C "$path" log -1 --format='%h %s' 2>/dev/null || '(无提交)')"
    local dirty; dirty="$(git -C "$path" status --porcelain)"
    if [[ -n "$dirty" ]]; then
      echo "  工作区: dirty（项目侧改动由你在项目仓库正常提交）"; echo "$dirty" | sed 's/^/    /'
    else
      echo "  工作区: clean"
    fi
  else
    echo "关联项目: ${path}（路径无效或非 git 仓库，请更新 project.txt）"
  fi
}

# ---------- 项目模式 ----------

cmd_init() {
  TARGET="$(cd "$TARGET" && pwd)"
  require_git "$TARGET"
  local WP="$TARGET/.waypoint"
  if [[ -d "$WP" ]]; then
    die "$WP 已存在。如需重装请先手工处理（协议文件可能含任务状态，勿随意删除）"
  fi
  mkdir -p "$WP/archive"
  for f in PROTOCOL.md TASK.md PLAN.md HANDOFF.md JOURNAL.md DECISIONS.md; do
    cp "$KIT_DIR/templates/$f" "$WP/$f"
  done
  echo "已创建 $WP/{PROTOCOL,TASK,PLAN,HANDOFF,JOURNAL,DECISIONS}.md 与 archive/"

  if [[ ! -f "$TARGET/AGENTS.md" ]]; then
    cp "$KIT_DIR/templates/AGENTS.md" "$TARGET/AGENTS.md"
    echo "已安装 AGENTS.md"
  else
    echo "提示: 项目已有 AGENTS.md，未覆盖。请手工合并指针段落（见 INSTALL_FOR_AGENTS.md §2）"
  fi
  echo "完成。下一步: 填写 .waypoint/TASK.md 与 PLAN.md 立项。"
}

cmd_checkpoint() {
  TARGET="$(cd "$TARGET" && pwd)"
  require_git "$TARGET"
  local WP="$TARGET/.waypoint"
  [[ -d "$WP" ]] || die "未安装协议，先运行: $0 init --target $TARGET"

  local dirty; dirty="$(git -C "$TARGET" status --porcelain)"
  if [[ -n "$dirty" && $ALLOW_DIRTY -eq 0 ]]; then
    echo "$dirty"
    die "工作区不干净。先 commit，或确认故意不提交后加 --allow-dirty（并在交接快照 Intentionally Dirty 中逐个列出）"
  fi

  echo "=== 交接事实（项目模式，由 waypoint.sh 抓取，agent 补齐叙事后整体重写 .waypoint/HANDOFF.md）==="
  echo
  echo "时间: $(date +%Y-%m-%dT%H:%M:%S%z)   ← 时间戳以此为准，勿自行编造"
  echo "客户端: \${当前客户端名}"
  echo "分支: $(git -C "$TARGET" rev-parse --abbrev-ref HEAD)"
  echo "HEAD: $(git -C "$TARGET" log -1 --format='%h %s')"
  echo
  echo "最近 10 次提交:"
  git -C "$TARGET" log --oneline -10
  echo
  echo "最近一次改动概览:"
  git -C "$TARGET" diff HEAD~1 --stat 2>/dev/null || echo "(首次提交，无 diff)"
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
  TARGET="$(cd "$TARGET" && pwd)"
  require_git "$TARGET"
  local WP="$TARGET/.waypoint"
  if [[ ! -d "$WP" ]]; then
    echo "未安装协议（$WP 不存在）"
    exit 0
  fi
  echo "== Waypoint 状态（项目模式: ${TARGET}）=="
  if [[ -f "$WP/LOCK" ]]; then echo "锁: $(cat "$WP/LOCK")"; else echo "锁: 无"; fi
  for f in TASK PLAN HANDOFF JOURNAL DECISIONS; do
    [[ -f "$WP/$f.md" ]] && echo "$f.md: $(wc -l < "$WP/$f.md" | tr -d ' ') 行" || echo "$f.md: 缺失"
  done
  echo "-- 最近提交 --"
  git -C "$TARGET" log --oneline -5 2>/dev/null || echo "(尚无提交)"
  echo "-- 工作区 --"
  git -C "$TARGET" status --short --branch
  if [[ -f "$WP/HANDOFF.md" ]]; then echo "-- HANDOFF 下一步 --"; sed -n '/## 下一步/,/^## /p' "$WP/HANDOFF.md" | head -6; fi
}

# ---------- 全局模式 ----------

cmd_init_home() {
  if [[ -d "$HOME_DIR" ]]; then HOME_DIR="$(cd "$HOME_DIR" && pwd)";
  else mkdir -p "$HOME_DIR"; HOME_DIR="$(cd "$HOME_DIR" && pwd)"; fi
  [[ -d "$HOME_DIR/tasks" ]] && die "$HOME_DIR 已是全局库（tasks/ 存在）。如需重建请先手工备份删除"
  mkdir -p "$HOME_DIR/tasks" "$HOME_DIR/archive"
  cp "$KIT_DIR/templates/PROTOCOL.md" "$HOME_DIR/PROTOCOL.md"

  # 渲染用户级规则注入文本（路径为本库权威记录）
  cat > "$HOME_DIR/RULES_SNIPPET.md" <<EOF
# 本机 Waypoint 全局任务库（把本段贴进客户端的用户级/全局规则）

- 数据目录: ${HOME_DIR}（本行是权威路径记录，勿凭记忆猜）
- 任务状态: $HOME_DIR/tasks/<任务短名>/{TASK,PLAN,HANDOFF,JOURNAL,DECISIONS}.md；当前任务见 $HOME_DIR/CURRENT
- 触发词:
  - 「继续任务」→ 读当前任务的 HANDOFF.md，按协议接管（复述状态后再继续）
  - 「checkpoint」→ 按协议交出: 更新任务文件后在 $HOME_DIR 内 git commit（前缀 waypoint:），删任务目录内 LOCK
  - 「新任务 <短名>」→ 运行 bash $KIT_DIR/scripts/waypoint.sh new <短名>（或按 PROTOCOL.md §9 手工建）
  - 「切换任务 <短名>」→ switch 到指定任务再接管
- 若任务目录有 project.txt: 任务关联该项目仓库，checkpoint 时在 JOURNAL 记录该项目 HEAD
- 完整协议: $HOME_DIR/PROTOCOL.md（冲突时以它为准）
EOF

  git -C "$HOME_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || git -C "$HOME_DIR" init -q
  git -C "$HOME_DIR" add -A
  git -C "$HOME_DIR" commit -q -m "waypoint: init home library" 2>/dev/null \
    || echo "(已有未提交内容，请自行整理提交)"

  echo "全局任务库已建立: $HOME_DIR"
  echo "├── PROTOCOL.md        协议本体（含 §9 全局模式）"
  echo "├── RULES_SNIPPET.md   ⭐ 注入文本——贴进 Qoder 用户级 Rules / Trae user_rules.md"
  echo "├── CURRENT            当前任务指针（new 时生成）"
  echo "├── tasks/             任务目录（每任务一个）"
  echo └── archive/
  echo
  echo "下一步:"
  echo "  1. 把 RULES_SNIPPET.md 的内容贴进各客户端的用户级规则（只需一次）"
  echo "  2. $0 new <任务短名> [--project <关联项目路径>]  立第一个任务"
}

cmd_new() {
  [[ -d "$HOME_DIR/tasks" ]] || die "全局库未初始化，先运行: $0 init-home --home $HOME_DIR"
  [[ -n "${POS_NAME:-}" ]] || die "用法: $0 new <任务短名> [--project <路径>]"
  local name; name="$(slug "$POS_NAME")"
  local dir="$HOME_DIR/tasks/$name"
  [[ -d "$dir" ]] && die "任务已存在: $name"
  mkdir -p "$dir"
  for f in TASK.md PLAN.md HANDOFF.md JOURNAL.md DECISIONS.md; do
    cp "$KIT_DIR/templates/$f" "$dir/$f"
  done
  echo "$name" > "$HOME_DIR/CURRENT"
  if [[ -n "${PROJ_PATH:-}" ]]; then
    PROJ_PATH="$(cd "$PROJ_PATH" 2>/dev/null && pwd)" || die "--project 路径不存在: $PROJ_PATH"
    echo "$PROJ_PATH" > "$dir/project.txt"
    echo "已锚定项目: ${PROJ_PATH}（checkpoint 时会在 JOURNAL 记录该项目 HEAD）"
  fi
  git -C "$HOME_DIR" add CURRENT "tasks/$name"
  git -C "$HOME_DIR" commit -q -m "waypoint: 新任务 $name" 2>/dev/null || true
  echo "已创建任务并设为当前: $name → $dir"
  echo "下一步: 填 $dir/TASK.md（DoD 验收标准）与 PLAN.md，然后对任意客户端说「继续任务」。"
}

cmd_tasks() {
  [[ -d "$HOME_DIR/tasks" ]] || die "全局库未初始化，先运行: $0 init-home"
  local cur=""
  if [[ -f "$HOME_DIR/CURRENT" ]]; then cur="$(cat "$HOME_DIR/CURRENT")"; fi
  echo "== Waypoint 任务库: $HOME_DIR =="
  local found=0 d title
  for d in "$HOME_DIR"/tasks/*/; do
    [[ -d "$d" ]] || continue
    found=1
    local n; n="$(basename "$d")"
    local mark=" "; [[ "$n" == "$cur" ]] && mark="*"
    title="$(head -1 "$d/TASK.md" 2>/dev/null | sed 's/^# *//' || true)"
    if [[ -z "$title" || "$title" == *\<* ]]; then title="(未立项)"; fi
    [[ -f "$d/LOCK" ]] && title="$title [锁定:$(cat "$d/LOCK")]"
    echo "$mark $n — $title"
  done
  if [[ $found -eq 0 ]]; then echo "(空。用 new <任务短名> 立第一个任务)"; fi
  local arch; arch="$(ls "$HOME_DIR/archive" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$arch" != "0" ]]; then echo "  归档: $arch 个（archive/）"; fi
}

cmd_switch() {
  [[ -d "$HOME_DIR/tasks" ]] || die "全局库未初始化，先运行: $0 init-home"
  [[ -n "${POS_NAME:-}" ]] || die "用法: $0 switch <任务短名>"
  local name; name="$(slug "$POS_NAME")"
  [[ -d "$HOME_DIR/tasks/$name" ]] || die "任务不存在: ${name}（$0 tasks 查看）"
  echo "$name" > "$HOME_DIR/CURRENT"
  git -C "$HOME_DIR" add CURRENT
  git -C "$HOME_DIR" commit -q -m "waypoint: 切换当前任务 → $name" 2>/dev/null || true
  echo "当前任务 → $name"
}

cmd_checkpoint_task() {
  resolve_task_dir
  require_git "$HOME_DIR"
  local dirty; dirty="$(git -C "$HOME_DIR" status --porcelain)"
  if [[ -n "$dirty" && $ALLOW_DIRTY -eq 0 ]]; then
    echo "$dirty"
    die "全局库不干净。先 commit 状态文件，或加 --allow-dirty 并在 HANDOFF 的 Intentionally Dirty 中说明"
  fi
  echo "=== 交接事实（全局模式，agent 补齐叙事后整体重写 $TASK_NAME/HANDOFF.md，然后在全局库 commit）==="
  echo
  echo "任务: $TASK_NAME"
  echo "时间: $(date +%Y-%m-%dT%H:%M:%S%z)   ← 时间戳以此为准，勿自行编造"
  echo "客户端: \${当前客户端名}"
  echo "全局库: $HOME_DIR @ $(git -C "$HOME_DIR" log -1 --format='%h %s' 2>/dev/null || '(尚无提交)')"
  project_anchor "$TASK_DIR"
  echo
  echo "最近提交（全局库）:"
  git -C "$HOME_DIR" log --oneline -5 2>/dev/null || echo "(尚无提交)"
  if [[ -n "$dirty" ]]; then echo; echo "故意未提交（写入 Intentionally Dirty）:"; echo "$dirty"; fi
  cat <<EOF

=== JOURNAL 追加条目骨架 ===

## [<上面抓到的时间>] <客户端名> · 迭代<N>
- 做了什么：
- 改动：<涉及的任务文件 / 关联项目文件>
- 验证：<命令 → 结果>
- 踩坑：
- 下一步：
- 全局库 commit：<提交后的短 hash>
- 项目 HEAD：<若任务锚定了 project.txt，记录上面抓到的项目 HEAD；否则删掉本行>
EOF
}

cmd_status_task() {
  resolve_task_dir
  echo "== Waypoint 任务: $TASK_NAME =="
  if [[ -f "$TASK_DIR/LOCK" ]]; then echo "锁: $(cat "$TASK_DIR/LOCK")"; else echo "锁: 无"; fi
  project_anchor "$TASK_DIR"
  for f in TASK PLAN HANDOFF JOURNAL DECISIONS; do
    [[ -f "$TASK_DIR/$f.md" ]] && echo "$f.md: $(wc -l < "$TASK_DIR/$f.md" | tr -d ' ') 行" || echo "$f.md: 缺失"
  done
  echo "-- 全局库最近提交 --"
  git -C "$HOME_DIR" log --oneline -5 2>/dev/null || echo "(尚无提交)"
  echo "-- 全局库工作区 --"
  git -C "$HOME_DIR" status --short
  if [[ -f "$TASK_DIR/HANDOFF.md" ]]; then echo "-- HANDOFF 下一步 --"; sed -n '/## 下一步/,/^## /p' "$TASK_DIR/HANDOFF.md" | head -6; fi
}

# ---------- 分发 ----------

case "$CMD" in
  init) cmd_init ;;
  checkpoint)
    if [[ "$TASK_NAME" != "" ]]; then cmd_checkpoint_task; else cmd_checkpoint; fi ;;
  status)
    if [[ "$TASK_NAME" != "" ]]; then cmd_status_task; else cmd_status; fi ;;
  init-home) cmd_init_home ;;
  new) cmd_new ;;
  tasks) cmd_tasks ;;
  switch) cmd_switch ;;
  -h|--help|help|"") usage ;;
  *) echo "未知子命令: $CMD" >&2; usage; exit 1 ;;
esac
