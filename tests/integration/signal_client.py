#!/usr/bin/env python3
"""Signal checks against examples/todos over real sockets.

Joins signal:todos like framework/signal/signal.js does, applies the server's
diffs to a copy of the rendered tree, and checks the resulting HTML. The
first check proves the two render paths agree: the plain-HTTP page and the
rendered JSON flatten to the same markup.

    python3 tests/integration/signal_client.py <port>
"""
import json
import os
import re
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chat_client as cc  # noqa: E402
import ws_client as w  # noqa: E402

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8070
w.PORT = PORT
cc.PORT = PORT
PASSED = 0
FAILED = 0


def check(label, ok, detail=""):
    global PASSED, FAILED
    if ok:
        PASSED += 1
        print(f"PASS  {label}")
    else:
        FAILED += 1
        print(f"FAIL  {label} {str(detail)[:300]}")


def html(r):
    """The same flattening signal.js does."""
    if r is None:
        return ""
    if isinstance(r, str):
        return r
    if "d" in r:
        return "".join(weave(r["s"], lambda i, e=e: html(e[i])) for e in r["d"])
    return weave(r["s"], lambda i: html(r.get(str(i))))


def weave(s, dyn):
    out = s[0]
    for i in range(1, len(s)):
        out += dyn(i - 1) + s[i]
    return out


def merge(old, diff):
    for k, v in diff.items():
        cur = old.get(k)
        if isinstance(v, dict) and "s" not in v and isinstance(cur, dict):
            if "d" in v:
                cur["d"] = v["d"]
            else:
                merge(cur, v)
        else:
            old[k] = v


def http_get(path):
    s = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    s.sendall(f"GET {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".encode())
    data = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        data += chunk
    s.close()
    head, _, body = data.partition(b"\r\n\r\n")
    return head.decode(errors="replace"), body.decode(errors="replace")


class Signal:
    def __init__(self, name="todos"):
        self.c = cc.Client.__new__(cc.Client)
        self.c.s = socket.create_connection(("127.0.0.1", PORT), timeout=3)
        _, self.c.head = w.handshake(self.c.s, path="/signal/websocket?vsn=2.0.0")
        self.c.r = w.Reader(self.c.s)
        self.c.ref = 0
        self.c.join_refs = {}
        self.topic = "signal:" + name
        self.pushes = 0
        self.tree = None
        ref = self.c.send(self.topic, "phx_join", {})
        self.join = self.c.reply_to(ref)
        self.tree = self.join[4].get("response", {}).get("rendered")

    def frame(self):
        """Next message; pushed diffs are merged on the way, like signal.js."""
        m = self.c.next(skip_ticks=False)
        if isinstance(m, list) and m[3] == "diff" and m[2] == self.topic:
            self.pushes += 1
            merge(self.tree, m[4]["diff"])
        return m

    def reply_to(self, ref):
        while True:
            m = self.frame()
            if isinstance(m, list) and m[3] == "phx_reply" and m[1] == ref:
                return m

    def event(self, *msg):
        ref = self.c.send(self.topic, "event", list(msg))
        reply = self.reply_to(ref)[4]
        if reply["status"] == "ok" and reply["response"].get("diff"):
            merge(self.tree, reply["response"]["diff"])
        return reply

    def wait_for(self, text, seconds):
        """Reads pushes until the page contains `text` (or time runs out)."""
        import time
        deadline = time.time() + seconds
        self.c.s.settimeout(0.3)
        try:
            while text not in self.page() and time.time() < deadline:
                try:
                    self.frame()
                except (socket.timeout, TimeoutError):
                    pass
        finally:
            self.c.s.settimeout(3)
        return text in self.page()

    def page(self):
        return html(self.tree)

    def titles(self):
        return re.findall(r'class="check"[^>]*>([^<]*)</button>', self.page())

    def close(self):
        self.c.close()


def main():
    head, body = http_get("/todos")
    check("GET /todos renders on the server", head.startswith("HTTP/1.1 200") and "Write a Signal" in body)
    jhead, js = http_get("/rz/signal.js")
    check("GET /rz/signal.js", jhead.startswith("HTTP/1.1 200") and "text/javascript" in jhead and "phx_join" in js)
    first = re.search(r'<div id="rz-root" data-signal="todos">(.*)</div>\n<script', body, re.S)

    a = Signal()
    check("join replies with a rendered tree", a.join[4]["status"] == "ok" and isinstance(a.tree, dict) and "s" in a.tree, a.join)
    check("rendered JSON == server HTML", first is not None and a.page() == first.group(1), (a.page()[:120], first and first.group(1)[:120]))
    check("initial items", a.titles() == ["Write a Signal", "Ship it"], a.titles())

    r = a.event("Toggle", 1)
    check("Toggle sends a diff", r["status"] == "ok" and r["response"]["diff"], r)
    check("Toggle applied", 'class="todo done"' in a.page() and "1 open" in a.page())
    diff_size = len(json.dumps(r["response"]["diff"]))
    check("the diff is small (no statics resent)", diff_size < 200 and '"s"' not in json.dumps(r["response"]["diff"]), diff_size)

    r = a.event("Toggle", 999)
    check("a no-op message sends an empty diff", r["status"] == "ok" and r["response"]["diff"] == {}, r)

    a.event("Draft", "<script>alert(1)</script> & co")
    r = a.event("Add")
    check("Draft + Add appends an item", a.titles()[-1] == "&lt;script&gt;alert(1)&lt;&#x2F;script&gt; &amp; co", a.titles())
    check("the input is cleared in the tree", 'name="title" value=""' in a.page())

    a.event("ClearDone")
    check("ClearDone", a.titles() == ["Ship it", "&lt;script&gt;alert(1)&lt;&#x2F;script&gt; &amp; co"], a.titles())
    a.event("Remove", 2)
    a.event("Remove", 3)
    check("removing everything switches to the empty branch", "Nothing to do." in a.page() and a.titles() == [], a.page()[:200])
    a.event("Draft", "again")
    a.event("Add")
    check("and back to the list branch", a.titles() == ["again"], a.titles())

    r = a.event("Nope")
    check("unknown message -> error", r["status"] == "error" and r["response"]["reason"] == "bad message", r)
    r = a.event("Toggle", "not a number")
    check("wrong payload type -> error", r["status"] == "error", r)
    ref = a.c.send(a.topic, "event", [5])
    r = a.c.reply_to(ref)[4]
    check("malformed event -> error", r["status"] == "error" and r["response"]["reason"] == "bad event", r)

    b = Signal()
    check("a second session has its own state", b.titles() == ["Write a Signal", "Ship it"] and a.titles() == ["again"], (b.titles(), a.titles()))

    # Pushes: messages published by the server, applied through update().
    check("ticker push reaches a page (Tick via TodosMsg__publish)", b.wait_for("server up 1s", 2.5) or b.wait_for("server up 2s", 1.5), b.pushes)
    r = a.event("Nudge")
    check("Nudge replies with no diff (delivery is a push)", r["status"] == "ok" and r["response"]["diff"] == {}, r)
    check("a nudge reaches the other page", b.wait_for("1 nudges", 2), b.page()[-200:])
    check("and the sender too (publish includes self)", a.wait_for("1 nudges", 2), a.page()[-200:])
    pushes_before = b.pushes
    b.close()
    a.event("Nudge")
    check("publishing after a page closed is fine", a.wait_for("2 nudges", 2))
    c = Signal()
    check("a new page starts at 0 nudges (state is per page)", "0 nudges" in c.page(), c.page()[-200:])
    c.close()

    nope = Signal("nope")
    check("unknown signal -> join error", nope.join[4]["status"] == "error", nope.join)
    nope.close()

    ref = a.c.send(a.topic, "phx_leave", {})
    check("leave ok", a.c.reply_to(ref)[4]["status"] == "ok")
    ref = a.c.send(a.topic, "event", ["Add"])
    check("events after leave are unmatched", a.c.reply_to(ref)[4]["response"] == {"reason": "unmatched topic"})
    a.close()

    print()
    if FAILED == 0:
        print(f"SIGNAL OK ({PASSED} checks)")
        return 0
    print(f"SIGNAL FAILED ({FAILED} of {PASSED + FAILED})")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"FAIL  exception: {e!r}")
        sys.exit(1)
