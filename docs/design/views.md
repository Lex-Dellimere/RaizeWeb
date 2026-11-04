# Views and Signals: markup as Mettle

Status: built on the preprocessor path, 2026-11-04 (see §7 for what differs
from the plan below). **Signal** (`RzSignal`) is raize's name for a
real-time page in the style of Phoenix LiveView: the model is adapted to
Mettle, not copied by name. Replaces the "templates v2" idea in
`realtime.md` §M5 (a separate template language). Nothing is built yet.

## The idea in one paragraph

A view is a Mettle function that returns markup. The markup is written in a
tagged literal, `html"""..."""`, and everything inside `{}` is Mettle. There
is no template language to learn: holes are Mettle expressions, loops are
Mettle `for`, branches are Mettle `if`/`match`, components are Mettle
functions, events are a Mettle `enum`. The literal is compiled at build time
into constant statics plus dependency-tracked dynamics, the exact shape
Signal diffs need. The compiler type-checks every hole, so a mistake is a
normal Mettle diagnostic with a line number.

## What Mettle already has (verified 2026-11-04)

- **Every string literal is already a template.** `"<li>{n}</li>"` may span
  lines and interpolates any expression. The lexer
  (`Mettle/src/lexer/lexer.c`) already splits a literal into static text and
  expression holes, and `ir_lower_interpolation` joins them. A view literal is
  the same parse with a different lowering: keep the parts apart.
- **`@generate` metafunctions** (`Mettle/docs/metaprogramming.md`) are Mettle
  code that runs at compile time and returns Mettle source, which the compiler
  then checks like typed code. `mettle expand` prints the result, and `@rule`
  can verify it. This is Mettle's equivalent of an Elixir macro, the
  machinery behind `~H`.
- **Compile-time reflection** (`typeof(T).fields`, `comptime for`) can
  generate a per-struct "which fields changed" function.
- **Not yet:** a generator cannot take a string argument (`@view("...")` is a
  parse error), and there is no tagged-literal form. That gap is §5.

## 1. A Signal is state + messages + update + view

Phoenix's model, typed. It is also the shape of a process in the coming
runtime: state, a mailbox of messages, and a handler.

```mettle
import "raize/signal";

struct Todo { id: int32; title: string; done: bool; }
enum Filter { All, Open, Done }

// State is a plain struct. There is no assign/3: change a field and the view
// knows (§3).
struct Todos {
  items: Todo[];
  filter: Filter;
  draft: string;
}

// Every event the page can send, as a tagged enum. `match` is exhaustive, so
// an event the view emits but update() ignores does not compile.
enum TodosMsg { Toggle(int32), Add, Draft(string), Show(Filter) }

fn todos_mount(s: Todos*) {
  s->filter = Filter.All;
}

fn todos_update(s: Todos*, msg: TodosMsg) {
  match (msg) {
    case Toggle(id): { todo_toggle(s, id); }
    case Add:        { todo_add(s); }
    case Draft(t):   { s->draft = t; }
    case Show(f):    { s->filter = f; }
  }
}

fn todos_view(s: Todos*) -> RzHtml* {
  return html"""
    <h1>Todos ({open_count(s)} open)</h1>
    <form on:submit={Add}>
      <input value={s->draft} on:input={Draft} />
    </form>
    <ul>
      {for t in visible(s) {
        <li class={todo_class(t)}>
          <button on:click={Toggle(t.id)}>{t.title}</button>
        </li>
      }}
    </ul>
    {if s->items.length == 0 {
      <.empty_state message="Nothing to do" />
    }}
  """;
}

fn empty_state(message: string) -> RzHtml* {
  return html"""<p class="empty">{message}</p>""";
}

// Registered once (TodosMsg__signal is generated, see §7), served by a route.
TodosMsg__signal(chans, "todos", &todos_mount, &todos_view, &todos_leave);
```

## 2. The rules (all of them)

1. `{expr}` is a Mettle expression. Strings and numbers are HTML-escaped by
   type. An `Html` value is inserted as is, safe by construction. `{raw(s)}`
   is the only way to insert unescaped text, and it is easy to grep for.
2. `name={expr}` sets an attribute from an expression. `name="text"` is
   literal text.
3. `{for x in xs { markup }}`, `{if cond { markup } else { markup }}` and
   `{match v { case A: markup, ... }}` are Mettle's own statements. Inside
   their braces you are back in markup.
4. `<.name a={x} b="y">children</.name>` calls `fn name(a, b, inner: Html)`.
   Attributes bind to parameters by name and are type-checked. `children`
   becomes `inner`.
5. `on:click={Msg}` / `on:click={Toggle(t.id)}` sends a message variant. It
   becomes Phoenix's `phx-click` plus `phx-value-*` attributes, and arrives in
   `update` already decoded.
6. `<script>` and `<style>` contents are raw text: `{` there is CSS or JS.

That is the whole language. Everything else is Mettle, which a developer and
a model already have to know. A model's mistake is a Mettle compile error
pointing at the line in the view.

Logic stays in functions (`open_count(s)`, `todo_class(t)`), not in markup.
Mettle has no ternary and no `if` expression, and the view does not invent
one.

## 3. How it compiles (what a Signal gets)

The `html` processor (written in Mettle, running at compile time) parses the
literal once and emits ordinary Mettle:

- **Statics:** a `const` string array per literal and per `for`/`if` body,
  plus a fingerprint computed at build time. Phoenix sends statics once per
  fingerprint, and so do we.
- **Dynamics:** one slot per hole. Each slot records which state fields it
  reads, taken from the hole's expression: `{s->draft}` reads `draft`;
  `{open_count(s)}` reads all of `s` unless the compiler can say more (§5).
- **Change tracking without assign():** for the state struct, `comptime for`
  over `typeof(Todos).fields` generates `todos__changed(old, new) -> uint64`,
  one bit per field. After `update`, only slots whose dependencies meet the
  changed bits are re-evaluated, and only those go into the diff (`"0"`,
  `"1"`, ... and `"d"` for `for` bodies, Phoenix's rendered format).
- **First render:** the same code flattens statics and dynamics to HTML for
  the initial GET, so search engines and no-JS clients get the page.

Because the output is plain Mettle, `mettle expand` shows exactly what a view
became, and a `@rule` can prove properties of the generated code (every
dynamic in text position goes through the escaper).

## 4. Why this design, for people and for models

- **Nothing new to learn.** The 6 rules above sit on top of Mettle. Compare
  HEEx (Elixir plus HEEx), Jinja (a second expression language) and Mustache
  (ambiguous sections).
- **Wrong code does not compile.** Unknown fields, wrong component arguments,
  unhandled events and type mismatches are compiler errors. A model fixes
  from the diagnostic in one step.
- **One canonical form per thing.** One loop, one branch, one way to call a
  component, one way to send an event.
- **Closest to the familiar shapes.** It reads like `~H` (Elixir), templ (Go,
  which has the same no-macros problem and solved it the same way), and JSX
  `{}` holes. Models have seen all three.
- **The runtime fit is free.** State plus message plus update is the process
  model. When the Mettle runtime lands, a Signal becomes a process with no
  API change.

## 5. What it needs from the compiler, and the path until then

**The ask (one feature, reusable):** a *tagged literal*.
`tag"""..."""` (triple quotes, because markup is full of `"`) is lexed like a
string with holes, but instead of being joined it goes to a metafunction:

```mettle
@literal fn html(lit: LiteralInfo) -> Generated { ... }   // in raize
```

`LiteralInfo` carries the static parts, each hole's source text, its checked
type and its site. The metafunction returns Mettle source, as `@generate`
already does. The same feature gives:

- flux_orm / MeoSQL: `sql"""select * from users where id = {id}"""` becomes a
  prepared statement with a bound parameter. SQL injection cannot be written.
- `json"""...""", css"""...""", shader"""..."""` as libraries, not compiler
  work.

A smaller second ask: let a hole report its field dependencies (the memory
analysis already knows what `open_count(s)` reads). That makes change
tracking exact instead of conservative.

**Until then (so raize is not blocked):** a raize preprocessor, written in
Mettle and run as an mbuild step, rewrites `html"""..."""` in `.mettle` files
into the same generated Mettle, the way templ generates Go. User code is
identical before and after the compiler feature lands. Cost: diagnostics
point at the generated file unless the compiler accepts a line-mapping
directive (a third small ask), and an mbuild custom step (the mbuild session
is designing `mbuild.mettle` custom commands now).

## 6. What happens to framework/template

It stays for what it does well: static pages and emails rendered from files
at startup. Views are the new path for anything interactive. The
statics/dynamics renderer in `framework/signal` is shared by both.

## Open questions

1. Tagged literal in the compiler (coordinate with the Mettle session), or
   the preprocessor first?
2. `<.name>` (HEEx) or `<Name>` (JSX) for components? Proposed: `<.name>`,
   because Mettle functions are snake_case.
3. Typed events (`on:click={Toggle(id)}`) replace string `phx-click` in
   views. Keep raw `phx-*` attributes for interop with hand-written JS?
   Proposed: yes, both.

## 7. What was built (2026-11-04)

`examples/todos` is a working Signal, verified in a browser and by
`make signal-test`. Differences from the plan above:

- **Views return `RzHtml*`** (raize's flat namespace needs the prefix).
- **Registration is generated.** rzpp finds `update` by its signature (the
  function whose second parameter is the message enum) and generates
  `NameMsg__decode`, `NameMsg__handle` (decode, then call update directly)
  and `NameMsg__signal(chans, name, &mount, &view, &leave)`, which type-checks
  the three functions against the state type. A generic
  `rz_signal_define<S, M>` was the plan, but the compiler cannot (yet) see
  type parameters inside a lambda, take `&generic<T>`, or call through a
  pointer with an enum argument.
- **Change tracking is by value, not by dependency.** Every event re-runs
  `view`, and `rz_html_diff` compares the new tree with the last one (text by
  value, nodes by fingerprint). The wire output is the same minimal diff, but
  the view does all its work each time. Per-field dependency tracking (§3)
  becomes possible when the compiler reports what each hole reads.
- **Field-access holes render through interpolation.** `{s->draft}` becomes
  `rz_html_put_text(h, i, "{s->draft}")`, because generic inference fails on
  field-access arguments. Calls, variables, literals and arithmetic use the
  typed `rz_html_put`. Same output either way.
- **Events:** `on:click/input/change/submit` exist. A bare variant whose
  payload is a string takes the input's value (on submit, the form's first
  named field). The client keeps the focused input's text while you type, and
  takes the server's values right after a submit, so forms clear.
- **Diagnostics:** rzpp errors are `file:line: message` (`tests/fixtures/rzpp`).
  Generated code sits on the literal's first line, so a Mettle type error
  inside a hole points at the `return html"""` line, not the exact hole line.

Not built yet: pushes from the server without an event (Phoenix's
`handle_info`, for example a ticker or a database change), keyed lists,
uploads, multiple Signals sharing one socket (each page joins its own
topic, which already works), and the compiler-native `html"""` literal.
