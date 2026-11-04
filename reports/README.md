# Reports: bugs, limitations and missing features

Everything known to be wrong or missing in raize_web, one file each, so nothing lives only
in a conversation. Scope: Mettle and the Mettle ecosystem only (raize, the Mettle compiler,
mbuild, flux_orm, MeoSQL, mist_plot). Nothing about external libraries or tools. Add a file for every new bug or missing feature (next free number),
update its status line when it changes, and keep this index in sync.

Kinds: **bug** (wrong behaviour), **limitation** (works, with a known restriction),
**unverified** (designed but not tested), **missing** (feature not built), **cleanup**,
**compiler** (a Mettle compiler issue raize works around).

| # | Kind | Project | Severity | Item | Status |
|---|---|---|---|---|---|
| [001](001-str-to-int-unbounded.md) | bug | raize_web | medium | `rz_str_to_int` has no bound: `rz_ctx_query_int` accepts junk as -1 and wraps on overflow | open; queued as B1 (first fix when work resumes) |
| [002](002-form-semicolon-separator.md) | bug | raize_web | low | Query strings and form bodies are also split on `;` | open; queued as B2 |
| [003](003-clear-cookie-path.md) | limitation | raize_web | low | `rz_ctx_clear_cookie` takes no options (only `Path=/`, can't repeat Secure/SameSite) | open |
| [004](004-sigterm-live-clients.md) | unverified | raize_web | medium | Shutdown on SIGTERM with live keep-alive or WebSocket clients is unverified | open; P3-C fixture asserts exit 0 within 3 s with a connected Signal |
| [005](005-channels-not-wired.md) | missing | raize_web | medium | `rz_channel` records a declaration but no `/socket/websocket` route is derived yet | open; P3-C (stopped before it started; tree clean at 32bf689) |
| [006](006-per-user-signals.md) | missing | raize_web | high | Signals cannot be per-user: `mount` gets no request, session or user, and the Signal socket has no guard | open; P3-C (DECISIONS A9, A10, F5) |
| [007](007-rzpp-multi-file.md) | missing | raize_web | medium | rzpp handles one file at a time; multi-file apps need entry mode | open; P3-C |
| [008](008-view-hole-error-lines.md) | limitation | raize_web | low | A Mettle type error inside a view hole points at the `return html"""` line | open; needs a compiler line-mapping directive (report 014) or tagged literals (report 013) |
| [009](009-rzpp-resource-file-size.md) | cleanup | raize_web | low | `tools/rzpp/resource.mettle` is 459 lines (D6 budget 400); lint does not cover tools/ | open; P6-G3 splits it and extends lint to tools/ |
| [010](010-signal-dependency-tracking.md) | missing | raize_web | low | Signals re-render the whole view per event (value diff), not per changed field | open; design in docs/design/views.md §3, needs compiler help (report 015) |
| [011](011-keyed-lists.md) | missing | raize_web | low | No keyed lists: a changed comprehension resends its whole `d` array | open (O2: out of scope of the redesign) |
| [013](013-compiler-tagged-literals.md) | compiler | Mettle compiler | feature | Tagged literals (`html"""..."""` handed to a compile-time `@literal` metafunction) | not delivered: the cross-session message to the mettle session was held and expired; full request in docs/design/mettle-tagged-literals-request.md |
| [014](014-compiler-generic-inference-field-access.md) | compiler | Mettle compiler | medium | Generic inference fails on field-access arguments (`put(h, s->n)`: "Nothing in this call says what 'T' is") | worked around in rzpp (field paths render via string interpolation); repro in docs/design/mettle-tagged-literals-request.md |
| [015](015-compiler-lambda-generic-params.md) | compiler | Mettle compiler | medium | A lambda inside a generic function cannot see its type parameters; `&generic<T>` does not parse | worked around with rzpp-generated non-generic glue (`<Type>__handle`, `<s>_signal`) |
| [016](016-compiler-call-indirect-ice.md) | compiler | Mettle compiler | high | Codegen ICE `call_indirect_unsupported` on some indirect calls | worked around (pass string variables, never cast fn pointers from rawptr, call update() directly) |
| [017](017-compiler-match-plain-enum.md) | compiler | Mettle compiler | low | `match` rejects plain (payload-less) enums, so a message enum needs at least one payload | worked around: rzpp reports a payload-less `<T>Msg` as an error (DECISIONS A1) |
| [018](018-compiler-fn-type-mismatch-message.md) | compiler | Mettle compiler | low | A function-type mismatch reports "expected 'function', found 'function'" | open; printing both signatures would help |
| [019](019-library-split.md) | missing | raize_web | high | raize is one package; it must become a framework of several libraries | open; next design step D8 (user direction 2026-11-04, AC S7) |
| [020](020-session-library.md) | missing | raize_web | high | No session handler library (cookies, session store and expiry, signed/hashed tokens, CSRF, flash) | open; part of D8 (user direction 2026-11-04) |
| [021](021-auth-library.md) | missing | raize_web | high | No auth library (KDF password hashing, sign-up/login/logout flows, guards, lockout) | open; part of D8 (user direction 2026-11-04) |
| [022](022-resource-policies.md) | missing | raize_web | medium | Resources have no actor/policies: derived JSON APIs cannot scope records per user | open; after the redesign (DECISIONS A13) |
| [023](023-mbuild-package.md) | missing | raize_web | medium | raize_web has no mbuild.mettle (library package `raize`, rzpp as its only bin) | open; after P3 / with D8 (library, not a binary) |
| [024](024-flux-orm-data-layer.md) | missing | raize_web | medium | No data layer over flux_orm/MeoSQL; resources only have the in-memory layer | open (O1); the RzDataLayer vtable is shaped to map onto flux_orm's repo API (DECISIONS D4) |
| [025](025-db-change-pushes.md) | missing | raize_web | low | Signals cannot be pushed from database changes | open; waits on MeoSQL change notifications (asked; message to MeoSQL session expired undelivered) |
| [026](026-event-loop-portability.md) | limitation | raize_web | low | The event loop (framework/poll) is Linux x86-64 only (raw syscall numbers) | won't fix: bridge until the BEAM/OTP-style Mettle runtime owns I/O (docs/design/realtime.md §4) |
| [027](027-docs-reference-guide.md) | missing | raize_web | high | Most exports lack contract docs; no reference pages or guide yet | open; P5-P7 (D5: `///` contracts on every export, doccheck in lint, generated reference, docs/guide.md) |
| [028](028-rate-limit-middleware.md) | missing | raize_web | medium | No per-peer rate-limiting middleware (`rz_use_rate_limit`) | open |
| [029](029-guards-before-405.md) | limitation | raize_web | low | Guards run before the router's method check (guard answer instead of 405) | open |

Related: example_sass keeps its own reports in `~/Projects/mettle/example_sass/reports/`
(001 is a Mettle release-build ICE it found; 002/003 are raize's 001/002 here; its
`F01-raize-missing.md` lists the raize features it needs, all tracked here).
