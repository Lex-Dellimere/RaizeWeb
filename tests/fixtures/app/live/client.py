#!/usr/bin/env python3
"""Per-user Signals over real sockets (P3-C2, DECISIONS A9, A10, F5).

    python3 tests/fixtures/app/live/client.py <port>
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../integration"))
import signal_client as sc  # noqa: E402

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8072
sc.PORT = sc.w.PORT = sc.cc.PORT = PORT
ANN = "theme=dark; sid=ann-token"
BOB = "sid=bob-token"


def status_line(s):
    return s.c.head.split(b"\r\n", 1)[0].decode(errors="replace")


def ok(s):
    return s.join is not None and s.join[4].get("status") == "ok"


def reason(reply):
    return reply.get("response", {}).get("reason")


def main():
    a = sc.Signal("board", path="/admin", cookie=ANN)
    sc.check("ann joins signal:board on a socket opened for /admin", ok(a), a.join)
    sc.check("ann's mount read the guard's user, the cookie and the path",
             all(t in a.page() for t in ('"who">ann<', '"sid">ann-token<', '"path">&#x2F;admin<', '"n">10<')), a.page())
    a.event("Inc")
    sc.check("ann's Inc -> 11", '"n">11<' in a.page(), a.page())

    b = sc.Signal("board", path="/admin", cookie=BOB)
    sc.check("bob joins with his own state (bob, 20)", ok(b) and '"who">bob<' in b.page() and '"n">20<' in b.page(), b.page())
    b.event("Inc")
    b.event("Inc")
    a.event("Inc")
    sc.check("per-user state: bob 22, ann 12", '"n">22<' in b.page() and '"n">12<' in a.page(), (a.page(), b.page()))
    a.close()
    b.close()

    n = sc.Signal("board", path="/admin")
    sc.check("no cookie: the /admin guard refuses the upgrade (302 /login)",
             n.join is None and " 302 " in status_line(n) and b"Location: /login" in n.c.head, n.c.head)
    n.close()

    t = sc.Signal("board", path="/public/../admin")
    sc.check("path=/public/../admin is normalized and guarded too", t.join is None and " 302 " in status_line(t), t.c.head)
    t.close()

    e = sc.Signal("board", path="/admin", cookie="sid=eve-token")
    sc.check("a refusing 2-arg mount refuses the join with its status text",
             e.join is not None and e.join[4].get("status") == "error" and reason(e.join[4]) == "not found", e.join)
    e.close()

    p = sc.Signal("hits", path="/public")
    sc.check("the public Signal (1-arg mount) joins with no cookie", ok(p) and '"hits">5<' in p.page(), p.join)
    r = p.join_topic("board")
    sc.check("a socket opened for /public cannot join signal:board",
             r.get("status") == "error" and reason(r) == "socket not opened for this page", r)
    p.event("Hit")
    sc.check("the /public socket still works after the refused join", '"hits">6<' in p.page(), p.page())
    p.close()

    q = sc.Signal("board", path="/public", cookie=ANN)
    sc.check("even with ann's cookie, a /public socket cannot join signal:board",
             q.join is not None and q.join[4].get("status") == "error" and reason(q.join[4]) == "socket not opened for this page", q.join)
    q.close()

    m = sc.Signal("hits")
    sc.check("no ?path= -> 400", m.join is None and " 400 " in status_line(m), m.c.head)
    m.close()

    print(f"\n{'LIVE OK' if sc.FAILED == 0 else 'LIVE FAILED'} ({sc.PASSED} passed, {sc.FAILED} failed)")
    return 0 if sc.FAILED == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
