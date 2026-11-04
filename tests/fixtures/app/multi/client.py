#!/usr/bin/env python3
"""The multi app's Signal check: Counter lives in counter.mettle (imported, generated).
Join signal:counter, see the mount's 7 (from util.mettle), send ["Inc"], expect 8.

    python3 tests/fixtures/app/multi/client.py <port>
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../integration"))
import signal_client as sc  # noqa: E402

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8073
sc.PORT = sc.w.PORT = sc.cc.PORT = PORT


def main():
    s = sc.Signal("counter", path="/counter")
    sc.check("join signal:counter replies ok", s.join[4].get("status") == "ok", s.join)
    sc.check("joined page shows 7 (mount reads util)", '<p class="n">7</p>' in s.page(), s.page())
    reply = s.event("Inc")
    diff = reply.get("response", {}).get("diff", {})
    sc.check("Inc replies with a diff containing 8", reply.get("status") == "ok" and "8" in json.dumps(diff), reply)
    sc.check("page shows 8 after the diff", '<p class="n">8</p>' in s.page(), s.page())
    s.close()
    print(f"\n{'SIGNAL OK' if sc.FAILED == 0 else 'SIGNAL FAILED'} ({sc.PASSED} passed, {sc.FAILED} failed)")
    return 0 if sc.FAILED == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
