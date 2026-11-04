# 025: Signals cannot be pushed from database changes

- **Project:** raize_web
- **Kind:** missing
- **Severity:** low
- **Status:** open; waits on MeoSQL change notifications (asked; message to MeoSQL session expired undelivered)

`<s>_publish` already works from any thread; a MeoSQL commit hook would call it.
