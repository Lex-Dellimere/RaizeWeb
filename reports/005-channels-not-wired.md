# 005: `rz_channel` records a declaration but no `/socket/websocket` route is derived yet

- **Project:** raize_web
- **Kind:** missing
- **Severity:** medium
- **Status:** fixed (P3-C1)

Declaring a channel in an app's declaration function currently does nothing at
runtime and nothing warns. P3-C wires it and makes an unwired declaration a startup
error (DECISIONS F3). examples/chat still uses the old explicit channel API, which works.

**Fixed (P3-C1):** rz_run derives GET /socket/websocket from the declarations (a hub that cannot start is a startup error, exit 1), adds `rz_broadcast(topic, event, json)` and `rz_chan_conn(ctx)`; covered by tests/fixtures/app/channels.
