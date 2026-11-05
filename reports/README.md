# Reports: bugs, limitations and missing features

Everything known to be wrong or missing in raize_web, one file each, so nothing lives only
in a conversation. Compiler issues are not kept here: they live in ~/Projects/mettle/reports (e.g. 074 tagged literals, 078 match on plain enums, 091 export-less import visibility). Scope: Mettle and the Mettle ecosystem only (raize, the Mettle compiler,
mbuild, flux_orm, MeoSQL, mist_plot). Nothing about external libraries or tools. Add a file for every new bug or missing feature (next free number),
update its status line when it changes, and keep this index in sync.

Kinds: **bug** (wrong behaviour), **limitation** (works, with a known restriction),
**unverified** (designed but not tested), **missing** (feature not built), **cleanup**,
**compiler** (a Mettle compiler issue raize works around).

| # | Kind | Project | Severity | Item | Status |
|---|---|---|---|---|---|
| [003](003-clear-cookie-path.md) | limitation | raize_web | low | `rz_ctx_clear_cookie` takes no options (only `Path=/`, can't repeat Secure/SameSite) | open |
| [004](004-sigterm-live-clients.md) | unverified | raize_web | medium | Shutdown on SIGTERM with live keep-alive or WebSocket clients is unverified | open; channel socket verified (fixtures/app/channels, exit 0 < 3 s); keep-alive and Signal still to check |
| [008](008-view-hole-error-lines.md) | limitation | raize_web | low | A Mettle type error inside a view hole points at the `return html"""` line | open; needs a compiler line-mapping directive or tagged literals (Mettle report 074) |
| [009](009-rzpp-resource-file-size.md) | cleanup | raize_web | low | `tools/rzpp/resource.mettle` is 459 lines (D6 budget 400); lint does not cover tools/ | open; 430 after P3-C3 moved the contract helpers to tools/rzpp/contract.mettle; P6-G3 splits it and extends lint to tools/ |
| [010](010-signal-dependency-tracking.md) | missing | raize_web | low | Signals re-render the whole view per event (value diff), not per changed field | open; design in docs/design/views.md §3, needs compiler help |
| [011](011-keyed-lists.md) | missing | raize_web | low | No keyed lists: a changed comprehension resends its whole `d` array | open (O2: out of scope of the redesign) |
| [019](019-library-split.md) | missing | raize_web | high | raize is one package; it must become a framework of several libraries | open; next design step D8 (user direction 2026-11-04, AC S7) |
| [021](021-auth-library.md) | missing | raize_web | high | No auth library (KDF password hashing, sign-up/login/logout flows, guards, lockout) | open; part of D8 (user direction 2026-11-04) |
| [022](022-resource-policies.md) | missing | raize_web | medium | Resources have no actor/policies: derived JSON APIs cannot scope records per user | open; after the redesign (DECISIONS A13) |
| [023](023-mbuild-package.md) | missing | raize_web | medium | raize_web has no mbuild.mettle (library package `raize`, rzpp as its only bin) | open; after P3 / with D8 (library, not a binary) |
| [024](024-flux-orm-data-layer.md) | missing | raize_web | medium | No data layer over flux_orm/MeoSQL; resources only have the in-memory layer | open (O1); the RzDataLayer vtable is shaped to map onto flux_orm's repo API (DECISIONS D4) |
| [025](025-db-change-pushes.md) | missing | raize_web | low | Signals cannot be pushed from database changes | open; waits on MeoSQL change notifications (asked; message to MeoSQL session expired undelivered) |
| [026](026-event-loop-portability.md) | limitation | raize_web | low | The event loop (framework/poll) is Linux x86-64 only (raw syscall numbers) | won't fix: bridge until the BEAM/OTP-style Mettle runtime owns I/O (docs/design/realtime.md §4) |
| [027](027-docs-reference-guide.md) | missing | raize_web | high | Most exports lack contract docs; no reference pages or guide yet | open; P5-P7 (D5: `///` contracts on every export, doccheck in lint, generated reference, docs/guide.md) |
| [028](028-rate-limit-middleware.md) | missing | raize_web | medium | No per-peer rate-limiting middleware (`rz_use_rate_limit`) | open |
| [029](029-guards-before-405.md) | limitation | raize_web | low | Guards run before the router's method check (guard answer instead of 405) | open |
| [030](030-telemetry-library.md) | missing | raize_web | medium | No telemetry library (events, handlers, spans, metrics) | open; part of D8 |
| [032](032-upgrade-abort-leak.md) | bug | raize_web | low | An upgrade aborted after the handler returns leaks its RzConn and a hub slot | open |

Related: example_sass keeps its own reports in `~/Projects/mettle/example_sass/reports/`
(001 is a Mettle release-build ICE it found; 002/003 are raize's 001/002 here; its
`F01-raize-missing.md` lists the raize features it needs, all tracked here).
| [033](033-hub-ws-intermittent-hang.md) | bug | raize_web | medium | The hub WebSocket suite hung once (ws_client against hub_app) | open |
