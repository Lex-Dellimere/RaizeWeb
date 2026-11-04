# 004: Shutdown on SIGTERM with live keep-alive or WebSocket clients is unverified

- **Project:** raize_web
- **Kind:** unverified
- **Severity:** medium
- **Status:** open; P3-C fixture asserts exit 0 within 3 s with a connected Signal

P3-A blocks SIGTERM/SIGINT in every thread and stops the server from a watcher thread
(no libc, so no signal handlers). Exit 0 is tested with no clients. Not tested: a worker
blocked in a keep-alive read (bounded by `read_timeout_ms`), and the hub with open
sockets (should send 1001 and close).
