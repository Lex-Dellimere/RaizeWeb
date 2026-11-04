# 023: raize_web has no mbuild.mettle (library package `raize`, rzpp as its only bin)

- **Project:** raize_web
- **Kind:** missing
- **Severity:** medium
- **Status:** open; after P3 / with D8 (library, not a binary)

Format settled (mbuild 0.2.0). Plan: `mb_package("raize", ...)`, no app bins, rzpp exposed
via `mb_dep_bin("raize", "rzpp")`, the rzpp `hook_pre_build` in the app's mbuild.mettle
(scaffolded by raize's init.rules, writing with `mb_write_if_changed`), AGENT.rules.
mbuild currently accepts raize_web as a manifest-less path dep (example_sass report 004).
