#!/usr/bin/env python3
"""rz_channel through rz_run: join, round trip, broadcasts, rz_chan_conn.

    python3 tests/fixtures/app/channels/client.py <port>
"""
import os
import socket
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../integration"))
import chat_client as cc  # noqa: E402
import ws_client as w  # noqa: E402

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8084
cc.PORT = w.PORT = PORT
check = cc.check


class Client(cc.Client):
    """A v2 channel client whose upgrade request may carry a Cookie header."""

    def __init__(self, cookie=None):
        self.s = socket.create_connection(("127.0.0.1", PORT), timeout=3)
        extra = f"Cookie: {cookie}\r\n" if cookie else ""
        _, self.head = w.handshake(self.s, path="/socket/websocket?vsn=2.0.0", extra=extra)
        self.r = w.Reader(self.s)
        self.ref = 0
        self.join_refs = {}


def http(method, path):
    s = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    s.sendall(f"{method} {path} HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".encode())
    data = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        data += chunk
    s.close()
    head, _, body = data.partition(b"\r\n\r\n")
    return int(head.split(b" ")[1]), body.decode()


def main():
    a = Client(cookie="theme=dark; sid=s3cret")
    check("upgrade on /socket/websocket -> 101", a.head.startswith(b"HTTP/1.1 101"), a.head)
    m = a.reply_to(a.send("room:lobby", "phx_join", {}))
    check("join ok", m[4].get("status") == "ok", m)
    check("join sees the cookie, guard user and peer via rz_chan_conn",
          m[4].get("response") == {"room": "room:lobby", "sid": "s3cret", "user": "ann", "peer": "127.0.0.1"}, m)
    m = a.reply_to(a.send("room:vip", "phx_join", {}))
    check("cookie-gated join admitted with the cookie", m[4].get("status") == "ok", m)

    b = Client()
    m = b.reply_to(b.send("room:lobby", "phx_join", {}))
    check("anonymous join: no cookie, no user",
          m[4].get("status") == "ok" and m[4]["response"]["sid"] == "" and m[4]["response"]["user"] == "none", m)
    m = b.reply_to(b.send("room:vip", "phx_join", {}))
    check("cookie-gated join refused without the cookie",
          m[4] == {"status": "error", "response": {"reason": "sign in first"}}, m)

    m = a.reply_to(a.send("room:lobby", "echo", {"x": 1}))
    check("message round trip (echo reply)", m[4] == {"status": "ok", "response": {"x": 1}}, m)
    m = a.reply_to(a.send("room:lobby", "nope", {}))
    check("unknown event -> error reply", m[4].get("status") == "error", m)

    a.send("room:lobby", "shout", {"t": "hi"})
    ma, mb = a.next(), b.next()
    check("handle_in broadcast reaches both members",
          ma[3] == "shout" and mb[3] == "shout" and mb[4] == {"t": "hi"}, (ma, mb))

    code, body = http("POST", "/announce?topic=room:lobby&msg=hello")
    check("rz_broadcast from an HTTP handler -> 202", code == 202, (code, body))
    ma, mb = a.next(), b.next()
    check("rz_broadcast reaches every member of the topic",
          ma[2:5] == ["room:lobby", "news", {"msg": "hello"}] and mb[2:5] == ["room:lobby", "news", {"msg": "hello"}],
          (ma, mb))
    http("POST", "/announce?topic=room:vip&msg=vip")
    ma = a.next()
    check("rz_broadcast is per topic (vip member gets room:vip)", ma[2:4] == ["room:vip", "news"], ma)
    b.s.settimeout(0.3)
    try:
        extra = b.next()
        check("non-member of room:vip gets nothing", False, extra)
    except (socket.timeout, TimeoutError):
        check("non-member of room:vip gets nothing", True)

    # 3 memberships (a: lobby + vip, b: lobby); closing both sockets runs every leave.
    _, before = http("GET", "/leaves")
    a.close()
    b.close()
    got = ""
    for _ in range(30):
        _, got = http("GET", "/leaves")
        if got.split() == ["3", "3"]:
            break
        time.sleep(0.1)
    check("socket close runs leave for each member, with the RzConn still readable",
          before.split() == ["0", "0"] and got.split() == ["3", "3"], (before, got))

    print(f"\n{'CHANNELS OK' if cc.FAILED == 0 else 'CHANNELS FAILED'} ({cc.PASSED} passed, {cc.FAILED} failed)")
    return 0 if cc.FAILED == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
