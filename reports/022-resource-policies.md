# 022: Resources have no actor/policies: derived JSON APIs cannot scope records per user

- **Project:** raize_web
- **Kind:** missing
- **Severity:** medium
- **Status:** open; after the redesign (DECISIONS A13)

Authenticated apps write their own handlers over the typed code interface until Ash-style
actor + policy declarations exist.
