# Realtime: WebSockets, channels and Signals for raize

Status (2026-11-04): M1-M4 are built and tested (`make integration`); M5-M7
are the plan. Each milestone below says what was actually built.

raize's goal is Phoenix's model in Mettle: server-rendered HTML, channels
(topic-based pub/sub over a socket), and Signals (`RzSignal`, raize's take on
Phoenix LiveView: stateful server views that
push minimal diffs to the browser). Later, a Mettle runtime with BEAM-level
concurrency will host every channel and view as its own process. This document
is the order to build it in, and the decisions that keep today's code
compatible with that runtime.

## 1. The blocker is gone: raize can have an event loop

`framework/server/server.mettle` says Mettle has no `poll`/`select`/`epoll`, so
the server is one blocking thread per connection. That was true of the stdlib
and of release 0.17.0. The dev compiler (`../Mettle/bin/mettle`) has a
`syscall(nr, args...)` builtin (see `mettle-ai-docs/40-toolchain-cli.md`), and
MeoSQL already depends on it.

Verified on 2026-11-04 with a probe built by the dev compiler on Linux x86-64:

| Call | Result |
|---|---|
| `epoll_create1(0)` (291) | fd 3 |
| `eventfd2(0, 0)` (290) | fd 4 |
| `fcntl(sock, F_SETFL, O_NONBLOCK)` (72) on a `std/net` socket | 0 |
| `epoll_ctl(ADD, eventfd, EPOLLIN)` (233) | 0 |
| `epoll_wait` (232) woken by a `CreateThread` worker writing the eventfd | 1 event, correct tag |

`struct epoll_event` is packed on x86-64 (u32 events + u64 data = 12 bytes), so
it is read and written as bytes, never as a Mettle struct.

Consequences:

- A WebSocket costs a file descriptor and some state, not a thread.
- raize now needs the dev compiler, not release 0.17.0. The `mettle-build`
  symlink already points at `../Mettle`, so nothing changes in practice.
- Linux only for the loop. Windows (IOCP) is not planned until someone needs
  it. The blocking HTTP path keeps working everywhere.
- `syscall` is refused by the compile-time interpreter, so loop code is tested
  by built fixtures over real sockets, and the protocol code it calls is kept
  as pure functions that `@test` can reach.

## 2. Copy Phoenix's wire protocol exactly

Channels and Signals talk to the browser in Phoenix's own formats:

- **Channels:** Phoenix serializer v2. Every message is a JSON array
  `[join_ref, ref, topic, event, payload]`. Events are `phx_join`, `phx_leave`,
  `phx_reply`, `phx_error`, `phx_close` and `heartbeat` on topic `phoenix`.
- **Signals:** LiveView's "rendered" diff format. Statics go under `"s"`, dynamics
  under `"0"`, `"1"`, ...; comprehensions use `"d"`; and each update sends only
  the dynamic slots that changed. Clients send `event` messages carrying
  `{type, event, value}` for `phx-click`, `phx-submit` and similar bindings.

Why: the browser half (`phoenix.js`, `phoenix_live_view.js`, MIT licensed) is
then a drop-in, and its behaviour is the specification we test against. If we
cannot ship those files, a small raize client speaks the same protocol, and
the server does not care which one is talking.

## 3. Milestones

Each milestone is committed separately with its tests.

### M1 `framework/ws`: WebSocket protocol as pure functions

- SHA-1 (`rz_sha1`), needed only for the handshake. Tested against the
  RFC 3174 vectors.
- Handshake: validate `Upgrade`, `Connection`, `Sec-WebSocket-Version: 13`
  and `Sec-WebSocket-Key`, and compute `Sec-WebSocket-Accept`. Tested against
  the RFC 6455 §1.3 example (`dGhlIHNhbXBsZSBub25jZQ==` gives
  `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`).
- Frame decoder and encoder: FIN, opcodes (text, binary, ping, pong, close,
  continuation), masking, and 7-, 16- and 64-bit lengths.
- Every bound is a named `RZ_WS_MAX_*` constant, and going over one is a close
  with code 1009, never a growing buffer. The same rule as the HTTP parser.

No sockets are involved, and everything is covered by `@test`.

**Built:** `framework/ws/{sha1,handshake,frame,utf8,conn}.mettle`. `RzWsConn`
is the per-connection state machine (fragmentation, ping/pong, close
handshake, 1002/1007/1009), pure and interpreter-tested.

### M2 `framework/poll`: the event loop

- `rz_poll_*` wraps `epoll_create1`, `epoll_ctl`, `epoll_wait` and `eventfd2`,
  plus nonblocking `accept4`/`recv`/`send` through `syscall`.
- A waker (an eventfd) and an MPSC queue let other threads post messages to
  the loop. This is the seam a broadcast from an HTTP worker goes through.
- Tested by a built fixture: N clients, echo, wakeups from other threads.

**Built:** `framework/poll/{sys,poll}.mettle`; `tests/fixtures/poll/ws_echo`
plus `tests/integration/ws_client.py` (18 checks, debug and release).

### M3 Upgrading a connection into the hub

HTTP stays on the blocking worker pool, which works and is tested. A route
marked as a socket endpoint answers `101 Switching Protocols` on the worker,
then hands the fd to the **hub**: one thread running the M2 loop that owns
every upgraded socket. The worker goes back to `accept()`.

- The hub owns read buffering, frame reassembly, ping/pong, the idle timeout
  and close handshakes.
- Later step (not M3): move HTTP onto the loop too and retire the worker pool.
  Only `conn.mettle` changes. The parser is already a pure function.

**Built:** `framework/hub`. The seam is `RzContext.upgrade` (an `RzUpgrade`
with an `adopt` callback): `rz_hub_upgrade` sets it and returns 101, the
connection loop calls `adopt` on the worker (which writes the 101 and posts
the fd) and returns `RZ_CONN_DETACHED`. `rz_hub_post_call` runs a function on
the hub thread from anywhere, the nearest thing to sending a process a
message until the runtime exists.

### M4 PubSub and channels

- `RzPubSub`: topic name to subscriber list, owned by the hub.
  `rz_pubsub_broadcast(topic, event, payload)` is callable from any thread and
  posts through the hub's queue.
- `RzChannel` callbacks, written as plain function pointers plus a state
  pointer so they map 1:1 onto future processes:
  `join(topic, payload, sock) -> ok|error`, `handle_in(event, payload, sock)`,
  `handle_info(msg, sock)` and `terminate(reason, sock)`.
- Topic routing (`"room:*"`) reuses the router trie's wildcard rules.
- Demo: `examples/chat`, served to the stock `phoenix.js` client.

**Built:** `framework/channel/{wire,types,members,channel}.mettle` and
`examples/chat` (with a small v2 client in the page; phoenix.js itself was
not fetched). `tests/integration/chat_client.py`: 22 checks. Membership is a
flat table scanned per broadcast; a topic index replaces it when needed.

### M5 Templates v2: statics and dynamics

The current engine (`framework/template`) already compiles a template into
`TEXT` ops (statics) and `VAR`/`RAW`/`SECTION` ops (dynamics). Signals need
exactly that split, kept at render time:

- Render to an `RzRendered` value: a statics fingerprint and a dynamic slot
  array, not a flat string. Flattening to HTML stays the first-render path.
- Add list comprehensions (`{{#each}}` producing `"d"`), components (a
  template calling another template, nested rendered output), and expressions
  limited to field paths. There is no general expression language in
  templates. Logic lives in Mettle.
- `phx-*` attributes pass through as text. Nothing needs special-casing.
- Compiling templates at build time (`import_str` plus `comptime`) is worth
  investigating, but startup compilation is the baseline because it already
  works.

### M6 Signals (see `views.md`, which supersedes the API below)

- `RzSignal` callbacks, again written as functions over a state pointer:
  `mount(params, session, sock)`, `handle_event(event, value, sock)`,
  `handle_info(msg, sock)` and `render(assigns) -> RzRendered`.
- **Assigns with change tracking.** `rz_assign(sock, "count", value)` marks
  the key dirty. The render step diffs dynamic slots by comparing old and new
  values, and only changed slots go into the diff.
- First request: a normal HTTP GET renders the full HTML with `data-phx-*`
  session attributes. The client then joins `lv:<id>` over the socket, raize
  re-mounts, and from then on sends diffs.
- Demo: `examples/counter`, then `examples/tasks` rewritten as a Signal.

### M7 The runtime

When the Mettle runtime (BEAM-like processes) arrives:

- Every channel and Signal becomes a process, and its callbacks become its
  message handlers. That is why M4 and M6 are callback-over-state today:
  handlers already receive one message at a time and never share state.
- The hub becomes a scheduler-facing I/O driver, and PubSub becomes process
  messaging.
- Reference model: Erlang/OTP sources in
  `../distibuted_mettle/reference_model/otp`.

## 4. The event loop is a bridge to the runtime

A BEAM/OTP-style runtime for Mettle is being built (with other runtime work
alongside it). When it lands, it owns scheduling and I/O, and
`framework/poll` (epoll through `syscall`) and the hub thread go away. So the
code is layered by what survives:

| Layer | Survives the runtime? |
|---|---|
| `framework/ws` (handshake, frames, UTF-8, `RzWsConn`): pure protocol | yes, unchanged |
| `framework/channel/wire`: the Phoenix v2 format | yes, unchanged |
| Channel and Signal callbacks (join/handle_in/leave; state + message + update + view) | yes, and they become process message handlers |
| `framework/hub` (thread, slots, mailbox) | replaced by processes and runtime mailboxes |
| `framework/poll` (epoll, eventfd, `syscall` numbers) | replaced by runtime I/O |

The rule that keeps the swap cheap: **apps never touch `poll` or the hub's
internals.** They see an opaque `RzHub*`, `rz_hub_upgrade`, and the channel
and Signal APIs. Anything new for Signals is built on those, not on epoll.
Effort on `poll` and `hub` stays minimal: correct and leak-free, not tuned.

## 5. Concurrency rules until the runtime exists

- One hub thread owns every upgraded socket and every channel and Signal
  state. Nothing else touches them. That rule avoids a lock per view and
  matches the process model.
- Other threads (HTTP workers) talk to the hub only through its queue plus
  eventfd wake.
- Callbacks must not block. A callback that needs the database posts work to
  a worker and gets a `handle_info` back. This is the same discipline a
  process runtime will enforce.
- When one hub thread becomes the bottleneck: N hubs, sockets sharded by fd,
  and PubSub fan-out crossing hubs through their queues.

## 6. Inputs from other projects

- **MeoSQL**: "changes visible to clients as they happen" (commit
  notifications) is what would drive live updates from the database, through
  PubSub. raize needs a callback or a queue it can poll.
- **flux_orm**: the data layer for apps, replacing `framework/orm` (which the
  README mentions but the tree does not contain). Callbacks call it from
  workers, not from the hub thread.
- **mbuild**: keep the Makefile until `mbuild.mettle` is settled (the mbuild
  session asked for this on 2026-11-04).
- **MistPlot**: `integrations/raize/mp_raize.mettle` renders charts
  (`mp_raize_svg`, `mp_raize_html`) and makes them live with
  `mp_raize_channel(app, c, topic, socket_path)` plus `mp_raize_notify(c)`, which
  `rz_broadcast`s a small notice so the browser refetches the SVG (ETag/304,
  polling fallback). API: https://github.com/Lex-Dellimere/MistPlot/blob/main/docs/API.md
