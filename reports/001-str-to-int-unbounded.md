# 001: `rz_str_to_int` has no bound: `rz_ctx_query_int` accepts junk as -1 and wraps on overflow

- **Project:** raize_web
- **Kind:** bug
- **Severity:** medium
- **Status:** open; queued as B1 (first fix when work resumes)

## What happens
`rz_str_to_int` returns -1 for non-digits and never checks overflow
(`"9223372036854775808"` -> INT64_MIN, `"18446744073709551617"` -> 1).
`rz_ctx_query_int` passes the result through and returns `true`, so `?id=abc` is
indistinguishable from `?id=-1`. `rz_signal_arg_int` checks characters but not length.
`framework/resource/api.mettle` is safe (18-digit cap).

## Fix
A bounded parser (`rz_str_parse_int(s, out*) -> bool`: optional sign, digits only,
overflow-checked) used by `rz_ctx_query_int`, `rz_signal_arg_int` and every caller;
keep `rz_str_to_int` for trusted input or make it call the bounded one. Tests for
"", "-", "abc", "1x", INT64_MAX, INT64_MAX+1, INT64_MIN, 20+ digits.

## Source
Found by example_sass: `~/Projects/mettle/example_sass/reports/002-raize-str-to-int.md`
(repro `002-repro.mettle`).
