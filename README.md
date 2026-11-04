# raize

A web framework written in [Mettle](https://github.com/The-Mettle-Project/Mettle),
a systems language with its own compiler, runtime and linker.

raize is deliberately small and boring: a blocking TCP accept loop, a trie
router, a fixed middleware chain, a template renderer, a static file server, and
an interface seam for a custom database engine. It owns no event loop, no
thread pool beyond its workers, and no dependencies at all — the runtime it
links is Mettle's, which means no libc, no TLS library, no OpenSSL, and no
`poll`/`epoll` (Mettle does not have them).

## Layout

```
framework/
├── server/      listener, worker pool, connection loop, HTTP/1.1 parser
├── context/     request/response, headers, query, params, json, date, arena
├── router/      trie router: exact > :param > *wildcard, 405 + Allow, groups
├── middleware/  request pipeline, logging, limits, CORS, auth hook
├── template/    HTML/text renderer with escaping and sections
├── static/      file serving: mime types, ETag/304, traversal-safe
├── ws/          WebSocket protocol: handshake, frames, UTF-8, connection state
├── poll/        epoll event loop + cross-thread mailbox (Linux x86-64, syscall)
├── hub/         WebSocket routes: upgrade on a worker, serve on one loop thread
├── channel/     Phoenix channels: v2 wire format, topics, join/handle_in/leave
├── signal/      Signals: rendered trees, diffs, the page shell, signal.js
├── orm/         storage vtable, unit of work, migrations hook (no database)
├── config/      env + config, validated at startup, immutable after
└── str/         the base layer: string views, owned copies, buffers, splitting
examples/tasks/  a complete example: template, JSON API, static files
examples/chat/   Phoenix-style channels: rooms, broadcast, a browser client
examples/todos/  a Signal: typed state + messages, html""" views, live diffs
tools/rzpp/      the html""" preprocessor (written in Mettle)
tests/           lint.sh, integration/*.sh, unit/*.mettle, fixtures/
docs/            architecture review and design notes
notes/           the Mettle language study this was built on
```

Dependency direction is one-way: `context` imports only `framework/str/str` and
the Mettle standard library; nothing else may be imported by it. See
`docs/architecture-review.md` for the full rules and the Phase 1 contract.

## Build and run

A locally built compiler is expected at `./mettle-build/bin/mettle`
(see `notes/HOW-I-VERIFIED.md` for how it was built; `make` in a copy of the
Mettle tree takes about 45 seconds).

```bash
make                 # build every example
make lint            # layout rules: <=400 product lines/file, name prefixes
make test            # lint + run @test functions in the interpreter (no codegen)
make smoke           # start examples/tasks and prove it over a real socket
make run-tasks       # build and run on :8080
```

Or by hand:

```bash
./mettle-build/bin/mettle --build examples/tasks/app.mettle -o build/tasks
./build/tasks
curl -i http://127.0.0.1:8080/
```

## Example: examples/tasks

A small task list that exercises the whole framework in one process:

| Route | What it shows |
|---|---|
| `GET /` | a template compiled once at startup |
| `GET /healthz` | JSON response + store counters |
| `GET/POST /api/tasks` | JSON in, JSON out, bounded in-memory store |
| `GET /api/tasks/:id` | path params |
| `POST /api/tasks/:id/toggle` | a mutating route |
| `DELETE /api/tasks/:id` | 204, owned-string cleanup |
| `GET /static/*` | static files with ETag/304 |
| `OPTIONS /api/tasks` | CORS preflight from the middleware chain |

The pipeline is `recover -> logging -> cors -> router`. Mutations take a spin
lock because the server runs `RAIZE_WORKERS` threads; titles are copied out of
the request arena before they are stored. Configuration comes from `RAIZE_*`
environment variables, and `--port` wins over the environment.

```bash
make smoke            # build + 29 checks over real sockets
make run-tasks        # http://127.0.0.1:8080/
RAIZE_PORT=8099 make run-tasks
```

## What the framework promises, and what it does not

Promises:

- Bounded everything: header bytes, header count, body bytes, request line,
  keep-alive requests, middleware depth, route count, params. Exceeding a
  bound is a 4xx with a reason, never a growing buffer.
- A read timeout on every accepted socket, so one stalled client cannot pin a
  worker.
- Parser as a pure function (`rz_parse`), testable with `mettle test` and no
  sockets.
- Threads are always joined. Mettle leaks 1 MiB per detached thread
  (`notes/issues/02-thread-close-detach-leak.md`), so detaching is forbidden
  project-wide.

Does not promise, because Mettle cannot:

- TLS. Run raize behind a reverse proxy and trust `X-Forwarded-*` only when a
  proxy is configured.
- DNS. Bind by address.
- HTTP/2, chunked request bodies, or `Expect: 100-continue` beyond the
  documented answer.
- An event loop off Linux x86-64. `framework/poll` uses raw x86-64 syscall
  numbers through the dev compiler's `syscall` builtin; the blocking HTTP
  server works everywhere.
- Catching a fault. A hardware fault is a process death in Mettle; the
  framework turns error *returns* into 500s, and a supervisor restarts the
  process.

## Realtime (in progress)

WebSockets, channels and Signals (real-time pages, after Phoenix LiveView),
following Phoenix's model and wire protocol:
see `docs/design/realtime.md`. Done so far: the WebSocket protocol
(`framework/ws`, interpreter-tested) and the epoll loop (`framework/poll`),
proven together by `make ws-test` (18 checks over real sockets: echo,
fragments, ping, close codes 1002/1007/1009, a cross-thread broadcast, 50
concurrent clients). `framework/hub` mounts WebSockets on the real server: a
route calls `rz_hub_upgrade`, the worker writes the 101 and hands the socket
to the hub thread, and goes back to accept(). `make hub-test` runs the same 18
checks through the router with 4 workers, plus plain HTTP on the same port.

`framework/channel` is Phoenix channels on the hub, speaking Phoenix's v2
wire format (`[join_ref, ref, topic, event, payload]`), so phoenix.js is a
valid client. `examples/chat` uses it: `./build/chat 8090` serves a chat page
on :8090. `make chat-test` runs 22 protocol checks
(join/refuse/unmatched, replies, push, room-isolated broadcast, a broadcast
posted from another thread, leave, cleanup on disconnect, 30-member rooms).

**Signals** are real-time pages written as Mettle: a state struct, a message
enum, `update`, and a `view` that returns an `html"""..."""` literal whose `{}`
holes, loops, branches, components and `on:event={Msg(...)}` handlers are
all Mettle. `tools/rzpp` compiles the literals (until the compiler has tagged
literals), the server sends Phoenix-format diffs, and `framework/signal/
signal.js` patches the DOM. `examples/todos` is a complete one:

```bash
make build/todos && ./build/todos 8070    # open http://127.0.0.1:8070/todos
make signal-test                          # rzpp diagnostics + 21 protocol checks
```

See `docs/design/views.md`.

`framework/poll` and `framework/hub` are a bridge: the epoll loop and the hub
thread will be replaced by the BEAM/OTP-style Mettle runtime. App code uses
only the channel and Signal APIs, so it does not change when that happens.

## Status

All five phases are in, gated end to end:

| Phase | State |
|---|---|
| 1 server + context + parser + router | done |
| 2 middleware (chain, logging, limits, CORS, auth, recover) | done |
| 3 template + static | done |
| 4 orm hooks (vtable, unit of work, migrations) | done |
| 5 config (defaults, env, validation) | done |

Verified numbers (see `reports/status.md` for transcripts):

```
framework/      45 modules, 13 152 lines, LINT OK (<=400 product lines/file)
unit            139 @test assertions across 22 files
integration     SMOKE OK 7/7 · EDGES OK 11/11 · SITE OK 16/16
                LEAK OK 2 000 requests, 0 kB growth (both apps)
                CONFIG OK (env precedence, strict parse, 413 on the new cap)
```

```bash
make integration     # lint, unit, then every HTTP suite over real sockets
```

Live orchestration log: `reports/director.md`. Independent evidence:
`reports/status.md`. Plan and acceptance criteria:
`docs/architecture-review.md`.
