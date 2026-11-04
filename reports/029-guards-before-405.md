# 029: Guards run before the router's method check

- **Project:** raize_web
- **Kind:** limitation (documentation at minimum)
- **Severity:** low
- **Status:** open (found by example_sass)

A signed-out `GET` to a POST-only guarded route gets the guard's answer (e.g. a redirect to
/login) instead of `405 Method Not Allowed`. Either document it in `rz_guard`'s contract and
the guide, or run guards after route matching (method check first, so 404/405 win over the
guard). Decide in the library-split design (D8); the second option leaks less about which
routes exist only if 404 also precedes the guard, so the choice is deliberate.
