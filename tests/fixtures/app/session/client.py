#!/usr/bin/env python3
"""The session fixture's socket check: a Signal joined with the session cookie
mounts with the session's user (rz_conn_session_get on the hub thread).

    python3 tests/fixtures/app/session/client.py <port> <sid>
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../integration"))
import signal_client as sc  # noqa: E402

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8076
SID = sys.argv[2] if len(sys.argv) > 2 else ""
sc.PORT = sc.w.PORT = sc.cc.PORT = PORT


def main():
    s = sc.Signal("whoami", path="/me", cookie=f"rz_sid={SID}")
    sc.check("join signal:whoami with the session cookie", s.join is not None and s.join[4].get("status") == "ok", s.join)
    sc.check("the socket's mount read the session's user", '"user">ann<' in s.page(), s.page())
    s.event("Inc")
    sc.check("Inc -> 1", '"n">1<' in s.page(), s.page())
    s.close()
    n = sc.Signal("whoami", path="/me")
    sc.check("without the cookie the mount sees no user", n.join is not None and '"user"><' in n.page(), n.page())
    n.close()
    print(f"\n{'SESSION SOCKET OK' if sc.FAILED == 0 else 'SESSION SOCKET FAILED'} ({sc.PASSED} passed, {sc.FAILED} failed)")
    return 0 if sc.FAILED == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
