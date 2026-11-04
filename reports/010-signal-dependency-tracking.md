# 010: Signals re-render the whole view per event (value diff), not per changed field

- **Project:** raize_web
- **Kind:** missing
- **Severity:** low
- **Status:** open; design in docs/design/views.md §3, needs compiler help (report 015)

The wire diff is already minimal, but the server does all view work on every event.
Per-field dependency tracking needs to know which state fields each hole reads.
