# 005: `rz_channel` records a declaration but no `/socket/websocket` route is derived yet

- **Project:** raize_web
- **Kind:** missing
- **Severity:** medium
- **Status:** open; P3-C (stopped before it started; tree clean at da8c02a)

Declaring a channel in an app's declaration function currently does nothing at
runtime and nothing warns. P3-C wires it and makes an unwired declaration a startup
error (DECISIONS F3). examples/chat still uses the old explicit channel API, which works.
