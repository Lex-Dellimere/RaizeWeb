#!/usr/bin/env python3
"""raize/server caps proof — the limits the shell gate does not reach.

Runs against a live server (default 127.0.0.1:8080, override with $1):

  * keep-alive budget: exactly `keepalive_max` responses on one connection,
    the last one saying `Connection: close`, then EOF;
  * read timeout: a stalled partial request gets 408 and the worker is free
    again (the next connection is served);
  * a body larger than the receive buffer (16 KiB) is read correctly, and one
    over the 1 MiB cap is 413 before any of it is read;
  * `Expect: 100-continue` gets the interim response before the body;
  * a request delivered one byte at a time still parses (incremental read);
  * two pipelined requests on one connection get two responses in order;
  * HEAD carries Content-Length but no body;
  * a 65-header request is 431 (the gate only proves the 9 KB byte cap).

Exit code 0 iff every check passes. No third-party dependencies.
"""
import socket
import sys
import time

HOST = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
FAIL = 0


def check(name, cond, detail=""):
    global FAIL
    if cond:
        print(f"PASS  {name}")
    else:
        FAIL += 1
        print(f"FAIL  {name}  {detail}")


def connect(timeout=5.0):
    s = socket.create_connection((HOST, PORT), timeout=timeout)
    s.settimeout(timeout)
    return s


def read_all(s, limit=1 << 20):
    out = b""
    try:
        while len(out) < limit:
            chunk = s.recv(65536)
            if not chunk:
                break
            out += chunk
    except socket.timeout:
        pass
    return out


def read_response(s):
    """Reads one response (status line + headers + Content-Length body)."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            return buf, b""
        buf += chunk
    head, _, rest = buf.partition(b"\r\n\r\n")
    length = 0
    for line in head.split(b"\r\n")[1:]:
        k, _, v = line.partition(b":")
        if k.strip().lower() == b"content-length":
            length = int(v.strip() or b"0")
    body = rest
    while len(body) < length:
        chunk = s.recv(65536)
        if not chunk:
            break
        body += chunk
    return head, body[:length]


def status_of(head):
    return int(head.split(b"\r\n")[0].split(b" ")[1])


def main():
    # --- 1. keep-alive budget ------------------------------------------------
    s = connect()
    s.sendall(b"GET / HTTP/1.1\r\nHost: t\r\n\r\n")
    n = 0
    closes = 0
    try:
        for _ in range(200):
            head, body = read_response(s)
            if not head:
                break
            n += 1
            if b"connection: close" in head.lower():
                closes += 1
                break
            s.sendall(b"GET / HTTP/1.1\r\nHost: t\r\n\r\n")
    except Exception as e:  # noqa: BLE001
        print(f"  (keep-alive loop stopped: {e})")
    s.close()
    check("keep-alive budget stops at 100 with Connection: close",
          n == 100 and closes == 1, f"responses={n} close_headers={closes}")

    # --- 2. read timeout -> 408, worker still free --------------------------
    s = connect()
    s.settimeout(20.0)   # outlive the server's 5 s read timeout
    s.sendall(b"GET / HTTP/1.1\r\nHost: t\r\n")   # no final CRLF on purpose
    t0 = time.time()
    data = read_all(s, 4096)
    dt = time.time() - t0
    s.close()
    check("stalled partial request -> 408 and connection closed",
          data.startswith(b"HTTP/1.1 408"), data[:40])
    check("stall lasted about the 5 s read timeout",
          4.0 <= dt <= 12.0, f"{dt:.2f}s")
    t1 = time.time()
    s = connect()
    s.sendall(b"GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
    head, _ = read_response(s)
    s.close()
    check("worker is free right after a timeout (next request served)",
          status_of(head) == 200, head[:40])
    check("the post-timeout request was fast", time.time() - t1 < 3.0)

    # --- 3. body at and over the buffer/cap boundaries ----------------------
    body = b"x" * 40000          # > 16 KiB receive buffer, < 1 MiB cap
    s = connect()
    req = (b"POST /echo HTTP/1.1\r\nHost: t\r\nContent-Length: "
           + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
    s.sendall(req)
    head, got = read_response(s)
    s.close()
    check("40 KiB body (over the 16 KiB recv buffer) is read and echoed",
          status_of(head) == 200 and got == body, f"{status_of(head)} {len(got)}")

    s = connect()
    s.sendall(b"POST /echo HTTP/1.1\r\nHost: t\r\nContent-Length: 1048577\r\n\r\n")
    data = read_all(s, 4096)
    s.close()
    check("body one byte over the 1 MiB cap -> 413 before reading it",
          data.startswith(b"HTTP/1.1 413"), data[:40])

    # --- 4. Expect: 100-continue -------------------------------------------
    s = connect()
    s.sendall(b"POST /echo HTTP/1.1\r\nHost: t\r\nExpect: 100-continue\r\n"
              b"Content-Length: 5\r\nConnection: close\r\n\r\n")
    interim = b""
    try:
        interim = s.recv(1024)
    except socket.timeout:
        pass
    s.sendall(b"hello")
    head, got = read_response(s)
    s.close()
    check("Expect: 100-continue answered with the interim 100 first",
          interim.startswith(b"HTTP/1.1 100 Continue"), interim[:40])
    check("...and the real response follows the body",
          status_of(head) == 200 and got == b"hello", f"{head[:20]} {got[:10]}")

    # --- 5. one byte at a time (incremental parse) -------------------------
    s = connect()
    req = b"GET /incremental HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n"
    for i in range(len(req)):
        s.sendall(req[i:i + 1])
        time.sleep(0.001)
    head, body = read_response(s)
    s.close()
    check("request delivered one byte at a time parses",
          status_of(head) == 200 and b"incremental" in body, head[:40])

    # --- 6. pipelining ------------------------------------------------------
    s = connect()
    s.sendall(b"GET / HTTP/1.1\r\nHost: t\r\n\r\n"
              b"GET /incremental HTTP/1.1\r\nHost: t\r\n\r\n"
              b"GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
    heads = []
    bodies = []
    try:
        while len(heads) < 3:
            h, b = read_response(s)
            if not h:
                break
            heads.append(status_of(h))
            bodies.append(b)
    except socket.timeout:
        pass
    s.close()
    check("three pipelined requests get three ordered responses",
          heads == [200, 200, 200] and b"incremental" in bodies[1],
          f"{heads} {bodies[:3]}")

    # --- 7. HEAD -----------------------------------------------------------
    s = connect()
    s.sendall(b"HEAD / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
    raw = read_all(s, 8192)
    s.close()
    check("HEAD carries Content-Length and no body",
          raw.startswith(b"HTTP/1.1 200")
          and b"Content-Length: 19" in raw
          and b"hello from fixture" not in raw,
          raw[:120])

    # --- 8. header count cap ------------------------------------------------
    s = connect()
    hdrs = b"".join(b"X-%02d: v\r\n" % i for i in range(64))
    s.sendall(b"GET / HTTP/1.1\r\nHost: t\r\n" + hdrs + b"\r\n")
    data = read_all(s, 4096)
    s.close()
    check("65 headers (count cap, not byte cap) -> 431",
          data.startswith(b"HTTP/1.1 431"), data[:40])

    print()
    if FAIL == 0:
        print("CAPS OK")
        return 0
    print(f"CAPS FAILED ({FAIL})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
