# 007: rzpp handles one file at a time; multi-file apps need entry mode

- **Project:** raize_web
- **Kind:** missing
- **Severity:** medium
- **Status:** open; P3-C

Planned (DECISIONS D1): `rzpp <entry.mettle>` processes the entry and every local import
containing decorators or html literals, writes `<name>.gen.mettle` beside each, and rewrites
`import "x";` to `import "x.gen";` on the same line.
