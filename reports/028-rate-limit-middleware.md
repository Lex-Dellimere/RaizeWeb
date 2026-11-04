# 028: No per-peer rate-limiting middleware

- **Project:** raize_web
- **Kind:** missing
- **Severity:** medium
- **Status:** open (suggested by example_sass, `F01-raize-missing.md`)

Login endpoints need per-client rate limiting; apps do it by hand today. Now that
`rz_ctx_peer` exists (trusting X-Forwarded-For only from `trusted_proxy`), an
`rz_use_rate_limit(app, prefix, requests, per_seconds)` middleware fits: a bounded per-peer
token bucket, 429 with `Retry-After`, thread-safe across workers. Belongs with the auth/session
libraries (reports 020, 021) or the middleware library after the split (019).
