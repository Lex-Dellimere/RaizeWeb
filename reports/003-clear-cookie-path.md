# 003: `rz_ctx_clear_cookie` takes no options (only clears `Path=/`, can't repeat Secure/SameSite)

- **Project:** raize_web
- **Kind:** limitation
- **Severity:** low
- **Status:** open

A cookie set with another path or a domain survives `rz_ctx_clear_cookie(ctx, name)`.
Fix: `rz_ctx_clear_cookie` takes the same `RzCookie` options used to set it (path, domain),
or the session library (report 020) owns cookie lifetimes.

It also cannot repeat the `Secure` / `SameSite` attributes the cookie was set with, which some
browsers require on the expiring Set-Cookie (example_sass, `F01-raize-missing.md`).
Fix: `rz_ctx_clear_cookie(ctx, name, opts: RzCookie)` (same options as set), or let the session
library (report 020) own cookie set/clear.
