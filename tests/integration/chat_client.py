#!/usr/bin/env python3
"""Phoenix channel checks against examples/chat over real sockets.

Speaks the v2 protocol ([join_ref, ref, topic, event, payload]) exactly as
phoenix.js does, on top of the stdlib-only WebSocket helpers in ws_client.py.

    python3 tests/integration/chat_client.py <port>
"""
import json
import os
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ws_client as w  # noqa: E402

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8090
w.PORT = PORT
PASSED = 0
FAILED = 0


def check(label, ok, detail=""):
    global PASSED, FAILED
    if ok:
        PASSED += 1
        print(f"PASS  {label}")
    else:
        FAILED += 1
        print(f"FAIL  {label} {detail}")


class Client:
    def __init__(self):
        self.s = socket.create_connection(("127.0.0.1", PORT), timeout=3)
        key, head = w.handshake(self.s, path="/socket/websocket?vsn=2.0.0")
        self.head = head
        self.r = w.Reader(self.s)
        self.ref = 0
        self.join_refs = {}

    def send(self, topic, event, payload, join_ref=None):
        self.ref += 1
        ref = str(self.ref)
        if event == "phx_join":
            self.join_refs[topic] = ref
            join_ref = ref
        elif join_ref is None:
            join_ref = self.join_refs.get(topic)
        self.s.sendall(w.frame(1, json.dumps([join_ref, ref, topic, event, payload]).encode()))
        return ref

    def next(self, skip_ticks=True):
        while True:
            op, p = self.r.frame()
            if op == 8:
                return ("close", w.close_code(p))
            msg = json.loads(p)
            if skip_ticks and msg[3] == "tick":
                continue
            return msg

    def reply_to(self, ref):
        while True:
            m = self.next()
            if m[3] == "phx_reply" and m[1] == ref:
                return m

    def close(self):
        self.s.close()


def main():
    page = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    page.sendall(b"GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    data = b""
    while True:
        chunk = page.recv(65536)
        if not chunk:
            break
        data += chunk
    check("GET / serves the chat page", data.startswith(b"HTTP/1.1 200") and b"room:lobby" in data)

    a = Client()
    check("socket upgrade", a.head.startswith(b"HTTP/1.1 101"))

    # heartbeat
    ref = a.send("phoenix", "heartbeat", {})
    m = a.reply_to(ref)
    check("heartbeat reply ok", m[2] == "phoenix" and m[4]["status"] == "ok", m)

    # join with a response body
    ref = a.send("room:lobby", "phx_join", {"user": "ann"})
    m = a.reply_to(ref)
    check("join ok", m[4] == {"status": "ok", "response": {"room": "room:lobby"}}, m)
    check("join reply echoes join_ref", m[0] == ref, m)

    # refused and unmatched joins
    ref = a.send("room:secret", "phx_join", {})
    m = a.reply_to(ref)
    check("refused join -> error + reason", m[4] == {"status": "error", "response": {"reason": "unauthorized"}}, m)
    ref = a.send("nope:1", "phx_join", {})
    m = a.reply_to(ref)
    check("unmatched topic join -> error", m[4]["response"] == {"reason": "unmatched topic"}, m)

    # events
    ref = a.send("room:lobby", "ping", {})
    m = a.reply_to(ref)
    check("handle_in reply", m[4] == {"status": "ok", "response": {"pong": True}}, m)
    ref = a.send("room:lobby", "bogus", {})
    m = a.reply_to(ref)
    check("handle_in error reply", m[4]["status"] == "error", m)
    a.send("room:lobby", "whoami", {})
    m = a.next()
    check("push to caller only", m[3] == "you" and m[4] == {"user": "ann"} and m[0] == a.join_refs["room:lobby"], m)

    # event on a topic not joined
    ref = a.send("room:other", "new_msg", {"body": "x"}, join_ref="99")
    m = a.reply_to(ref)
    check("event on unjoined topic -> unmatched", m[4]["response"] == {"reason": "unmatched topic"}, m)

    # broadcast across sockets, and room isolation
    b = Client()
    b.reply_to(b.send("room:lobby", "phx_join", {"user": "bob"}))
    c = Client()
    c.reply_to(c.send("room:kitchen", "phx_join", {"user": "cat"}))
    a.send("room:lobby", "new_msg", {"body": "hello \"world\""})
    ma, mb = a.next(), b.next()
    want = {"user": "ann", "body": "hello \"world\""}
    check("broadcast reaches sender", ma[3] == "new_msg" and ma[4] == want, ma)
    check("broadcast reaches other member", mb[3] == "new_msg" and mb[4] == want and mb[0] is None, mb)
    c.send("room:kitchen", "new_msg", {"body": "only kitchen"})
    mc = c.next()
    check("other room gets its own message", mc[4] == {"user": "cat", "body": "only kitchen"}, mc)
    ref = b.send("room:lobby", "ping", {})
    mb = b.reply_to(ref)
    check("lobby member did not see kitchen message", mb[4]["status"] == "ok", mb)

    # cross-thread broadcast (ticker -> rz_chan_post_broadcast)
    deadline = time.time() + 2
    saw = None
    while time.time() < deadline and saw is None:
        m = b.next(skip_ticks=False)
        if m[3] == "tick":
            saw = m
    check("tick broadcast from another thread", saw is not None and saw[2] == "room:lobby" and saw[4]["n"] >= 1, saw)
    c.send("room:kitchen", "ping", {})
    mc = c.next(skip_ticks=False)
    check("kitchen does not get lobby ticks", mc[3] == "phx_reply", mc)

    # leave, then events are unmatched and broadcasts stop
    ref = b.send("room:lobby", "phx_leave", {})
    check("leave ok", b.reply_to(ref)[4]["status"] == "ok")
    ref = b.send("room:lobby", "ping", {})
    check("after leave -> unmatched", b.reply_to(ref)[4]["response"] == {"reason": "unmatched topic"})

    # closing a socket removes its memberships: a's broadcast reaches only a
    c.close()
    b.close()
    time.sleep(0.2)
    a.send("room:lobby", "new_msg", {"body": "after"})
    check("broadcast after others left", a.next()[4] == {"user": "ann", "body": "after"})

    # non-protocol frame -> close 1003
    d = Client()
    d.s.sendall(w.frame(1, b"not json"))
    check("garbage frame -> close 1003", d.next() == ("close", 1003))
    d.close()

    # many members in one room
    many = [Client() for _ in range(30)]
    for i, cl in enumerate(many):
        cl.reply_to(cl.send("room:big", "phx_join", {"user": f"u{i}"}))
    many[0].send("room:big", "new_msg", {"body": "to all"})
    ok = all(cl.next()[4] == {"user": "u0", "body": "to all"} for cl in many)
    check("broadcast to 30 members", ok)
    for cl in many:
        cl.close()
    a.close()

    print()
    if FAILED == 0:
        print(f"CHAT OK ({PASSED} checks)")
        return 0
    print(f"CHAT FAILED ({FAILED} of {PASSED + FAILED})")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"FAIL  exception: {e!r}")
        sys.exit(1)
