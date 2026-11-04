# 020: No session handler library (cookies, session store and expiry, signed/hashed tokens, CSRF, flash)

- **Project:** raize_web
- **Kind:** missing
- **Severity:** high
- **Status:** fixed (libs/session, package `raize_session`, over the `session` library)

example_sass implements sessions, hashed tokens, CSRF and expiry in app code; raize should
own them as a library the auth library builds on.

**Fixed:** `libs/session` (`raize_session`) binds the `session` library to HTTP: `rz_use_session`
middleware, `rz_session_*`, `rz_csrf_token` + 403 guard with `rz_csrf_exempt`, `rz_flash_*`,
`rz_conn_session_get`; tests/fixtures/app/session proves it (store is the app's; see 034).
