# 006: Signals cannot be per-user: `mount` gets no request, session or user, and the Signal socket has no guard

- **Project:** raize_web
- **Kind:** missing
- **Severity:** high
- **Status:** open; P3-C (DECISIONS A9, A10, F5)

Planned: `fn x_mount(s: X*, c: RzConn*) -> int32` (cookies, user, peer from the upgrade
request; non-RZ_OK refuses the join), guards run on the socket upgrade using the page path
carried in the socket URL, and a Signal join is refused unless the socket was opened for
that Signal's path. Until then authenticated apps (example_sass) keep Signals off
signed-in pages.
