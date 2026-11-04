# 003: `rz_ctx_clear_cookie` only clears cookies set with `Path=/`

- **Project:** raize_web
- **Kind:** limitation
- **Severity:** low
- **Status:** open

A cookie set with another path or a domain survives `rz_ctx_clear_cookie(ctx, name)`.
Fix: `rz_ctx_clear_cookie` takes the same `RzCookie` options used to set it (path, domain),
or the session library (report 020) owns cookie lifetimes.
