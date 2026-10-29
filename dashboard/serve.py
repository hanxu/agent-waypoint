#!/usr/bin/env python3
"""waypoint dash —— 本地看板服务（仅标准库，无第三方依赖）。

  GET /             页面（首屏数据内嵌，随后走 SSE 推送）
  GET /api/board    当前快照 JSON（curl / 其它端消费）
  GET /api/events   SSE 推送：连上先推一次，之后每 5 秒推一次变化
  GET /api/ping     健康检查

设计要点：
- 数据只来自 `waypoint.sh board --json`，服务不另做采集（PROTOCOL §7）
- 采集结果缓存 2 秒：多个浏览器/多个 SSE 连接共享同一次 subprocess
- 只监听 127.0.0.1；端口被占用时自动 +1 试探，实际端口写进 --port-file
"""

import argparse
import json
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PLACEHOLDER = "__WAYPOINT_DATA__"
CACHE_TTL = 2.0
PUSH_INTERVAL = 5.0
PORT_TRIES = 12


class Board:
    """采集 + 缓存 board --json。"""

    def __init__(self, args):
        self.args = args
        self.lock = threading.Lock()
        self.stamp = 0.0
        self.data = "{}"

    def _run(self):
        cmd = ["bash", self.args.waypoint, "--home", self.args.home]
        if self.args.stale_days:
            cmd += ["--stale-days", self.args.stale_days]
        cmd += ["board", "--json"]
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout.strip()
            json.loads(out)
            return out
        except Exception as exc:  # noqa: BLE001 - 服务要活着，错误也渲成页面
            return json.dumps({
                "sessions": [], "repos": [], "home": self.args.home, "generated_at": "",
                "stale_days": 0, "error": str(exc),
            }, ensure_ascii=False)

    def get(self, force=False):
        with self.lock:  # 持锁采集：并发请求排队，后到的直接吃缓存
            if force or time.time() - self.stamp >= CACHE_TTL:
                self.data = self._run()
                self.stamp = time.time()
            return self.data


class Handler(BaseHTTPRequestHandler):
    server_version = "waypoint-dash"
    protocol_version = "HTTP/1.1"

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
        board = self.server.board
        if path == "/api/board":
            self._send(200, "application/json", board.get())
            return
        if path == "/api/ping":
            self._send(200, "application/json",
                       json.dumps({"ok": True, "home": self.server.args.home}, ensure_ascii=False))
            return
        if path == "/api/events":
            self._events(board)
            return
        if path in ("/", "/index.html"):
            try:
                with open(self.server.args.template, encoding="utf-8") as fh:
                    html = fh.read()
            except OSError as exc:
                self._send(500, "text/plain", "读不到页面模板: %s" % exc)
                return
            snap = board.get().replace("<", "\\u003c")
            html = html.replace(PLACEHOLDER, snap)
            self._send(200, "text/html", html)
            return
        self._send(404, "text/plain", "not found")

    def _events(self, board):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        try:
            self.wfile.write(b"retry: 2000\n\n")
            self._push(board.get())
            while True:
                time.sleep(PUSH_INTERVAL)
                self._push(board.get())
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass  # 浏览器关页面：正常收尾

    def _push(self, data):
        self.wfile.write(("data: " + data + "\n\n").encode("utf-8"))

    def log_message(self, fmt, *a):
        if not self.server.args.quiet:
            sys.stderr.write("dash: " + (fmt % a) + "\n")


def bind(host, port):
    last = None
    for p in range(port, port + PORT_TRIES):
        try:
            return ThreadingHTTPServer((host, p), Handler)
        except OSError as exc:
            last = exc
    return last


def main():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--waypoint", required=True)
    p.add_argument("--home", required=True)
    p.add_argument("--template", required=True)
    p.add_argument("--port", default="8787")
    p.add_argument("--stale-days", default="")
    p.add_argument("--port-file", default="")
    p.add_argument("--open", action="store_true")
    p.add_argument("--quiet", action="store_true")
    args = p.parse_args()

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    try:
        httpd = bind("127.0.0.1", int(args.port))
    except ValueError:
        sys.stderr.write("dash: 端口不是数字: %s\n" % args.port)
        return 1
    if isinstance(httpd, Exception) or httpd is None:
        sys.stderr.write("dash: %s 起不来（%s）。换一个: --port 8790\n" % (args.port, httpd))
        return 1

    httpd.board = Board(args)
    httpd.args = args
    port = httpd.server_address[1]
    url = "http://127.0.0.1:%d/" % port
    if args.port_file:
        with open(args.port_file, "w", encoding="utf-8") as fh:
            fh.write("%d %d\n" % (os.getpid(), port))
    print("看板服务已启动 → %s   （库 %s，Ctrl+C 停止）" % (url, args.home), flush=True)
    if args.open:
        opener = "open" if sys.platform == "darwin" else "xdg-open"
        try:
            subprocess.Popen([opener, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:  # noqa: BLE001
            pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n看板服务已停止。")
    finally:
        httpd.server_close()
        if args.port_file and os.path.exists(args.port_file):
            try:
                os.unlink(args.port_file)
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
