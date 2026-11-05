# 033: The hub WebSocket suite hung once (ws_client against hub_app)

- **Project:** raize_web (raize_realtime hub)
- **Kind:** bug
- **Severity:** medium
- **Status:** open

## What happens
During `mbuild integration` on 2026-11-05, `tests/integration/ws.sh build/hub_app 8097 http`
stopped making progress: `ws_client.py` sat connected to `hub_app` for 9 minutes with no
output, after TASKS, EDGES, LEAK, CONFIG and the epoll-loop WS suite had passed. Run alone
right after, the same suite passed 5 times out of 5. So it is intermittent, which points at a
race in the hub (upgrade hand-off from the worker to the hub thread, or the hub mailbox).

## Next
- Find which check the client was on (the suite prints PASS lines only after each check).
- Stress it: run the suite in a loop (100x) to reproduce; then trace the hand-off.
- Every suite now runs under `timeout 120` in the Makefile, so a hang fails instead of stalling.
