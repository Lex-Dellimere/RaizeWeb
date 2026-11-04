# 004: Shutdown on SIGTERM with live keep-alive or WebSocket clients is unverified

- **Project:** raize_web
- **Kind:** unverified
- **Severity:** medium
- **Status:** open; channel socket case verified (fixtures/app/channels); keep-alive and Signal still to check

P3-A blocks SIGTERM/SIGINT in every thread and stops the server from a watcher thread
(no libc, so no signal handlers). Exit 0 is tested with no clients. Not tested: a worker
blocked in a keep-alive read (bounded by `read_timeout_ms`), and the hub with open
sockets (should send 1001 and close).

P3-C1: the hub case is now covered for a channel socket: tests/fixtures/app/channels
asserts exit 0 within 3 s after SIGTERM with a joined socket open. Keep-alive HTTP and a
connected Signal are still untested.
