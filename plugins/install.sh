#!/usr/bin/env bash
# install.sh — 安装 Waypoint 自动落盘 hook 到 Qoder（无 LLM 依赖）
#
# 做四件事：
#   1) 准备收件箱目录（项目模式 .waypoint/inbox，或全局库 ~/.waypoint/inbox）
#   2) 把收件箱登记进 .git/info/exclude（不污染用户仓库的 git status）
#   3) 写 ~/.waypoint-hook.conf（hook 的 cwd/HOME 不可靠，落绝对路径）
#   4) 安装插件本体：默认只打印准备内容与手动安装指引；--apply 才写 Qoder 插件目录
#
# 用法:
#   install.sh [--target <项目或库路径>] [--name waypoint] [--apply] [--force] [--dry-run]
#
# --apply 的写法是"本机插件缓存 + 注册表条目"，属于对未公开约定的 best-effort 安装，
# 执行体每次事件重新执行，改完重装即生效；hooks.json 的事件列表在新会话开始时加载。
# 若你的 Qoder 提供正式插件安装入口，请优先用官方入口。
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_DIR="$(cd "$SELF_DIR/.." && pwd)"          # agent-waypoint 仓库根（scripts/ 与 templates/ 在这里）
PLUGIN_SRC="$SELF_DIR/waypoint-qoder-hook"

TARGET="$PWD"
NAME="waypoint"
APPLY=0
FORCE=0
QODER_HOME="${QODER_HOME:-$HOME/.qoder-cn}"
VER="$(sed -n 's/.*"version": "\(.*\)".*/\1/p' "$PLUGIN_SRC/.qoder-plugin/plugin.json" | head -1)"
VER="${VER:-0.1.0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --qoder-home) QODER_HOME="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ✅ %s\n' "$*"; }
no() { printf '  ⚠️ %s\n' "$*"; }

[[ -d "$PLUGIN_SRC" ]] || die "找不到插件源目录: $PLUGIN_SRC"
[[ -d "$TARGET" ]] || die "目标路径不存在: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"

# ---------- 1. 收件箱定位 ----------
INBOX=""
INBOX_KIND=""
if [[ -d "$TARGET/.waypoint" ]]; then
  INBOX="$TARGET/.waypoint/inbox"; INBOX_KIND="project"
elif [[ -d "${WAYPOINT_HOME:-$HOME/.waypoint}" ]]; then
  INBOX="${WAYPOINT_HOME:-$HOME/.waypoint}/inbox"; INBOX_KIND="home"
else
  INBOX="$HOME/.waypoint-hook-fallback/inbox"; INBOX_KIND="fallback"
fi

say "== Waypoint 自动落盘 hook 安装 =="
say "插件源: $PLUGIN_SRC (v$VER)"
say "目标:   $TARGET"
say "收件箱: ${INBOX}（模式 ${INBOX_KIND}）"
say ""

# ---------- 2. 落盘前的准备 ----------
DEST="$QODER_HOME/plugins/cache/qoder-local/$NAME/$VER"
KEY="$NAME@qoder-local"

if [[ $APPLY -eq 0 ]]; then
  say "-- 演练模式（未写任何文件；加 --apply 才真装）--"
  say "将执行："
  say "  a) mkdir -p $INBOX"
  say "  b) 把收件箱登记进对应仓库的 .git/info/exclude（不动用户 .gitignore）"
  say "  c) 写 $HOME/.waypoint-hook.conf（绝对路径：WAYPOINT_HOME / 兜底收件箱）"
  say "  d) 拷插件到 ${DEST}，并注册 ${KEY}（写前自动备份 JSON）"
  say ""
  say "手动安装路径（不想改注册表时走官方入口）："
  say "  用 Qoder 的 create-plugin / 插件安装入口，指向源目录：$PLUGIN_SRC"
else
  say "-- 应用模式 --"
fi

# ---------- 3. 实际写入 ----------
ensure_line() {  # $1=file $2=line
  local f="$1" l="$2"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  [[ -f "$f" ]] || : > "$f"
  grep -qxF "$l" "$f" 2>/dev/null || printf '%s\n' "$l" >> "$f"
}

if [[ $APPLY -eq 1 ]]; then
  mkdir -p "$INBOX" || die "无法创建收件箱: $INBOX"
  chmod +x "$PLUGIN_SRC/bin/waypoint-hook" 2>/dev/null || true
  ok "收件箱就绪: $INBOX"

  if [[ "$INBOX_KIND" == "project" ]]; then
    if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      root="$(git -C "$TARGET" rev-parse --show-toplevel)"
      if [[ -d "$root/.git" ]]; then
        ensure_line "$root/.git/info/exclude" ".waypoint/inbox/"
        ok "已排除出版本跟踪（$root/.git/info/exclude，不动用户 .gitignore）"
      else
        no "worktree/子模块：请手工把 .waypoint/inbox/ 加进 .gitignore"
      fi
    fi
  elif [[ "$INBOX_KIND" == "home" ]]; then
    lib="${WAYPOINT_HOME:-$HOME/.waypoint}"
    if git -C "$lib" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -d "$lib/.git" ]]; then
      ensure_line "$lib/.git/info/exclude" "inbox/"
      ok "任务库收件箱已排除（收件箱是机器本地原料，不入库；归摞后的 JOURNAL 才入库）"
    fi
  fi

  # 不写 WAYPOINT_INBOX：让 hook 自己识别当前项目（项目模式优先），只有库路径与兜底位写死
  cat > "$HOME/.waypoint-hook.conf" <<EOF
# Waypoint hook 定位（由 install.sh 生成；hook 的 cwd/HOME 不可靠，故写绝对路径）
WAYPOINT_HOME="${WAYPOINT_HOME:-$HOME/.waypoint}"
WAYPOINT_FALLBACK_INBOX="$HOME/.waypoint-hook-fallback/inbox"
WAYPOINT_KIT="$KIT_DIR"
# 安装时的默认项目（capture 命令的 --target 缺省参考）
WAYPOINT_INSTALL_TARGET="$TARGET"
EOF
  ok "已写 $HOME/.waypoint-hook.conf"
fi

# ---------- 4. 插件安装 ----------
install_plugin() {
  [[ -d "$QODER_HOME" ]] || { no "没找到 Qoder 用户目录 ${QODER_HOME}（可用 --qoder-home 指定）"; return 1; }
  if [[ -d "$DEST" && $FORCE -eq 0 ]]; then
    say "插件目录已存在，跳过（要覆盖加 --force）：$DEST"
    return 0
  fi
  mkdir -p "$DEST" || { no "无法写 $DEST"; return 1; }
  # 只覆盖内容、保留父目录结构，方便 version 目录被插件缓存的既有约定识别
  ( cd "$PLUGIN_SRC" && tar cf - .qoder-plugin hooks bin ) | ( cd "$DEST" && tar xf - ) || { no "复制失败"; return 1; }
  chmod +x "$DEST/bin/waypoint-hook" 2>/dev/null || true
  ok "插件文件就位: $DEST"

  local reg="$QODER_HOME/plugins/installed_plugins_v2.json"
  if [[ -f "$reg" ]] && command -v python3 >/dev/null 2>&1; then
    cp "$reg" "$reg.bak.$(date +%s)" 2>/dev/null || true
    python3 - "$reg" "$KEY" "$NAME" "$VER" "$DEST" <<'PY' || { no "注册表写入失败（已备份，可手工编辑）"; return 1; }
import json, sys, time, pathlib
reg, key, name, ver, dest = sys.argv[1:6]
p = pathlib.Path(reg)
d = json.loads(p.read_text() or "{}")
d.setdefault("version", 2)
plugins = d.setdefault("plugins", {})
stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
plugins[key] = [{
    "scope": "user",
    "installPath": dest,
    "version": ver,
    "installedAt": stamp,
    "lastUpdated": stamp,
    "displayName": "Waypoint Auto-Capture",
    "enabled": True,
    "source": "local",
}]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
print("  ✅ 注册表已加入 %s" % key)
PY
    local settings="$QODER_HOME/settings.json"
    if [[ -f "$settings" ]] && grep -q '"enabledPlugins"' "$settings"; then
      cp "$settings" "$settings.bak.$(date +%s)" 2>/dev/null || true
      python3 - "$settings" "$KEY" <<'PY' || no "settings.json 启用位写入失败（可手工加 enabledPlugins）"
import json, sys, pathlib
reg, key = sys.argv[1:3]
p = pathlib.Path(reg)
d = json.loads(p.read_text() or "{}")
d.setdefault("enabledPlugins", {})[key] = True
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
print("  ✅ settings.json 已启用 %s" % key)
PY
    fi
  else
    no "未找到注册表或 python3，请手工安装插件"
  fi
  return 0
}

if [[ $APPLY -eq 1 ]]; then
  install_plugin
fi

# ---------- 5. 落盘格式自测（不依赖 Qoder：直接喂假 stdin 看记录行长什么样）----------
say ""
say "== 落盘格式自测 =="
HOOK_BIN="$PLUGIN_SRC/bin/waypoint-hook"
[[ $APPLY -eq 1 && -x "$DEST/bin/waypoint-hook" ]] && HOOK_BIN="$DEST/bin/waypoint-hook"
TEST_REPO="$(mktemp -d)"
git -C "$TEST_REPO" init -q 2>/dev/null || true
git -C "$TEST_REPO" commit -q --allow-empty -m "自测提交：这条应出现在 commits.log" 2>/dev/null || true
# 收件箱放在 <repo>/.waypoint/inbox：hook 由它上溯两级算出仓库根，才能拿到 git 事实
TMPINBOX="$TEST_REPO/.waypoint/inbox"
mkdir -p "$TMPINBOX"
printf '%s\n' '{"hookEventName":"UserPromptSubmit","prompt":"自测：这条应该出现在 prompts.log"}' \
  | ( cd "$TEST_REPO" && WAYPOINT_INBOX="$TMPINBOX" WAYPOINT_INBOX_MODE=project "$HOOK_BIN" prompt ) 2>/dev/null || true
printf '%s\n' '{"hookEventName":"SessionStart","session_id":"selftest"}' \
  | ( cd "$TEST_REPO" && WAYPOINT_INBOX="$TMPINBOX" WAYPOINT_INBOX_MODE=project "$HOOK_BIN" probe ) 2>/dev/null || true
# agent 回答那一半：Stop 自带 last_assistant_message，正文应落成 .md
# （JSON 这里是 printf 的 %s 参数，所以用单反斜杠 \n：单引号保留它，由 json 解成换行）
printf '%s\n' '{"hookEventName":"Stop","session_id":"selftest","cwd":"'"$TEST_REPO"'","transcript_path":"/dev/null","last_assistant_message":"自测回答第一段\n第二段"}' \
  | ( cd "$TEST_REPO" && WAYPOINT_INBOX="$TMPINBOX" WAYPOINT_INBOX_MODE=project "$HOOK_BIN" stop ) 2>/dev/null || true
# 必须再跑一遍自动探测路径（不给 WAYPOINT_INBOX）：宿主真的就是这么调的，
# 只测显式分支会把路由 bug 掩盖掉（曾发生过：装完当场报 INBOX_DIR 未赋值）
printf '%s\n' '{"hookEventName":"UserPromptSubmit","prompt":"自测：自动探测路由","cwd":"'"$TEST_REPO"'"}' \
  | ( cd / && "$HOOK_BIN" prompt ) 2>/dev/null || true
sleep 1
say "  执行体: $HOOK_BIN"
say "  prompts.log   → $(cat "$TMPINBOX/prompts.log" 2>/dev/null || echo '(空)')"
say "  answers.log   → $(cat "$TMPINBOX/answers.log" 2>/dev/null || echo '(空)')"
say "  回答正文      → $(ls "$TMPINBOX/answers/" 2>/dev/null | tr '\n' ' ' || echo '(无)')"
say "  sessions.log  → $(cat "$TMPINBOX/sessions.log" 2>/dev/null | tail -1 || echo '(空)')"
say "  commits.log   → $(cat "$TMPINBOX/commits.log" 2>/dev/null || echo '(空：首次运行只写基线)')"
say "  snapshots.log → $(cat "$TMPINBOX/snapshots.log" 2>/dev/null | tail -1 || echo '(空)')"
say "  hook-probe.log→ $(cat "$TMPINBOX/hook-probe.log" 2>/dev/null | tail -1 || echo '(空)')"
# 自动探测没落盘时直接说，不要让人去翻文件才知道挂了
if grep -q '自测：自动探测路由' "$TMPINBOX/prompts.log" 2>/dev/null; then
  say "  自动探测路由 → OK（靠 payload 的 cwd 定位，与宿主真实调用一致）"
else
  no  "  自动探测路由 → 失败（收件箱不会落在预期位置，先查 resolve_inbox 与 repos.txt）"
fi
rm -rf "$TMPINBOX" "$TEST_REPO"

cat <<EOF

== 下一步 ==
1. hook 脚本本身是每次事件重新执行的，换文件即生效；hooks.json 在会话开始时加载，
   改事件列表/args 后要开个新会话（实测：同一 IDE 里新开会话就会热加载，不必重启）
2. 在 Qoder 里发一句话，再看数据（prompts=你要什么，answers=agent 怎么答）：
     bash $KIT_DIR/scripts/waypoint.sh capture show --target $TARGET
3. 确认哪些事件真的被回调（看快照行末的 payload 事件名）：
     tail -5 $INBOX/snapshots.log
     grep -o '"hook_event_name":"[A-Za-z]*"' $INBOX/hook-probe.log | sort | uniq -c
4. 数据看过几轮后，再决定归摞与定格策略（--full 会把回答正文一起写进 JOURNAL）：
     bash $KIT_DIR/scripts/waypoint.sh capture drain --target $TARGET
     bash $KIT_DIR/scripts/waypoint.sh capture drain --target $TARGET --full --commit
5. （可选）开启 SessionStart 提醒注入：在插件的 hooks/hooks.json 里
   给 SessionStart 的同步条目加 env："env": {"WAYPOINT_HOOK_INJECT": "1"}
   默认不开：本版只采集原料，不改变 agent 的行为

== 卸载 ==
  rm -rf "$DEST"                       # 插件文件
  编辑 installed_plugins_v2.json 删掉 "$KEY"（备份文件在同目录）
  rm -f "$HOME/.waypoint-hook.conf"
  收件箱里的日志随时可删：rm -f $INBOX/*.log
EOF
