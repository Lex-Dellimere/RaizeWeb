# DECISIONS: raize DX redesign (Ash-style declarations, resources, refactor, docs)

> Design record for raize (D1–D8, amendments, findings). Copied from the local `.apex/DECISIONS.md`;
> paths written before the package split say `framework/...` (see `SPLIT-imports.tsv`).

Decided 2026-11-04 by the design agent. Build agents follow this file. AC.md wins over
it; the compiler wins over both (record the finding here).

## Summary

An app is `import "raize";`, one **declaration function** `fn <app>_app(app: RzApp*)` of
plain calls (routes, static dirs, middleware, config defaults, channels, timers, and the
Signals and resources it mounts), and `fn main() -> int32 { return rz_run("<app>",
&<app>_app); }`. `rz_run` records the declarations, loads config, reports every mistake
at once, then derives the wiring: hub, channel router, socket routes, `/rz/signal.js`,
Signal pages, JSON API routes, middleware chain, server. Types that need generated code
carry **decorators** that tools/rzpp expands today (`@signal`, `@resource` and its
attribute/action decorators). Decorator arguments are identifiers and integers only, the
shape Mettle already parses for layout decorators, so the same source moves to
`@generate` metafunctions later. Resources are flux_orm-shaped: struct, field metadata
from `typeof(T).fields`, typed code interface, data-layer vtable, memory layer, derived
JSON API. Spelling tells the tier (D3): `rz_x`/`RzX`/`RZ_X` app API, `rz__x`/`Rz_X`/
`RZ__X` internal or glue, `task_create`/`TaskList` generated app API, `Task__fields`
generated glue.

---

## D1. Declaration syntax and vehicle

**Chosen.** One rule: *a decorator only where code must be generated from a type;
everything else is a plain, type-checked call in the declaration function.* The
declaration function is the Ash Domain plus the Phoenix router: it lists every resource
and Signal the app mounts, explicitly, so rzpp never needs a whole-program view.

| Declares | Syntax | rzpp generates |
|---|---|---|
| route | `rz_get(app, "/healthz", &health);` also `rz_post/put/patch/delete`, `rz_route(app, verb, path, &h)` | nothing |
| static dir | `rz_static(app, "/static", "examples/tasks/public");` | nothing |
| middleware | `rz_use_logging(app); rz_use_cors(app, "*"); rz_use(app, "name", &mw);` call order = chain order; recover always first, body cap always last | nothing |
| config default | `rz_default(app, "port", "8070");` | nothing |
| channel | `rz_channel(app, "room:*", &room_join, &room_in, &room_leave);` | nothing |
| timer | `rz_every(app, 1000, &tick);` with `fn tick(n: int64)` | nothing |
| Signal | `@signal struct Todos` + `enum TodosMsg` + `todos_update`, `todos_view` (+ optional `todos_mount`, `todos_leave`); mount: `todos_signal(app, "/todos", HEAD);` | `todos_signal`, `todos_publish`, glue |
| resource | `@resource` + decorators on `struct Task`; mount: `task_json_api(app, "/api/tasks", dl);` | code interface, `TaskList`, `task_resource`, `task_json_api`, glue |
| view / message enum | `return html"""...""";` and `enum NameMsg` (unchanged, views.md §2, §7) | unchanged |

**Resource decorators.** On the lines above `struct`, several per line allowed.

| Decorator | Meaning | rzpp checks |
|---|---|---|
| `@resource` | first field must be `id: int64` (primary key, assigned by the layer) | field types are int32, int64, bool, string |
| `@required(f)` | string non-empty after trim | f exists, is a string |
| `@min_length(f, n)`, `@max_length(f, n)` | bytes after trim | string field, n >= 0 |
| `@create(f, ...)` | action create, accepting the fields (list may be empty) | fields exist, not id |
| `@read` | actions read (all), get (by id), count | |
| `@update(f, ...)` | action update, accepting the fields | fields exist, not id |
| `@destroy` | action destroy (by id) | |
| `@action(name, change_fn)` | custom update: load, run `fn change_fn(r: Task*)`, validate, store | fn exists with that signature; name snake_case, not a generated name |

Accepted strings are always trimmed (Ash's default). Unaccepted fields are zero on
create and keep their stored value on update. A resource with no action is an error.

**Signal decorator.** `@signal struct Todos` binds by the snake name (`Todos` → `todos`,
`ChatRoom` → `chat_room`): `enum TodosMsg`, `fn todos_update(s: Todos*, msg: TodosMsg)`,
`fn todos_view(s: Todos*) -> RzHtml*` required; `todos_mount`, `todos_leave` optional.
Topic `signal:todos`. Replaces today's search for update() by signature.

**Generated tail (shape).** Glue is `<Type>__<what>`; app-facing functions carry full
`///` contracts (D5) and are `export`ed when the struct is.

```mettle
struct TaskList { items: Task*; count: int32; }          // layout of RzRecords
var Task__fields: RzField[3];
var Task__def: RzResourceDef;
var Task__layer: RzDataLayer* = 0;                       // bound by task_json_api
fn Task__init_fields(out: RzField*) -> int32 {           // flux_orm's idiom: no globals
  var i: int32 = 0;                                      // inside the comptime body
  comptime for f in typeof(Task).fields {
    out[i].name = f.name; out[i].kind = f.type.kind;
    out[i].offset = (int32)f.offset; out[i].size = (int32)f.type.size; i = i + 1;
  }
  return i;
}
fn Task__change_toggle(rec: rawptr) { task_flip((Task*)rec); }   // typed wrapper, no fn casts
fn task_resource() -> RzResourceDef* { /* once: fields, rz__attr_required(&Task__def, 1),
  rz__attr_max_length(..., 1, 120), rz__action_create(..., RZ__FIELD_BIT(1)),
  rz__action_custom(..., "toggle", &Task__change_toggle), read, destroy */ }
fn task_create(dl: RzDataLayer*, title: string, id: int64*, errs: RzErrors*) -> int32 {
  var rec: Task;                                         // zeroed
  rec.title = title;
  return rz__create(dl, task_resource(), (rawptr)&rec, id, errs);
}
fn Task__api_create(ctx: RzContext*) -> int32 { return rz__api_create(ctx, Task__layer); }
fn task_json_api(app: RzApp*, base: string, dl: RzDataLayer*) {
  Task__layer = dl;
  rz__app_api(app, base, dl, task_resource());           // records the mount, checks dl->def
  rz__app_route(app, "POST", base, "", &Task__api_create); // ... one line per route
}
```

For `@signal struct Todos`: `Todos__mount/__view/__leave(state: rawptr)` and
`Todos__handle(state, name, value)` typed wrappers (replacing `(fn(rawptr) -> void)mount`
casts), `todos_signal(app, path, head)` → `rz__app_signal(app, "todos", path, head,
sizeof(Todos), &Todos__mount, &Todos__handle, &Todos__view, &Todos__leave)`, and
`todos_publish(topic: string, m: TodosMsg) -> bool` (any thread).

**Build-time diagnostics (AC D3).** `path:line: <what> — <fix>`, exit 1, first error
only, line of the decorator or declaration. One fixture per message: unknown rz
decorator ("did you mean @max_length?"); decorator not on a struct; unknown field (lists
the fields); unsupported field type; missing/misplaced `id: int64`; `@required` on a
non-string; missing `TodosMsg`/`todos_update`/`todos_view` (prints the signature to add);
change fn missing or mis-typed; generated name already declared (names both lines);
duplicate action; no actions. rzpp also checks literals it can see in the declaration
function: route patterns (`/a/:id/:id`), duplicate verb+path, unknown `rz_default` keys.
The rest is checked by `rz_run` before binding (D2).

**Multi-file apps.** `rzpp <entry.mettle>` (entry mode) processes the entry and every
local relative import containing rz decorators or `html"""`, writes `<name>.gen.mettle`
beside each (gitignored already), and rewrites `import "task";` to `import "task.gen";`
on the same line. `rzpp <in> <out>` stays for tests. Layout: `app.mettle` (declaration fn
+ main) plus one file per resource or Signal; decorated structs used across files are
`export`ed (rzpp says so if not).

**Forward path.** Generators are "text in, text out", as gen.mettle already is. When
`@generate` takes `args: string[]` (as layouts do) and can read sibling decorators, the
generators become `@resource`/`@signal` metafunctions with the same output; rzpp goes.
P7 adds this ask to docs/design/mettle-tagged-literals-request.md.

**Rejected.** A block DSL (`resource Task { ... }`): not Mettle, nothing checks it, no
path to native. App-written const tables (flux_orm `RcColumn[]`): manual counts, string
field names, two places per field (rzpp emits this form instead). Decorators for
routes/middleware on main: stringly handlers, no string args today, routes scatter.
Runtime generics (`rz_resource<T>`): lambdas cannot see T, no `&generic<T>`, inference
fails on field access. Comment annotations: invisible to the compiler forever. One giant
`@resource(...)`: unreadable.

**Consequences.** Every app goes through rzpp (one Makefile rule). Routes live in one
place. Decorator mistakes are build errors; plain-call mistakes are startup errors
unless rzpp sees a literal. rzpp must detect collisions with generated names.

**Falsifier.** In the slice: a type error in `task_flip` or a hole is not reported on its
own line after stripping; `comptime for` fails in a generated imported module even with
the parameter idiom; Mettle's metaobject design (`Mettle/docs/design/metaobject.md`)
rejects identifier args on `@generate`.

**Blast radius.** tools/rzpp (new deco/resource/signal modules, main), all examples,
Makefile. Must-test: line mapping, one fixture per diagnostic, debug and `--release`.

---

## D2. App entry point and lifecycle

**Chosen.** `rz_run(name: string, declare: fn(RzApp*) -> void) -> int32`, once per process:

1. **Record.** Create `RzApp`, call `declare(app)` on the main thread. Each declaration
   validates its arguments and records errors with its text; nothing listens, no thread
   starts. Anything returned by a function taking `RzApp*` is owned by the app.
2. **Config.** framework defaults < `rz_default` < `RAIZE_*` env < `--port N` (argv, read
   from `/proc/self/cmdline` as tasks does now; the only flag). Keys = env names without
   `RAIZE_`, lowercase (`max_body_bytes`). This reverses today's "program set beats env"
   so operators can always override. Validate, freeze.
3. **Report.** Any error → print each as `tasks: <what> — <fix>` (`tasks: RAIZE_PORT=
   "notaport" is not a port 1..65535 — set it to a number or unset it`); return **1**.
4. **Derive.** Hub + one channel router only if a channel or Signal exists. Routes:
   declared, `/socket/websocket` (channels), `/signal/websocket` + `/rz/signal.js`
   (Signals), Signal pages, `<prefix>/*path` per static dir (root must exist, else error,
   return 1), JSON APIs. Chain: recover → declared middleware → body cap (413) → router.
5. **Start.** Hub, timers, listener. Bind failure: `tasks: cannot listen on :8080 (address
   in use) — stop the other process or pass --port N`, return **2**.
6. Print `tasks: listening on 127.0.0.1:<port>` (tests wait for "listening").
7. **Stop.** Join timers, stop server and hub, free app-owned objects in reverse; return
   0 or the server's code.

Threads: `declare` runs once, before any other thread, and globals it sets (`g_tasks`) are
read-only afterwards. Handlers run on workers; channel/Signal callbacks on the hub
thread; `rz_every` callbacks on their own thread, calling only any-thread APIs
(`*_publish`, `rz_broadcast`, data-layer functions).

**Rejected.** Explicit builder (`rz_app_new/start/wait`): hands ordering and error checks
back to the app (today's main with 17 exit codes). `rz_run(argc, argv, ..)`: two
spellings of main exist now; /proc works for both. Positional port: two ways; `--port`
wins (chat.sh, signal.sh change one line). App code beating env: blocks operators.
Serving a partly declared app: worse than exit 1.

**Consequences.** framework/config gains the app-defaults layer; `rz_config_set` goes
internal; exit codes 0/1/2 are a contract. Static dirs are cwd-relative; the
`../examples/...` fallback is deleted, and the error says where it looked. Config keys
nothing honours (`static_root`, `template_root`, `bind_addr`, `store_dsn`) are removed.

**Falsifier.** config.sh fails on precedence or on naming RAIZE_PORT; an app needs a hook
between bind and serve; `/proc/self/cmdline` unreadable in the runner.

**Blast radius.** framework/app (new), config, server (bind error), middleware facades,
all mains. Must-test: config.sh, a fixture per startup error class and exit code, leak.sh.

---

## D3. Public API surface vs internals

**Chosen.**
- **Facade** `raize.mettle` at the repo root: no exports, imports `std/io`, `std/mem` and
  one part-module per area (`framework/app/app`, `framework/resource/resource`, ...). A
  module with no exports re-exports its imports, so `import "raize";` is the whole API
  (AC D1). It resolves from the working directory (builds run from the root); outside
  the repo, build with `-I <raize_web>` and write the same line.
- **Naming is the classification** (a flat namespace has no visibility): app API
  `rz_<area>_<verb>`, `Rz<Noun>`, `RZ_<NAME>`; internal/glue `rz__...`, `Rz_...`,
  `RZ__...`. Both pass the lint prefix rule. `raize_*`/`Raize*` become `rz_*`/`Rz*` (P1).
- **Telling them apart:** the spelling at the call site; the reference lists app API
  only; every internal doc starts `/// internal: <callers>`; lint fails when hand-written
  code under `examples/` names an internal (fixtures and `*.gen.mettle` exempt). That
  also enforces AC I5: hub, poll, server, router, chain and ws are internal entirely.

Public surface (~110 symbols; P3 fixes exact parameters within these lines):

| Reference page | App API |
|---|---|
| app | `RzApp`, `rz_run`, `rz_default`, `rz_get/post/put/patch/delete`, `rz_route`, `rz_static`, `rz_use`, `rz_use_logging`, `rz_use_cors`, `rz_use_headers`, `rz_use_bearer_auth`, `rz_channel`, `rz_every`, `rz_mem_layer` |
| handlers | `RzContext`, `rz_ctx_text/html/json/view/empty/redirect/not_found` (return the status they set), `rz_ctx_param`, `rz_ctx_param_int`, `rz_ctx_query`, `rz_ctx_query_int`, `rz_ctx_header`, `rz_ctx_body`, `rz_ctx_json_str/int/bool`, `rz_ctx_scratch` |
| json | `rz_json_get_str/int/bool/raw`, `rz_json_has`, `rz_json_quote(arena, s)` |
| views-signals | `RzHtml`, `rz_raw`, `rz_signal_subscribe`, `rz_signal_scratch` (was `rz_signal_arena`) |
| channels | `RzChanCtx`, `rz_chan_topic`, `rz_chan_state`, `rz_chan_set_state`, `rz_chan_scratch`, `rz_chan_reply_json`, `rz_chan_refuse`, `rz_chan_push`, `rz_chan_broadcast` (hub thread), `rz_broadcast(topic, event, json)` (any thread) |
| resources | `RzResourceDef`, `RzErrors`, `rz_error_text`, `rz_errors_clear`, `rz_errors_count`, `rz_mem_layer_new`, `rz_data_layer_free` |
| data-layers | `RzDataLayer`, `RzField`, `RzRecords`, `rz_field_get_*/set_*`, `rz_record_copy_into` |
| status | `RZ_OK`, `RZ_E_*`, `rz_status_text`, `rz_status_http` |
| strings | `RzBuf`, `rz_buf_new/add/add_int/str/free`, `RzArena`, `rz_arena_new/free`, `rz_str_eq/trim/dup/free/empty/to_int/from_c/starts/ends/find` |
| templates | `RzTemplate`, `rz_template_*`, `RzVarMap`, `rz_vars_*` (files rendered at runtime; views are the canonical markup path) |

Everything else is internal: server, router, hub, poll, ws, chain, static and config
internals, channel members/wire, signal inst and html-node glue, resource glue, rzpp.

**Rejected.** Document-only separation: call sites still read `rz_server_new`, the name
a model will type. `import "x" as n` inside the framework: generated glue in app files
needs global names, and generics/traits through aliases are unverified here. A separate
public prefix: AC keeps rz_, and public names should be the short ones. Per-area
imports: AC D1.

**Consequences.** P1 and P5 are scripted repo-wide renames (mappings under .apex/). New
code uses final names from P2 on. Fixtures keep using internals.

**Falsifier.** `Rz_Name` or `rz__name` misparse or collide (P2 runs a 10-line probe); a
public symbol cannot be documented without naming an internal type (then it is public).

**Blast radius.** every file. Must-test: integration after each rename; examples lint.

---

## D4. Resources

**Chosen.** Declared per D1. Code interface (snake `task`, `dl` = data layer):

| Decorator | Function | Contract |
|---|---|---|
| always | `task_resource() -> RzResourceDef*` | static lifetime; first call during declaration |
| `@create(title)` | `task_create(dl, title: string, id: int64*, errs: RzErrors*) -> int32` | `*id` = new id; `id` may be 0 |
| `@read` | `task_read(dl, arena: RzArena*) -> TaskList` | all records, id order, copied into arena |
| `@read` | `task_get(dl, id: int64, out: Task*, arena) -> int32` | `RZ_E_NOT_FOUND`; strings in arena |
| `@read` | `task_count(dl) -> int32` | |
| `@update(title)` | `task_update(dl, id, title: string, errs) -> int32` | sets every accepted field |
| `@destroy` | `task_destroy(dl, id, errs) -> int32` | |
| `@action(toggle, task_flip)` | `task_toggle(dl, id, errs) -> int32` | |
| any | `task_json_api(app, base: string, dl)` | once per resource |

Accept-list parameters follow declaration order with the field's type. `errs` may be 0
and is reset on entry.

**Status (framework/core/status.mettle).** `RZ_OK = 0`; errors are negative, so never an
HTTP status: `RZ_E_USAGE -1` (misuse, nothing changed), `RZ_E_INVALID -2`,
`RZ_E_NOT_FOUND -3`, `RZ_E_CONFLICT -4`, `RZ_E_FULL -5`, `RZ_E_NOMEM -6`,
`RZ_E_UNSUPPORTED -7`, `RZ_E_DATA_LAYER -8`, `RZ_E_IO -9`; `rz_status_text`,
`rz_status_http`. Router, config and template detail codes map onto these at their
public boundary.

```mettle
export struct RzFieldError { field: string; text: uint8[64]; len: int32; }  // field: static name
export struct RzErrors { code: int32; count: int32; items: RzFieldError[8]; }
```

Messages are formatted inline ("can't be blank", "is too long (at most 120)"), so
`RzErrors` owns nothing and can live in Signal state; `rz_error_text(errs, "title")`
returns the message or "" (view into errs). Not `Result<T, E>`: struct payloads in
generic enums are unverified, enums by value through indirect calls ICE, and flux_orm
uses int32 + out-params; one convention across the ecosystem.

**Data layer (framework/resource/layer.mettle).**

```mettle
export struct RzRecords { items: rawptr; count: int32; }        // arena-backed
export struct RzDataLayer {
  name: string;                                                 // "memory"
  ud: rawptr;                                                   // the layer's state
  def: RzResourceDef*;                                          // the one resource stored
  insert: fn(rawptr, rawptr, int64*) -> int32;                  // (ud, rec, out id)
  get: fn(rawptr, int64, rawptr, RzArena*) -> int32;            // (ud, id, out rec, arena)
  modify: fn(rawptr, int64, fn(rawptr, rawptr) -> int32, rawptr, RzArena*) -> int32;
                                                                // atomic read-apply-write
  remove: fn(rawptr, int64) -> int32;
  scan: fn(rawptr, RzRecords*, RzArena*) -> int32;              // all, id order
  count: fn(rawptr) -> int32;
  close: fn(rawptr) -> void;
}
```

- Records cross as `rawptr` to a struct described by `def` (`RzField`: name, kind,
  offset, size, flags, min/max length): typed load/store by kind at compiler-reported
  offsets, as flux_orm's `RcField`.
- **Ownership:** inputs are borrowed for the call; the layer copies what it keeps and
  frees its copies on remove/modify/close; get/scan copy into the caller's arena
  (`rz_ctx_scratch(ctx)` in handlers, `rz_signal_scratch()` in Signals, reset after the
  event's diff). The layer never hands out views into its storage.
- **Threads:** every op is any-thread (memory layer: one spin lock per layer). `modify`
  runs `apply`, and so the change fn, inside the critical section: change fns do plain
  field edits and call nothing in raize.
- **Compiler limits:** only pointers and int64 cross the vtable (no string literals or
  enums by value); vtables are heap-built in an `@noinline` constructor with every slot
  set (unsupported → stub returning `RZ_E_UNSUPPORTED`), per flux_orm's release finding.
- **flux_orm fit:** `RzField` ↔ `RcField` (kind → `RC_T_*`, id → `RC_F_PK|RC_F_AUTO`,
  required → `RC_F_NOT_NULL`); insert/get/remove/scan ↔ `rc_repo_insert/get/delete/all`;
  modify ↔ `RC_TX_IMMEDIATE` begin, get, apply, update changed fields, commit;
  `RC_ERR_NOT_FOUND/CONFLICT/NOMEM` → `RZ_E_*`, others `RZ_E_DATA_LAYER`. A later
  `rz_flux_layer_new(session, def)` needs no interface change.
- Filtering stays in app code over `task_read`; query pushdown waits for a real store (O1).

**Memory layer:** `rz_mem_layer_new(def, capacity)` (caller frees, `rz_data_layer_free`)
and `rz_mem_layer(app, def, capacity)` (app-owned). Fixed capacity, ids from 1 per
layer, insertion order, `RZ_E_FULL` when full.

**Derived JSON API** (`task_json_api(app, "/api/tasks", dl)`):

| Action | Route | Success | Errors |
|---|---|---|---|
| read | `GET /api/tasks` | 200 `[{"id":1,"title":"..","done":false}]` | |
| read | `GET /api/tasks/:id` | 200 record | 400 `{"error":"bad id"}`, 404 `{"error":"not found"}` |
| create | `POST /api/tasks` | 201 record | 400 `{"error":"invalid","fields":{"title":"can't be blank"}}`, 400 `{"error":"body is not a JSON object"}`, 409 `{"error":"full"}` |
| update | `PATCH /api/tasks/:id` | 200 record (absent keys keep stored values) | 400, 404 |
| custom | `POST /api/tasks/:id/toggle` | 200 record | 400, 404 |
| destroy | `DELETE /api/tasks/:id` | 204 | 404 |

Keys in struct order; unknown body keys ignored; 405/413 come from router and body cap;
500 is `{"error":"internal"}` with no details.

**Signals and forms.** State holds `errors: RzErrors`; the action gets `&s->errors`; the
view shows `{rz_error_text(&s->errors, "title")}`; the draft clears only on success. A
view reads its data (`todo_read(s->todos, rz_signal_scratch())`). Per-page data: a layer
made in mount, freed in leave. Shared data: an app layer in a global.

**Rejected.** begin/commit in the vtable (lock re-entry and tx state leak to callers;
`modify` covers it); scan visitors (lock held across user code); out records that view
the store (races); per-field generated codecs (kept as fallback); Ash-style implicit
store (hides which store, blocks per-page data).

**Consequences.** framework/resource is new (~7 files under 400 lines). tasks loses its
store, JSON and handlers; todos keeps per-page state (signal.sh semantics hold) and gains
visible validation.

**Falsifier.** offset string load/store or comptime offsets wrong under `--release`;
leak.sh grows; tasks.sh's `"id":1`, trim, 400/404/204 checks fail; vtable calls ICE.

**Blast radius.** framework/resource, core/status, router codes, rzpp resource generator,
tasks, todos. Must-test: tasks.sh, http_edges.sh, leak.sh, signal.sh, a unit test of
every validation and status mapping.

---

## Target developer experience

### examples/todos/app.mettle (258 → ~110 lines; CSS moves to head.html)

```mettle
// examples/todos — a Signal backed by a resource. GET /todos renders on the server,
// then the page is live over /signal/websocket. Each page has its own list (a memory
// layer per page). A timer publishes Tick(n) every second; Nudge reaches every page
// subscribed to "todos:nudges", the sender included.
// Run from the repository root:  make todos && ./build/todos --port 8070

import "raize";

const TODO_CAPACITY: int32 = 32;
const PAGE_HEAD: string = import_str "head.html";   // <title> and <style>

@resource
@required(title) @max_length(title, 80)
@create(title) @read @destroy
@action(toggle, todo_flip)
struct Todo {
  id: int64;
  title: string;
  done: bool;
}

fn todo_flip(t: Todo*) { t->done = !t->done; }

@signal
struct Todos {
  todos: RzDataLayer*;   // this page's list; made in mount, freed in leave
  draft: string;         // the input's text; owned
  errors: RzErrors;      // from the last Add
  uptime: int32;         // seconds, from Tick
  nudges: int32;         // Nudged messages received
}

// From the page: Draft..ClearDone, Nudge. From the server: Tick, Nudged.
enum TodosMsg { Draft(string), Add, Toggle(int64), Remove(int64), ClearDone, Nudge, Tick(int32), Nudged(int32) }

fn todos_mount(s: Todos*) {
  rz_signal_subscribe("todos:nudges");
  s->todos = rz_mem_layer_new(todo_resource(), TODO_CAPACITY);
  todo_create(s->todos, "Write a Signal", 0, 0);
  todo_create(s->todos, "Ship it", 0, 0);
}

fn todos_update(s: Todos*, msg: TodosMsg) {
  match (msg) {
    case Draft(text): { set_draft(s, text); }
    case Add: {
      if (todo_create(s->todos, s->draft, 0, &s->errors) == RZ_OK) { set_draft(s, ""); }
    }
    case Toggle(id): { todo_toggle(s->todos, id, 0); }
    case Remove(id): { todo_destroy(s->todos, id, 0); }
    case ClearDone: { clear_done(s); }
    case Nudge: { todos_publish("todos:nudges", Nudged(1)); }
    case Tick(n): { s->uptime = n; }
    case Nudged(k): { s->nudges = s->nudges + k; }
  }
}

fn todos_leave(s: Todos*) {
  rz_data_layer_free(s->todos);
  set_draft(s, "");
}

fn set_draft(s: Todos*, text: string) {
  rz_str_free(s->draft);           // no-op on the empty string
  s->draft = rz_str_dup(text);
}

fn clear_done(s: Todos*) {
  var list: TodoList = todo_read(s->todos, rz_signal_scratch());
  for i in 0..list.count {
    if (list.items[i].done) { todo_destroy(s->todos, list.items[i].id, 0); }
  }
}

// open_count(list: TodoList), todo_class(t: Todo) and empty_state(message) are
// today's helpers, reading a TodoList instead of the state's array.

fn todos_view(s: Todos*) -> RzHtml* {
  var list: TodoList = todo_read(s->todos, rz_signal_scratch());
  return html"""
    <main>
      <h1>Todos <small>{open_count(list)} open</small></h1>
      <form on:submit={Add}>
        <input name="title" value={s->draft} on:input={Draft} placeholder="What needs doing?" autocomplete="off">
        <button>Add</button>
      </form>
      <p class="error">{rz_error_text(&s->errors, "title")}</p>
      {if list.count == 0 {
        <.empty_state message="Nothing to do." />
      } else {
        <ul>
          {for i in 0..list.count {
            <li class={todo_class(list.items[i])}>
              <button class="check" on:click={Toggle(list.items[i].id)}>{list.items[i].title}</button>
              <button class="remove" on:click={Remove(list.items[i].id)} aria-label="Remove">×</button>
            </li>
          }}
        </ul>
        <button class="clear" on:click={ClearDone}>Clear done</button>
      }}
      <footer>...today's footer: {s->uptime}, on:click={Nudge}, {s->nudges}...</footer>
    </main>
  """;
}

fn tick(n: int64) { todos_publish("todos", Tick((int32)n)); }

fn todos_app(app: RzApp*) {
  rz_default(app, "port", "8070");
  todos_signal(app, "/todos", PAGE_HEAD);
  rz_every(app, 1000, &tick);
}

fn main() -> int32 { return rz_run("todos", &todos_app); }
```

rzpp.sh's line-mapping check moves from `^const STYLE` to `^fn todos_app`.

### examples/tasks/app.mettle (505 → ~65 lines; templates/ deleted)

```mettle
// examples/tasks — a JSON API derived from a resource, a page and static files.
//   GET /  page · GET /healthz · GET|POST /api/tasks · GET|DELETE /api/tasks/:id
//   POST /api/tasks/:id/toggle · GET /static/*path (ETag, 304)
// Run from the repository root:  ./build/tasks [--port N]   (RAIZE_* variables apply)

import "raize";

const TASK_CAPACITY: int32 = 64;

@resource
@required(title) @max_length(title, 120)
@create(title) @read @destroy
@action(toggle, task_flip)
struct Task {
  id: int64;
  title: string;
  done: bool;
}

fn task_flip(t: Task*) { t->done = !t->done; }

var g_tasks: RzDataLayer* = 0;   // set by tasks_app before the first request

fn index_view(count: int32) -> RzHtml* {
  return html"""
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><title>raize tasks</title>
      <link rel="stylesheet" href="/static/style.css"></head>
    <body><main>
      <h1>raize tasks</h1>
      <p class="count">Store: <strong id="count">{count}</strong> / 64 tasks</p>
      <!-- form#new-task, #status, ul#tasks, footer: as in today's templates/index.html -->
    </main><script src="/static/app.js"></script></body></html>
  """;
}

fn index(ctx: RzContext*) -> int32 {
  return rz_ctx_view(ctx, 200, index_view(task_count(g_tasks)));
}

fn health(ctx: RzContext*) -> int32 {
  return rz_ctx_json(ctx, 200, "{{\"status\":\"ok\",\"tasks\":{task_count(g_tasks)},\"capacity\":{TASK_CAPACITY}}");
}

fn tasks_app(app: RzApp*) {
  rz_use_logging(app);
  rz_use_cors(app, "*");
  rz_static(app, "/static", "examples/tasks/public");
  rz_get(app, "/", &index);
  rz_get(app, "/healthz", &health);
  g_tasks = rz_mem_layer(app, task_resource(), TASK_CAPACITY);
  task_json_api(app, "/api/tasks", g_tasks);
}

fn main() -> int32 { return rz_run("tasks", &tasks_app); }
```

tasks.sh still holds: "raize tasks", `id="count">0<`, every API status and body.
rzpp learns `<!doctype ...>` and `<!-- -->` as static text (P3-C).

### examples/chat/app.mettle (180 → ~55 lines; excerpt)

```mettle
import "raize";

const PAGE: string = import_str "index.html";
struct ChatMember { name: string; }   // owned; freed in room_leave

fn room_join(ctx: RzChanCtx*, payload: string) -> int32 {
  if (rz_str_eq(rz_chan_topic(ctx), "room:secret")) { return rz_chan_refuse(ctx, "unauthorized"); }
  var a: RzArena* = rz_chan_scratch(ctx);
  var user: string = rz_str_empty();
  if (!rz_json_get_str(payload, "user", &user, a) || user.length == 0 || (int64)user.length > 32) { user = "anon"; }
  var m: ChatMember* = new ChatMember;
  m->name = rz_str_dup(user);
  rz_chan_set_state(ctx, (rawptr)m);
  return rz_chan_reply_json(ctx, "{{\"room\":{rz_json_quote(a, rz_chan_topic(ctx))}}");
}
// room_in: ping -> rz_chan_reply_json; whoami -> rz_chan_push(ctx, "you", ..);
// new_msg -> rz_chan_broadcast(ctx, "new_msg", "{{\"user\":{q(name)},\"body\":{q(body)}}");
// anything else -> return rz_chan_refuse(ctx, "unknown event");
fn lobby_tick(n: int64) { rz_broadcast("room:lobby", "tick", "{{\"n\":{n}}"); }
fn index(ctx: RzContext*) -> int32 { return rz_ctx_html(ctx, 200, PAGE); }

fn chat_app(app: RzApp*) {
  rz_default(app, "port", "8090");
  rz_get(app, "/", &index);
  rz_channel(app, "room:*", &room_join, &room_in, &room_leave);   // -> /socket/websocket
  rz_every(app, 200, &lobby_tick);
}

fn main() -> int32 { return rz_run("chat", &chat_app); }
```

Channel callbacks return `RZ_OK` to reply "ok"; anything else replies "error" with the
body set by `rz_chan_refuse` (`{"reason":..}`).

---

## D5. Documentation standard

**Chosen.** `///` lines directly above each export (a plain line comment to the compiler):

```mettle
/// Declares a GET route. The handler runs on a worker thread for each request whose
/// path matches `pattern` (`/tasks/:id`, `/static/*path`).
///
/// in:      app      the app being declared (from rz_run)
///          pattern  borrowed; copied into the app
///          handler  returns the HTTP status it set (every rz_ctx_* returns it)
/// returns: nothing; a bad or duplicate pattern is reported by rz_run at startup
/// owns:    nothing kept from the caller
/// thread:  the declaration function only (main thread, before serving)
/// example:
///   rz_get(app, "/tasks/:id", &show_task);
export fn rz_get(app: RzApp*, pattern: string, handler: fn(RzContext*) -> int32) { ... }
```

`tests/doccheck.sh` (bash/awk, in `make lint`, AC I6) enforces:

| Export | Required |
|---|---|
| any | a `///` block directly above; first line is the summary sentence |
| fn | `in:` naming every parameter; `returns:` listing every `RZ_E_*` (or "nothing"); `owns:` if the signature has `string`, `*`, `rawptr`, `cstring`; app API also `thread:` and `example:` (`example: -` only for one-line getters) |
| struct, trait | summary; every field line has a trailing `//` comment (ownership for strings/pointers) |
| const, enum | summary, or a trailing `//` comment on the line |
| internal | first line `/// internal: <calling modules>. <summary>`; `owns:` rule applies; no example |

Each framework file starts `// raize/<area> — <purpose>`, then `// reference: <page>`
(or `internal`), then its thread rule. rzpp writes the same contracts on generated
app-facing functions, so a `.gen.mettle` documents itself.

**Reference.** `tools/rzdoc.sh` (bash/awk) writes `docs/reference/README.md` (every app
API symbol and summary) and one page per D3 area: signature block, then the doc block.
`docs/reference/generated.md` is hand-written (each decorator, what it generates, the
contracts). `make docs` regenerates; `make lint` runs `tools/rzdoc.sh --check` (stale
docs fail). Markdown only (AC O4).

**Guide** `docs/guide.md`: 1 build and run the examples; 2 a first app; 3 config, env,
`--port`, startup errors; 4 handlers, `RzContext`, JSON in and out; 5 static files and
middleware; 6 views; 7 resources (declare, code interface, JSON API, errors); 8 data
layers (memory, ownership, writing one); 9 Signals (state, messages, forms with
`RzErrors`, pushes); 10 channels; 11 timers and threads; 12 multi-file apps; 13 rzpp
diagnostics and reading `.gen.mettle`; 14 testing an app; 15 strings and memory rules.
Each chapter ends with links to the reference pages it used.

**Rejected.** Free-text `//` (unparseable); a doc tool in Mettle (bash/awk matches
tests/lint.sh, no build step); HTML (O4); docs from tests (no contracts).

**Consequences.** ~110 app API docs with examples, ~670 internal one-liners. doccheck
lands in warn mode (P5) and becomes failing in P7.

**Falsifier.** doccheck misparses signatures (then require one-line `export fn`
signatures, as the code already does); reviewers find `example: -` on non-trivial APIs.

**Blast radius.** every export, Makefile lint/docs, docs/. Must-test: doccheck fails on a
fixture with an undocumented export and passes on the tree.

---

## D6. Readability rules (every build agent)

1. **Names.** `rz_<area>_<verb>[_<object>]`, `Rz<Noun>`, `RZ_<AREA>_<NAME>`; internal per
   D3. Predicates read as questions (`rz_req_is_json`). Locals say what they hold; short
   names allowed: `ctx`, `req`, `resp`, `buf`, loop `i`/`k`, `s` (Signal state), `dl`.
2. **Size.** Files ≤ 400 product lines (lint). Functions ≤ 60 lines, ≤ 6 parameters
   (doccheck warns; parsers and generated code may say `// lint: long (reason)`).
3. **Errors.** Fallible → `int32` `RZ_OK`/`RZ_E_*`; constructors → pointer or 0;
   predicates → bool; lookups → empty string when absent; index searches → -1.
   Handlers `return rz_ctx_*(...)`. No `println` + exit codes outside `rz_run`. Every
   message says what to do.
4. **Ownership** is written where a string or pointer crosses a function (`owns:`) and on
   struct fields (`// owned`, `// borrowed until ..`). `rz_str_free("")` is a no-op;
   `rz_str_dup("")` returns the empty string without allocating.
5. **Comments** say why; D5 header on every file; no commented-out code; no stale status
   lines (views.md's "Nothing is built yet"); named char codes (`CH_QUOTE`), not `34`.
6. **Globals** only for state published before workers start: `g_<what>` + lifetime.
7. **Generated code** reads like hand-written code: one statement per line, `///` on
   app-facing functions, glue `<Type>__<what>`.
8. **New code uses final names.** Renames only in P1/P5, scripted, mapping committed.

Inconsistencies to fix: `raize_` vs `rz_` (P1); three status vocabularies plus ad hoc
-1/bool (P1 router, P3 config/template boundaries); `json_status`/`respond_json` because
`rz_ctx_*` does not return the status (P1); middleware's new/use/chain_add triple (P3-A);
positional port vs `--port` and asset-path fallbacks (P4); app-facing `TodosMsg__signal`/
`__publish` and `rz_signal_arena` (P3-C); fn-type casts in signal registration (P3-C);
router trie's 43 and config types' 86 exports (P5: internal or private); tasks'
`task_dup` (P4, deleted with the store); rzpp's bare ASCII codes (P6-G3); dead config
keys (P3-A).

---

## D7. Sequencing

Every phase ends with `make integration` green in debug plus a `--release` build and run
of what it touched. Parallel = disjoint files and no change to an interface another
writer uses; at most 3 writers.

| Phase | W | Owns | Done when |
|---|---|---|---|
| **P1** one prefix, one status | 1 | whole tree: scripted `raize_`→`rz_`, `Raize`→`Rz` (.apex/renames-p1.tsv, collision check first); framework/core/status.mettle; router codes; `rz_ctx_*` return the status; lint drops `raize_` | integration green; release tasks + todos run |
| **P2** DRAFT SLICE | 1 | raize.mettle; framework/app/{app,types,declare,run} (rz_run, rz_get/post, rz_default, recover + body cap, Signal and API mounts); framework/resource/{resource,def,errors,layer,mem,action,api} (create/read/get/count/destroy/custom, required/max_length); tools/rzpp/{deco,resource,signal} + main dispatch (single-file); tests/fixtures/app/slice/{app.mettle,test.sh}; tests/integration/apps.sh (runs every fixtures/app/*/test.sh); generic Makefile rules (every example and fixture app via rzpp); data-driven rzpp.sh (`// expect: <line>: <text>` in each bad fixture) + bad_resource_field; the naming probe | slice test passes, debug and release |
| GATE | | | orchestrator checks the slice against D1–D4 |
| **P3** finish layers | 3 | **A** framework/app (static, rz_use_*, channels, timers, full config precedence, startup errors, exit codes), middleware facades, channel accessors + rz_chan_refuse + rz_broadcast, config app-defaults + dead keys, Makefile, fixtures/app/startup. **B** framework/resource (update/PATCH, min_length, all statuses, rz_error_text), rzpp/resource.mettle, fixtures/rzpp/bad_resource_*, fixtures/app/resource, tests/unit/resource_test.mettle. **C** framework/signal (scratch rename, page via app), rzpp/{signal,gen,msg,src,main} (entry mode, import rewrite, `<!doctype>`, generated names), fixtures/rzpp/bad_signal_*, fixtures/app/multi | own fixtures pass; old examples still build (old API kept) |
| **P4** examples | 3 | **tasks** examples/tasks/**, tasks.sh, http_edges.sh, leak.sh, config.sh. **chat** examples/chat/**, chat.sh. **todos** examples/todos/** (+head.html), signal.sh, signal_client.py, rzpp.sh mapping check | examples match the targets; app APIs with no callers left deleted |
| **P5** internals | 1 | whole tree: classify, rename to `rz__`/`Rz_`/`RZ__` (.apex/renames-p5.tsv), privatize single-module exports, delete dead code, "no internals in examples/" lint, doccheck.sh in warn mode | integration green; lint clean |
| **P6** readability + docs | 3 | **G1** framework/{app,resource,core,context,str}, raize.mettle. **G2** framework/{signal,channel,hub,poll,ws,server}. **G3** framework/{router,middleware,static,template,config}, tools/rzpp | D6 applied; doccheck clean on own dirs |
| **P7** reference + guide | 1 | doccheck failing mode, tools/rzdoc.sh, docs/reference/**, docs/guide.md, README.md, views.md/realtime.md updates, compiler asks | lint enforces coverage and fresh docs |
| FINAL GATE | | | AC S1–S6, I1–I6, D1–D3 checked one by one |

**Draft slice** (P2), `tests/fixtures/app/slice/app.mettle`:

```mettle
import "raize";
@resource
@required(text) @max_length(text, 40)
@create(text) @read @destroy
@action(pin, note_pin)
struct Note { id: int64; text: string; pinned: bool; }
fn note_pin(n: Note*) { n->pinned = true; }

@signal
struct Counter { n: int32; }
enum CounterMsg { Inc, Dec }
fn counter_update(s: Counter*, msg: CounterMsg) {
  match (msg) { case Inc: { s->n = s->n + 1; } case Dec: { s->n = s->n - 1; } }
}
fn counter_view(s: Counter*) -> RzHtml* {
  return html"""<p>{s->n}</p><button on:click={Inc}>+</button>""";
}

fn slice_app(app: RzApp*) {
  rz_default(app, "port", "8075");
  note_json_api(app, "/api/notes", rz_mem_layer(app, note_resource(), 8));
  counter_signal(app, "/counter", "");
}
fn main() -> int32 { return rz_run("slice", &slice_app); }
```

`test.sh`: POST valid → 201 `"id":1`, text trimmed; POST `{}` → 400
`"fields":{"text":"can't be blank"}`; 41 bytes → 400; GET /1 → 200, /999 → 404, /abc →
400; POST /1/pin → `"pinned":true`; DELETE → 204, again 404; list `[]`; GET /counter has
`<p>0</p>`; a Python client joins `signal:counter`, sends `Inc`, gets a diff with 1;
`RAIZE_PORT=x` exits 1 naming the variable; a bad fixture `@max_length(txt, 40)` reports
its line and the field list. This crosses every risky seam once: decorator stripping
with stable lines, comptime metadata in generated code, offset-based records through a
vtable, arena copies, the generic JSON API, `@signal` by convention beside a resource in
one file, and `rz_run` deriving hub, socket and routes, in debug and release.

**Rejected.** Examples first (risk proven last); renames last (every phase writes against
names about to change); a single writer (serial where disjoint work exists).

**Consequences.** Old app-facing APIs coexist with new ones from P2 to P4, so every
commit stays green; P4 deletes what lost its last caller.

**Falsifier.** A P3 writer needs another's interface changed (serialize that pair); the
P5 rename breaks something the mapping missed (word-bounded regex, collision check first).

**Blast radius.** As listed per phase.

---

## Risks not resolved

1. Decorator forward-compatibility rests on compiler features that do not exist yet
   (`@generate` args, sibling-decorator access, `@generate` on enums for `NameMsg`). The
   syntax matches layout-decorator arguments, which parse today; rzpp carries it until then.
2. Mistakes in plain declaration calls (route typos, static dirs) are startup errors,
   not build errors, unless rzpp sees a literal. AC D3 is met fully for decorators and
   partly for calls; a bad app still never serves.
3. Release-mode miscompiles around vtables and offset loads (flux_orm hit one). The
   slice must pass `--release` before P3; fallback is generated per-field accessors.
4. A type error inside a view hole still points at the `return html"""` line (views.md §7).

## Findings (P2)

Recorded by the P2 build agent, 2026-11-04. Compiler: ./mettle-build/bin/mettle.

1. **D3 naming probe: holds.** `struct Rz_Name`, `fn rz__name`, `const RZ__NAME` and glue
   `fn Note__init` parse beside `RzName`/`rz_name`/`RZ_NAME` in one module, with no
   collision, debug and `--release` (output identical). No fallback needed.
2. **D1/D4 falsifiers: none fired.** `comptime for f in typeof(Note).fields` inside a
   generated, non-generic fn with an out-param; `f.type.kind` passed as `Kind`; typed
   load/store at compiler offsets (string, int64, int32, bool); a heap vtable built in an
   `@noinline` constructor, including `modify`'s nested fn-type parameter
   `fn(rawptr, int64, fn(rawptr, rawptr) -> int32, rawptr, RzArena*) -> int32`: all
   correct in debug and `--release` (slice test 20/20 both). Per-field accessors not needed.
3. **D7 slice text, plain enum.** `enum CounterMsg { Inc, Dec }` has no payload, so it is a
   plain enum and `match` rejects it (E0003 "match expression must be a tagged enum type"),
   both in `counter_update` and in rzpp's generated `CounterMsg__json`. The fixture adds
   `Set(int32)`. P3-C: rzpp should either emit `switch` with `CounterMsg.Inc` for
   payload-less message enums or report "add a payload variant" at the enum's line.
4. **D7 slice text, name collision.** `@action(pin, note_pin)` generates `note_pin(dl, id,
   errs)` (D4's `<snake>_<action>`), which collides with the change fn itself. rzpp reports
   it ("generates fn note_pin, but line N already declares it"); the fixture uses
   `@action(pin, note_set_pinned)`. Guide/examples: never name a change fn `<snake>_<action>`
   (the tasks/todos targets, `task_flip`/`todo_flip`, are fine).
5. **Bind vs serve.** `rz_server_run` binds internally, so `rz_run` probes the port with
   `rz_listen` + `rz_listener_close` before printing "listening" (exit 2 on failure) and
   still maps a later `rz_server_run` -1 to exit 2. P3-A: split bind from serve in
   framework/server so the probe (and its small race) goes away.
6. **`rz_str_free(rz_str_empty())` aborts** ("free() of a pointer that malloc() did not
   return"): `rz_str_empty()` views the literal `""`, whose chars are not null. D6 rule 4
   ("`rz_str_free("")` is a no-op, `rz_str_dup("")` does not allocate") is not true today;
   new code guards with `length > 0`. P6-G1 should make both rules true in framework/str.
7. **Exported globals vs lint.** `export var g_x` fails the prefix rule, so module state
   other modules need is reached through `rz__app_current()` / `rz__app_set_current()`.
8. **Deviations, small.** (a) The Signal handle wrapper is msg.mettle's existing
   `CounterMsg__handle` (D1 says `Counter__handle`); P3-C may rename. (b) `RzAction` is a
   public struct because public `RzResourceDef` embeds it (D3 falsifier rule). (c) The memory
   layer's `modify` applies the change to an arena copy and stores that copy's strings on
   RZ_OK; the result is handed back through the apply arg, so callers without an arena
   (generated `note_pin`) get a temporary one. (d) Config messages keep config's own text
   (`RAIZE_PORT: not a number or out of range: "x" (allowed 1..65535) — set the variable to
   an allowed value or unset it`), not D2's exact wording; P3-A polishes. (e) rzpp single-file
   mode only; `@update`/`@min_length` are recognised but reported "not supported yet" (P3-B).

## Amendments after the P2 gate (FIX FIRST, 2026-11-04) — binding for P3+
A1 (D1) A `<T>Msg` enum with no payload variant is an rzpp ERROR at the enum's line:
   "give one variant a payload (a payload-less enum is a plain enum and `match` rejects it)".
   No silent auto-tagging. P7 adds the compiler ask "match on plain enums".
A2 (D4/D7) Keep generated `<snake>_<action>`. The slice uses `note_set_pinned`; P3-B adds a fixture
   for the collision diagnostic; the guide says never name a change fn `<snake>_<action>`.
A3 (D6.4) `rz_str_free` is a no-op on length 0 and `rz_str_dup("")` returns the empty string without
   allocating — done in the P2 fix pass, guards at run.mettle / layer.mettle removed.
A4 (D2, P3-A) Bind before printing "listening", then serve (split rz_server bind/serve); a startup
   fixture asserts SIGTERM -> exit 0, bind failure -> exit 2 with nothing printed as "listening".
A5 (D4) Generated `<s>_signal` calls every `<r>_resource()` in the same file during declaration, so a
   resource definition is never first built on the hub thread.
A6 (D3, P3-A) `RzApp` is opaque: `export struct RzApp { impl: Rz_AppState*; }` (all internal-typed
   fields move to Rz_AppState). Same rule for any public struct that would expose internal types.
A7 (D4, P3-B) Data-layer copies never leave views into storage on any error path (blank dst strings
   before copying); the API answers a plain 400 when `errs == 0` on RZ_E_INVALID from a layer.
A8 (D5, P3-B/C) Generated app-facing functions carry full contracts (`in:` names every parameter, a
   real `example:`), and are `export`ed when the struct is.

## Amendments from the first downstream app (example_sass, 2026-11-04) — binding for P3
A9  (P3-C) Per-user Signals. The upgrade request is captured on the worker before hand-off: an
    owned copy of the Cookie header, the peer address, and ctx->user set by guards/middleware.
    A Signal may declare `fn todos_mount(s: Todos*, c: RzConn*) -> int32` (rzpp detects the 2-arg
    form; the 1-arg `fn todos_mount(s: Todos*)` stays valid). RzConn accessors: rz_conn_cookie(c,
    name) -> string, rz_conn_user(c) -> rawptr, rz_conn_peer(c) -> string. Returning non-RZ_OK
    refuses the join with {"reason": rz_status_text(code)}. The first-GET render calls mount with
    the HTTP request's RzConn too, so the page and the socket see the same user. Same RzConn for
    channel join callbacks (rz_chan_conn(ctx)).
A10 (P3-A) Guards. `rz_guard(app, "/prefix", &fn)` with `fn(ctx: RzContext*) -> int32` returning
    RZ_OK to continue or the HTTP status it already answered (e.g. rz_ctx_redirect to /login).
    Guards run after global middleware, before the handler, in declaration order, and also run on
    the socket upgrade for Signal pages/sockets under that prefix (so A9's user is set). `rz_use`
    stays for global middleware.
A11 (P3-A) Cookies + forms. rz_ctx_cookie(ctx, name) -> string (view, empty if absent);
    rz_ctx_set_cookie(ctx, name, value, opts: RzCookie) with RzCookie{max_age_s; path ("/");
    http_only (true); secure (false); same_site ("Lax")} and rz_cookie_defaults();
    rz_ctx_clear_cookie(ctx, name). rz_ctx_form(ctx, name, out*) for
    application/x-www-form-urlencoded bodies (decoded into the request arena).
    rz_ctx_set_header(ctx, name, value) (promised to mist_plot) and rz_ctx_header(ctx, name).
A12 (P3-A) Peer address. Workers record the accepted socket's IPv4 address; rz_ctx_peer(ctx)
    returns "a.b.c.d". X-Forwarded-For is trusted only when config `trusted_proxy` (an address)
    equals the socket peer; then rz_ctx_peer returns the rightmost untrusted XFF entry.
A13 Later, not P3: crypto (SHA-256/HMAC/PBKDF2/getrandom) may be lifted from example_sass into
    framework/crypto once its vectors pass there; resource actor/policies (Ash-style per-user
    scoping on derived APIs) are a design item for after P7 — until then authenticated apps
    write their own handlers over the typed code interface.

## Findings (P3-A, P3-B) — 2026-11-04
F1 `impl` is a reserved word: A6's opaque structs use `state` (`RzApp { state: Rz_AppState*; }`,
   `RzConn { state: ... }`).
F2 No libc, so no signal handlers: SIGTERM/SIGINT are blocked in every thread and a watcher thread
   (sigwait-style via syscall) stops the server; exit 0. Behaviour with live keep-alive/WS clients
   during shutdown is unverified (P3-C/P4 to check with a connected Signal).
F3 rz_channel only records (rz__app_channels); P3-C wires /socket/websocket and must make an
   unwired declaration impossible (startup error if the channel runtime is absent).
F4 tools/rzpp/resource.mettle is 459 lines (P6-G3 splits it). P3-B extras accepted: per-field 400
   for wrong-typed/out-of-range ints, 409 {"error":"conflict"}, @min_length passes empty unless
   @required (Ash's rule).
F5 Signal socket guards: /signal/websocket is shared, so the page path travels in the socket URL
   (`/signal/websocket?vsn=2.0.0&path=<location.pathname>`); the upgrade runs
   rz__app_run_guards(ctx, path) and records the path in RzConn; a Signal join is refused unless the
   joined Signal is mounted at exactly that path (a socket opened for /public cannot join /admin).

## D8. Library split, session/auth/telemetry, re-plan (2026-11-04, AC S7)

### Package graph (one-way; arrows = "depends on")
Today's module DAG (measured from `../x` imports) is already acyclic:
str, core, poll → nothing; context → core,str; router/resource → context,core,str;
server/middleware/static/ws → context,str; template → str; config → context,server,str;
hub → context,poll,str,ws; channel → context,hub,str,ws; signal → channel,context,hub,str,template;
app → everything. The cut follows it:

| Package (mbuild name = import prefix) | Lives in | Contents | Depends on |
|---|---|---|---|
| `telemetry` (`tm_`) | new repo `~/Projects/mettle/telemetry` | events, handlers, spans, counters/histograms | — (pure Mettle) |
| `raize_core` | `raize_web/libs/core` | str, core/status, context, router, server, poll, middleware, config, static, template | telemetry |
| `raize_realtime` | `raize_web/libs/realtime` | ws, hub, channel (`rz_channel`, `rz_broadcast`) | raize_core |
| `raize_signal` | `raize_web/libs/signal` | signal, html, render, signal.js | raize_core, raize_realtime |
| `raize_resource` | `raize_web/libs/resource` | resource, memory layer, JSON API | raize_core |
| `raize` (umbrella) | `raize_web` root | `raize.mettle` facade, app (`rz_run`, declare, use, web, timer), rzpp bin, init.rules, AGENT.rules | the four above |
| `raize_session` | `raize_web/libs/session` | HTTP binding of `session`: load/save middleware, `rz_session_*`, CSRF guard, flash | raize_core, `session` |
| `raize_auth` | `~/Projects/mettle/raize_auth` (reworked) | `@auth` user declaration, sign-up/login/logout routes, guards, lockout, API tokens | raize, raize_session, `crypto` |
| `session` (`ses_`), `crypto` (`cr_`, folder `../cryptex`) | existing repos | unchanged | crypto → libsodium |

Rules:
- The umbrella does **not** depend on raize_session/raize_auth. An app opts in. So `raize` stays
  pure Mettle, and only apps that want sessions/auth link libsodium (the crypto exception).
- Library packages only; the single bin is `rzpp` in the umbrella (`mb_dep_bin("raize","rzpp")`).
- One public prefix for the raize family: `rz_`/`Rz`/`RZ_` everywhere (no rename on split); internals
  `rz__` (P5). Generic libraries keep their own prefix (`tm_`, `ses_`, `cr_`).
- Inside a package, imports stay relative. Across packages they use the prefix:
  `import "raize_core/context/context"`.
- `framework/middleware/auth*.mettle` (basic/bearer guards, no crypto) stay in raize_core;
  raize_auth builds the real flows.

### Dependent import migration
`import "raize/raize"` keeps working (umbrella facade re-exports the common surface).
`import "raize/framework/X/Y"` becomes `import "raize_<pkg>/X/Y"` (table above).
mist_plot and example_sass get the mapping as a TSV at the SPLIT commit.

### Telemetry library (pure Mettle, Elixir :telemetry + Telemetry.Metrics shape)
- `tm_attach(id, prefix, handler: fn(ev: TmEvent*, cfg: rawptr) -> void, cfg) -> int32`, `tm_detach(id)`.
- `tm_execute(name, measures, n, meta)`: name is dotted (`raize.request.stop`); handlers run on the
  caller's thread; registry is copy-on-write under a lock so execute never blocks on attach.
- `tm_span_start(name, meta) -> TmSpan` / `tm_span_stop(span, meta)`: emits `.start`/`.stop` with
  `duration_ns`; `.exception` variant.
- Metrics: `tm_counter`, `tm_sum`, `tm_last_value`, `tm_histogram(name, buckets)` defined over events;
  a reporter is a handler. In-process aggregates are not a storage system (hold not violated).
- raize events: `raize.request.{start,stop}`, `raize.router.dispatch`, `raize.signal.{mount,update,render}`,
  `raize.channel.{join,message,broadcast}`, `raize.resource.action.{start,stop}`. Cost when nothing is
  attached: one atomic load.

### Session and auth
- `session` already gives agnostic sessions + a store interface (no backend, storage hold).
  raize_session adds: `rz_use_session(app, cfg)` (cookie name, max age, store vtable), `rz_session_get/put/
  delete/rotate(c)`, `rz_csrf_token(c)` + a CSRF guard for unsafe methods, `rz_flash_put/take`.
  Signals read the session at mount through `RzConn`.
- raize_auth: drop its hand-written crypto (bfcc112, 4ff6a6e) for `crypto`; never commit mem_store.
  Ash-style: `@auth` on a resource gives sign-up/login/logout routes, `rz_require_user` guard, lockout,
  hashed API tokens. Store = interface; backends come from MeoSQL/flux_orm (or alph later).

### Blocker: C calls only on the main thread (reports/031, ecosystem 058)
raize_session/raize_auth call `crypto` from handler worker threads. **USER DECIDED (2026-11-04): wait for alph.** SES and AUTH
are deferred until alph owns scheduling; no executor, no 058 workaround. Was recommended:
a generic main-thread executor in raize_core, `rz_main_call(fn, arg) -> int32` (main thread runs a queue
while `rz_run` waits; caller blocks until done). It is not crypto-specific, adds one hop per call, and is
removed when 058 or alph lands. Alternatives: wait for 058, or wait for alph.

### mbuild questions (asked to the mbuild session)
1. Root package `raize` with sibling packages under `libs/`: does publish of `raize` exclude `libs/`?
2. Path deps between packages of one repo (`mb_dep_path("raize_core","libs/core")`): how do they become
   versioned deps at publish?
3. Can the Makefile's compiler runs keep resolving `raize_core/...` through `mettle.deps` until mbuild
   builds everything?

### Re-plan (replaces D7 from P3-C on)
1. ~~TM~~ dropped: telemetry is the separate RaizeTelemetry project; raize only consumes it (INSTR).
2. **SPLIT** move framework/* into libs/*, cross-package imports, an mbuild.mettle + mettle.deps per
   package, umbrella mbuild.mettle (HANDOFF item 5), Makefile paths. Gate: `make integration` green.
   Message mist_plot + example_sass with the TSV.
3. **P3-C** as before (per-user Signals, channels from `rz_channel`, `rz_broadcast`, rzpp entry mode,
   A1/A5/A8) in the new paths.
4. **INSTR** telemetry events in core/realtime/signal/resource.
5. **SES** raize_session + the executor (after the blocker choice).
6. **P4** examples. Message mist_plot and example_sass.
7. **AUTH** raize_auth rework on raize_session + crypto. Tell mbuild.
8. **P5, P6, P7** per package (each gets AGENT.rules, init.rules where it has one, docs), FINAL GATE.

### mbuild answers (2026-11-04)
1. publish packs everything except build/, .mbuild/, vendor/, dist/, dot-files, lock, mbuild.local.mettle, mettle.deps.
   mbuild LANDED (pushed): publish skips any subdir with its own mbuild.mettle, so libs/* stay out of raize.
2. publish refuses mb_dep_path. Publish each lib separately in dep order; in raize's deps() use
   `mb_dep("raize_core","v0.1.0")` + `mb_replace_path("raize_core","libs/core")` (in deps() for every checkout).
3. mettle.deps takes one `name=path` line per package, relative to the file; mbuild writes them once it drives the build.
### Re-plan amendment
SES and AUTH wait for alph. Order now: TM, SPLIT, P3-C, INSTR, P4, P5-P7, gate; SES/AUTH after alph.
User paused before approving TM + SPLIT (restarting the desktop app): ask again before building.

### D8 amendment: structure fixes (2026-11-05)
- `app/` (rz_run, declarations, guards, rz_use, rz_every) moves out of the umbrella into package
  `raize_app` (libs/app). Add-ons (raize_session, raize_auth's binding, telemetry glue) depend on
  `raize_app`, never on the `raize` umbrella, which only re-exports.
- `poll` moves to `raize_realtime`: its only user is the hub, and alph replaces both there.
- `template` (string templates) becomes package `raize_template`, used by raize_signal and mist_plot;
  `raize_core` is now HTTP only: str, status, context, router, server, middleware, config, static.
- This record lives in git as `docs/decisions.md`; `.apex/DECISIONS.md` is a symlink to it.
