# Request to the Mettle compiler: tagged literals

From raize_web, 2026-11-04. Paste this into the Mettle compiler session. The
context is `docs/design/views.md` §5.

## Why

raize views will be Mettle functions that return markup, in the style of
Phoenix's `~H`, where every `{}` hole is a Mettle expression:

```mettle
fn todos_view(s: Todos*) -> Html {
  return html"""
    <h1>{open_count(s)} open</h1>
    {for t in s->items { <li on:click={Toggle(t.id)}>{t.title}</li> }}
  """;
}
```

LiveView diffing needs the literal kept as statics plus per-hole dynamics,
with each hole's field dependencies. Today `ir_lower_interpolation` joins it
into one string.

## Verified on the dev compiler (da1753da)

- Ordinary string literals already span lines and interpolate `{expr}`, so
  the lexer already splits literal text from expression holes.
- `@generate` already runs Mettle at compile time and splices the source it
  returns.
- A generator cannot take a string decorator argument:
  `@view("<li>{{n}}</li>") fn item(...)` is E0002 "Expected an expression,
  found the end of the line". Layout decorators do get `args: string[]`.

## The ask (one feature, reusable)

1. **Lexer and parser:** `ident"""..."""`, a triple-quoted literal (markup is
   full of `"`) with the same `{expr}` and `{{` rules as strings. The AST
   keeps the static parts and the hole expressions separate.
2. **Lowering:** if `ident` resolves to a metafunction declared as
   `@literal fn html(lit: LiteralInfo) -> Generated`, the compiler calls it at
   compile time. `LiteralInfo` carries `parts: string[]` (statics),
   `holes: string[]` (each hole's source text), `hole_types: string[]`
   (checked types) and a `site` for diagnostics. The returned `Generated`
   source replaces the literal expression and is checked like typed code.
   `refuse(why)` and `mettle expand` behave as they do for `@generate`.
3. **Nested markup inside holes** (`{for t in xs { <li>...</li> }}`): the
   simplest form gives the metafunction the raw hole text and lets it parse.
   Lexer support for braces inside markup inside holes would be a bonus.

Nice to have, later:

4. Per-hole field dependencies: which struct fields a hole's expression reads.
   The memory analysis already knows this, and it makes change tracking exact.
5. A line-mapping directive, so code a preprocessor generates reports errors
   at the original line.

## Other users of the same feature

- flux_orm and MeoSQL: `sql"""select * from users where id = {id}"""` becomes
  a prepared statement with a bound parameter, so SQL injection cannot be
  written.
- `json"""..."""` and `css"""..."""` become libraries, not compiler work.

## Until then

raize runs a preprocessor (an mbuild step) that does the same rewrite, so
nothing is blocked.

Questions for the compiler side:
- Is this feasible in the frontend?
- Would you change the `LiteralInfo` shape or the syntax?
