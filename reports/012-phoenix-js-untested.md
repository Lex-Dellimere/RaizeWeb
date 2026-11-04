# 012: The stock phoenix.js / phoenix_live_view.js clients were never run against raize

- **Project:** raize_web
- **Kind:** unverified
- **Severity:** low
- **Status:** open

raize speaks Phoenix's v2 channel protocol and rendered-diff format and ships its own small
clients (examples/chat, framework/signal/signal.js). Compatibility with the upstream JS was
designed for but not tested (downloading it needs the user's approval).
