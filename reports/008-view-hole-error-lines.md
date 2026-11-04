# 008: A Mettle type error inside a view hole points at the `return html"""` line

- **Project:** raize_web
- **Kind:** limitation
- **Severity:** low
- **Status:** open; needs a compiler line-mapping directive (report 014) or tagged literals (report 013)

rzpp joins the generated statements onto the literal's first line so lines below keep
their numbers; errors inside the literal therefore report that first line.
