# 019: raize is one package; it must become a framework of several libraries

- **Project:** raize_web
- **Kind:** missing
- **Severity:** high
- **Status:** open; next design step D8 (user direction 2026-11-04, AC S7)

Split existing functionality into library packages with one-way dependencies (e.g. core
HTTP/router/context, realtime hub+channels, Signals+views+rzpp, resources+data layers,
templates/static, middleware), each its own mbuild package (library-only), with a `raize`
umbrella for dependents that import `raize/...` today (example_sass, mist_plot).
