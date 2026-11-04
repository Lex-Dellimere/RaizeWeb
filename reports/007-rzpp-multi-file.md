# 007: rzpp handles one file at a time; multi-file apps need entry mode

- **Project:** raize_web
- **Kind:** missing
- **Severity:** medium
- **Status:** fixed (P3-C3)

Planned (DECISIONS D1): `rzpp <entry.mettle>` processes the entry and every local import
containing decorators or html literals, writes `<name>.gen.mettle` beside each, and rewrites
`import "x";` to `import "x.gen";` on the same line.

Fixed in P3-C3: entry mode (tools/rzpp/entry.mettle) does exactly this, transitively, loading each file once (cycles end), and also generates a plain file that imports a generated one; tests/fixtures/app/multi builds through it.
