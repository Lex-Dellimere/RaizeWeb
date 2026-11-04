# 031: The crypto library can only be called from the main thread, but raize runs handlers on worker threads

- **Project:** Mettle runtime (C interop), affecting raize_web and raize_auth
- **Kind:** limitation (blocker for auth)
- **Severity:** high
- **Status:** open; root cause is the Mettle runtime (crypto's reports/001), filed as feature
  request `~/Projects/mettle/reports/058-foreign-calls-from-mettle-threads.md`

`~/Projects/mettle/crypto` wraps libsodium (verified: every vector suite OK in debug and release).
`Mettle/docs/shared-libraries.md` says only the main thread may call a foreign library: threads
that Mettle starts install their own thread pointer, which libc's thread-local state (`errno`,
pthread) doesn't recognise. raize handles HTTP requests on worker threads and Signals and
channels on the hub thread, so a login handler can't call `cr_pwhash_verify`.

## Options
1. Mettle runtime fix: threads Mettle starts are real pthread/libc threads when a program binds a
   shared library. This is the proper fix, so ask the Mettle compiler session.
2. raize workaround: a crypto service on the main thread (rz_run's main thread serves a request
   queue; workers block on a reply). Adds latency and serializes all crypto.
3. Wait for alph: if its scheduler threads are created in a libc-compatible way, crypto calls from
   actors work.
