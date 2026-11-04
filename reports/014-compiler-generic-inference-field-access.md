# 014: Generic inference fails on field-access arguments (`put(h, s->n)`: "Nothing in this call says what 'T' is")

- **Project:** Mettle compiler
- **Kind:** compiler
- **Severity:** medium
- **Status:** worked around in rzpp (field paths render via string interpolation); repro in docs/design/mettle-tagged-literals-request.md

Bare variables, literals, calls and `s->n + 0` infer fine. `put<typeof(s->n)>(...)` does not parse.
