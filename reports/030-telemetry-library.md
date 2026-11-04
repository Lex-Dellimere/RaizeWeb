# 030: No telemetry library

- **Project:** raize_web
- **Kind:** missing
- **Severity:** medium
- **Status:** open; part of the library-split design D8 (user direction 2026-11-04)

raize emits no structured events or metrics (only the logging middleware and server counters).
Planned: a telemetry library in the style of Elixir's `:telemetry`: named events with
measurements and metadata, handlers apps attach, spans with start/stop timings, and metrics
(counters, histograms) for HTTP requests, Signal events and diffs, channel joins and messages,
and resource actions. Pure Mettle, no external exporters; other raize libraries emit through it.
