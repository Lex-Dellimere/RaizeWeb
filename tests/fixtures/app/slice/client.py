#!/usr/bin/env python3
"""The slice's Signal check: join signal:counter, send ["Inc"], expect a diff with 1.

    python3 tests/fixtures/app/slice/client.py <port>
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../integration"))
import signal_client as sc  # noqa: E402

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8075
sc.PORT = sc.w.PORT = sc.cc.PORT = PORT


def main():
    s = sc.Signal("counter")
    sc.check("join signal:counter replies ok", s.join[4].get("status") == "ok", s.join)
    sc.check("joined page shows <p>0</p>", "<p>0</p>" in s.page(), s.page())
    reply = s.event("Inc")
    diff = reply.get("response", {}).get("diff", {})
    sc.check("Inc replies with a diff containing 1", reply.get("status") == "ok" and "1" in json.dumps(diff), reply)
    sc.check("page shows <p>1</p> after the diff", "<p>1</p>" in s.page(), s.page())
    bad = s.event("Nope")
    sc.check("an unknown message is refused", bad.get("status") == "error", bad)
    s.close()
    print(f"\n{'SIGNAL OK' if sc.FAILED == 0 else 'SIGNAL FAILED'} ({sc.PASSED} passed, {sc.FAILED} failed)")
    return 0 if sc.FAILED == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
