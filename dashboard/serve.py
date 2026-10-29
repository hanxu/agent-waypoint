#!/usr/bin/env python3
"""waypoint dash --serve 的极简本地服务（只用标准库，无第三方依赖）。

  GET /           现渲染页面：每次请求都重新跑 `waypoint board --json`
  GET /api/board  直接返回 board --json 的原始结果

只监听 127.0.0.1，不做鉴权；数据全部来自本机任务库。
"""

import argparse
import http.server
import json
import os
import subprocess
import sys

PLACEHOLDER = "__WAYPOINT_DATA__"
LIVE_OFF = "window.WAYPOINT_LIVE = false;/*live*/"
LIVE_ON = "window.WAYPOINT_LIVE = true;"


def board_json(args):
    cmd = ["bash", args.waypoint, "--home", args.home]
    if args.stale_days:
        cmd += ["--stale-days", args.stale_days]
    cmd += ["board", "--json"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout.strip()
        json.loads(out)  # 校验；坏了就落回空数据
        return out
    except Exception as exc:  # noqa: BLE001 - 出错时页面也要能打开
        return json.dumps({
            "sessions": [], "repos": [], "home": args.home,
            "generated_at": "", "stale_days": 0, "error": str(exc),
        }, ensure_ascii=False)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "waypoint-dash"

    def _send(self, code, ctype, body):
        raw = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/board":
            self._send(200, "application/json", board_json(self.server.args))
            return
        if path in ("/", "/index.html"):
            try:
                with open(self.server.args.template, encoding="utf-8") as fh:
                    html = fh.read()
            except OSError as exc:
                self._send(500, "text/plain", "读不到模板: %s" % exc)
                return
            html = html.replace(PLACEHOLDER, board_json(self.server.args)).replace(LIVE_OFF, LIVE_ON)
            self._send(200, "text/html", html)
            return
        self._send(404, "text/plain", "not found")

    def log_message(self, fmt, *a):  # 只在出错时说话，别刷屏
        if str(a[1] if len(a) > 1 else "")[:1] in ("4", "5"):
            sys.stderr.write("dash: " + (fmt % a) + "\n")


def main():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--waypoint", required=True)
    p.add_argument("--home", required=True)
    p.add_argument("--template", required=True)
    p.add_argument("--port", default="8787")
    p.add_argument("--stale-days", default="")
    p.add_argument("--open", action="store_true")
    args = p.parse_args()

    class Server(http.server.ThreadingHTTPServer):
        daemon_threads = True

    try:
        httpd = Server(("127.0.0.1", int(args.port)), Handler)
    except OSError as exc:
        sys.stderr.write("dash: 端口 %s 起不来（%s）。换一个：--port 8788\n" % (args.port, exc))
        return 1
    httpd.args = args
    url = "http://127.0.0.1:%d/" % httpd.server_address[1]
    print("看板已就绪 → %s   （Ctrl+C 停止）" % url, flush=True)
    if args.open:
        opener = "open" if sys.platform == "darwin" else "xdg-open"
        try:
            subprocess.Popen([opener, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:  # noqa: BLE001
            pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止。")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
