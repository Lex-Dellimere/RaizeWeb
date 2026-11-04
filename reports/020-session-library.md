# 020: No session handler library (cookies, session store and expiry, signed/hashed tokens, CSRF, flash)

- **Project:** raize_web
- **Kind:** missing
- **Severity:** high
- **Status:** open; part of D8 (user direction 2026-11-04)

example_sass implements sessions, hashed tokens, CSRF and expiry in app code; raize should
own them as a library the auth library builds on.
