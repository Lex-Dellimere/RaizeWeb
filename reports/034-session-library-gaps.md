# 034: `session` has no subject change and no read-only lookup

- **Project:** session (used by raize_web's `raize_session`)
- **Kind:** limitation
- **Severity:** low
- **Status:** fixed: session `ses_peek` and `ses_set_subject`; raize_session uses `ses_peek` in `rz_conn_session_get` and sets the subject in `rz_session_login`

## What happens
1. **Subject fixed at creation.** `ses_create` takes the subject (user id) and `ses_rotate`
   keeps it; there is no call to set it later. A web session starts anonymous (a CSRF token
   for the login form, a flash) and gains a user at login, so `raize_session` creates every
   session with the constant subject `"raize"` (`RZ__SES_SUBJECT`) and keeps the user in the
   session data. Consequence: `ses_revoke_subject(m, user_id)` ("log out everywhere") cannot
   target one user's raize sessions.
2. **No read-only lookup.** `ses_lookup` hands pending flash messages to the caller and clears
   them in the store. `rz_conn_session_get` (a Signal mount or channel join on the hub thread)
   only wants the values, but has no other verified lookup, so flash queued for the session's
   next page is consumed if a socket mounts first.
3. The session README and `///` contracts still say "main thread only" (libsodium era);
   since cryptex 0.2.0 is pure Mettle the calls are any-thread. raize relies on that.

## Wanted from `session`
- `ses_set_subject(m, s, subject)` (or a subject argument to `ses_rotate`), so login can
  rotate an anonymous session into a user's.
- `ses_peek(m, tok, now, out)`: `ses_lookup` without taking flash or deleting expired records.
- Thread notes updated for pure-Mettle crypto.

raize adapts in `libs/session/state.mettle` (subject) and `libs/session/conn.mettle` (lookup)
once these exist.
