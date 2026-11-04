# 032: An upgrade aborted after the handler returns leaks its RzConn and a hub slot

- **Project:** raize_web
- **Kind:** bug
- **Severity:** low
- **Status:** open

## What happens
When the server aborts a WebSocket upgrade after the route handler has returned (for example the
handshake write fails), the per-socket `RzConn` captured for channel joins (`rz_chan_conn`) is never
freed, and the hub's reserved-socket counter is not released either. Found while wiring channels
(P3-C1, 17624ab); documented in a code comment at the abort path.

## Fix
Give the abort path the same cleanup as a normal close: call the upgrade's free callback
(`rz_hub_upgrade_with`) and release the reservation. Test: a fixture that forces the handshake
write to fail and checks memory/slot counts stay flat.
