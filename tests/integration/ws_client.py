#!/usr/bin/env python3
"""WebSocket checks against tests/fixtures/poll/ws_echo over real sockets.

Standard library only: the client speaks RFC 6455 itself so the test does not
depend on a websocket package being installed.

    python3 tests/integration/ws_client.py <port>
"""
import base64
import hashlib
import os
import socket
import struct
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8095
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
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


def connect():
    s = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    return s


def recv_until(s, marker):
    data = b""
    while marker not in data:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
    return data


def handshake(s, key=None, version="13", extra=""):
    key = key or base64.b64encode(os.urandom(16)).decode()
    req = (
        "GET /socket HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: {version}\r\n{extra}\r\n"
    )
    s.sendall(req.encode())
    head = recv_until(s, b"\r\n\r\n")
    return key, head


def accept_for(key):
    return base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()


def frame(op, payload, fin=True, mask=True):
    b0 = (0x80 if fin else 0) | op
    n = len(payload)
    mbit = 0x80 if mask else 0
    if n < 126:
        head = struct.pack("!BB", b0, mbit | n)
    elif n < 65536:
        head = struct.pack("!BBH", b0, mbit | 126, n)
    else:
        head = struct.pack("!BBQ", b0, mbit | 127, n)
    if not mask:
        return head + payload
    key = os.urandom(4)
    body = bytes(b ^ key[i % 4] for i, b in enumerate(payload))
    return head + key + body


class Reader:
    def __init__(self, s):
        self.s = s
        self.buf = b""

    def need(self, n):
        while len(self.buf) < n:
            chunk = self.s.recv(65536)
            if not chunk:
                raise EOFError
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def frame(self):
        b0, b1 = self.need(2)
        n = b1 & 127
        if n == 126:
            n = struct.unpack("!H", self.need(2))[0]
        elif n == 127:
            n = struct.unpack("!Q", self.need(8))[0]
        assert not (b1 & 0x80), "server frames must not be masked"
        return b0 & 15, self.need(n)

    def next_data(self, skip_ticks=True):
        while True:
            op, p = self.frame()
            if skip_ticks and op == 1 and p.startswith(b"tick "):
                continue
            return op, p


def open_ws():
    s = connect()
    key, head = handshake(s)
    return s, Reader(s), key, head


def close_code(payload):
    return struct.unpack("!H", payload[:2])[0] if len(payload) >= 2 else None


def main():
    # 1. handshake
    s, r, key, head = open_ws()
    lines = head.decode(errors="replace").split("\r\n")
    check("handshake 101", lines[0] == "HTTP/1.1 101 Switching Protocols", lines[0])
    check("accept key", f"Sec-WebSocket-Accept: {accept_for(key)}" in lines)

    # 2. echo text, binary with 16-bit length
    s.sendall(frame(1, b"hello"))
    check("echo text", r.next_data() == (1, b"hello"))
    big = os.urandom(60000)
    s.sendall(frame(2, big))
    check("echo 60000-byte binary", r.next_data() == (2, big))

    # 3. fragments with a ping in between
    s.sendall(frame(1, b"frag", fin=False) + frame(9, b"pp") + frame(0, b"mented"))
    got = [r.next_data(), r.next_data()]
    check("pong between fragments", (10, b"pp") in got, got)
    check("reassembled message", (1, b"fragmented") in got, got)

    # 4. cross-thread tick (posted to the mailbox by another thread)
    deadline = time.time() + 2
    saw_tick = False
    while time.time() < deadline and not saw_tick:
        op, p = r.frame()
        saw_tick = op == 1 and p.startswith(b"tick ")
    check("tick from ticker thread", saw_tick)

    # 5. broadcast reaches another client
    s2, r2, _, _ = open_ws()
    s.sendall(frame(1, b"broadcast:hi all"))
    check("broadcast to sender", r.next_data() == (1, b"hi all"))
    check("broadcast to other client", r2.next_data() == (1, b"hi all"))

    # 6. clean close: echoed code, then EOF
    s.sendall(frame(8, struct.pack("!H", 1000) + b"bye"))
    op, p = r.next_data()
    check("close echoed with 1000", op == 8 and close_code(p) == 1000, (op, p))
    try:
        r.frame()
        check("EOF after close", False)
    except EOFError:
        check("EOF after close", True)
    s.close()

    # 7. protocol errors close with the right code
    s2.sendall(frame(1, b"x", mask=False))
    op, p = r2.next_data()
    check("unmasked frame -> 1002", op == 8 and close_code(p) == 1002, (op, p))
    s2.close()
    s3, r3, _, _ = open_ws()
    s3.sendall(frame(2, os.urandom(70000)))
    op, p = r3.next_data()
    check("70000-byte message -> 1009", op == 8 and close_code(p) == 1009, (op, p))
    s3.close()
    s4, r4, _, _ = open_ws()
    s4.sendall(frame(1, b"\xc0\xaf"))
    op, p = r4.next_data()
    check("invalid UTF-8 -> 1007", op == 8 and close_code(p) == 1007, (op, p))
    s4.close()

    # 8. refused upgrades
    s5 = connect()
    _, head = handshake(s5, version="8")
    check("version 8 -> 426", head.startswith(b"HTTP/1.1 426"), head[:20])
    s5.close()
    s6 = connect()
    _, head = handshake(s6, key="short")
    check("bad key -> 400", head.startswith(b"HTTP/1.1 400"), head[:20])
    s6.close()

    # 9. many clients at once, each echoed on its own connection
    clients = [open_ws() for _ in range(50)]
    for i, (cs, _, _, _) in enumerate(clients):
        cs.sendall(frame(1, f"client {i}".encode()))
    ok = all(cr.next_data() == (1, f"client {i}".encode()) for i, (_, cr, _, _) in enumerate(clients))
    check("50 concurrent clients echoed", ok)
    for cs, _, _, _ in clients:
        cs.close()

    # 10. the server is still serving after all of that
    s7, r7, _, _ = open_ws()
    s7.sendall(frame(1, b"still here"))
    check("still serving", r7.next_data() == (1, b"still here"))
    s7.close()

    print()
    if FAILED == 0:
        print(f"WS OK ({PASSED} checks)")
        return 0
    print(f"WS FAILED ({FAILED} of {PASSED + FAILED})")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # a hung or dead server shows up here
        print(f"FAIL  exception: {e!r}")
        sys.exit(1)
