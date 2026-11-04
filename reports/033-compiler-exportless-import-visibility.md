# 033: An export-less module imported first through another module is invisible to a later direct importer

- **Project:** Mettle compiler
- **Kind:** compiler
- **Severity:** low
- **Status:** open; worked around (export the helpers)

## What happens
`u.mettle` has no `export` (so it is entirely public). `b.mettle` imports `u`. `a.mettle`
does `import "b"; import "u";` and calls `u_one()`: `error[E0003]: Undefined function
'u_one'`. Swapping the imports (`import "u"; import "b";`) builds. The repeated plain import
of `u` is skipped, and its names are then not made visible to `a`. With `export fn u_one()`
both orders build. Found with tests/fixtures/app/multi (P3-C3): app.mettle imports
counter (which imports util) before util.

Repro (three files, debug build): u.mettle `fn u_one() -> int32 { return 1; }`; b.mettle
`import "u"; export fn b_two() -> int32 { return u_one() + 1; }`; a.mettle
`import "b"; import "u"; fn main() -> int32 { return u_one() + b_two(); }`.

## Fix
Upstream: a skipped repeated import should still make the module's public names visible
to the importer. Until then, multi-file raize apps `export` the helpers in shared local
files (the multi fixture does).
