# 006: Signals cannot be per-user: `mount` gets no request, session or user, and the Signal socket has no guard

- **Project:** raize_web
- **Kind:** missing
- **Severity:** high
- **Status:** fixed (P3-C2)

Planned: `fn x_mount(s: X*, c: RzConn*) -> int32` (cookies, user, peer from the upgrade
request; non-RZ_OK refuses the join), guards run on the socket upgrade using the page path
carried in the socket URL, and a Signal join is refused unless the socket was opened for
that Signal's path. Until then authenticated apps (example_sass) keep Signals off
signed-in pages.

**Fixed (P3-C2):** a Signal may declare `fn x_mount(s: X*, c: RzConn*) -> int32` (rzpp detects it; non-RZ_OK refuses the join with its `rz_status_text` and the first GET with `rz_status_http`); signal.js opens `/signal/websocket?path=<page>`, the upgrade runs that page's guards and records the path (`rz_conn_path`), and a join is refused unless the Signal is mounted at that path; covered by tests/fixtures/app/live.
