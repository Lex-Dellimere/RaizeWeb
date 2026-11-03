# tests/fixtures/middleware

Runnable fixtures for `framework/middleware`. Each one is a *proof*, not a demo;
the expected outcome is stated here and in the file header, so a future change
that breaks it is visible.

Build and run everything from the repo root (`import` paths are cwd-relative):

```bash
M=./mettle-build/bin/mettle
$M --build tests/fixtures/middleware/wire.mettle -o build/rz_mw_wire && ./build/rz_mw_wire
$M --build tests/fixtures/middleware/app.mettle  -o build/rz_mw_app  && ./build/rz_mw_app --port 8093
$M --build tests/fixtures/middleware/fault.mettle -o build/rz_mw_fault && ./build/rz_mw_fault; echo $?
```

| file | what it proves | expected |
|---|---|---|
| `wire.mettle` | the whole compiled chain (`recover -> logging -> cors -> auth -> terminal`) driven in memory: order, short-circuit, 401/403/500, CORS preflight, CRLF guard, monotonic clock, stats | every line `PASS`, last line `failures=0` |
| `app.mettle` | the same chain on a real socket for curl: preflight 204, 401 + `WWW-Authenticate`, 200 with a token, 500 with a generic body, arena bytes per request, no RSS growth under 400 failures | see the hand-off report's curl transcript |
| `fault.mettle` | a wild write inside the handler while `rz_mw_recover` is mounted: the process dies, recovery never runs | `Unhandled runtime signal 11`, exit `139`, no line after `rz_chain_serve` |
| `probe_auth_reexport.mettle` | a consumer importing **only** `framework/middleware/auth` still reaches the moved token parser and the hook types after the `auth_token.mettle` split | `scheme=[Bearer] token=[abc] found=1`, `validate=0` |
| `probe_abi_hook_shapes.mettle` | the hook signature shipped by `auth.mettle` (pointer args, `int32` return) called through a function pointer in another module, with cross-module calls inside the callee | `found=1 token=[good] verdict=200 principal=<nonzero>` |
| `probe_abi_call_indirect.mettle` | **negative**: an indirect call with a `string` argument | compile fails: `call_indirect_unsupported` |
| `probe_abi_bad_return.mettle` | **negative**: an indirect call to another module's function that *returns* a `string` | runtime `signal 11`, exit `139`; the direct call on the line before prints `Not Found` |

The two negative probes are the reason no pluggable hook in `framework/middleware`
takes or returns a struct by value — see the header of `framework/middleware/auth.mettle`
and of `auth_token.mettle`.

`wire.mettle` and `app.mettle` are also the regression harness for the module
(`make test` covers the `@test` units; these cover codegen + the socket path).
