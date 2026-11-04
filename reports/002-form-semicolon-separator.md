# 002: Query strings and form bodies are also split on `;`

- **Project:** raize_web
- **Kind:** bug
- **Severity:** low
- **Status:** fixed: query/form splitting is on `&` only; `t_rz_query_semicolon` covers `a=1;b=2`.

## What happens
`framework/context/query.mettle` splits pairs on `;` as well as `&`, so `rz_query_get`,
`rz_query_find` and `rz_ctx_form` read `a=1;b=2` as two fields. WHATWG
`application/x-www-form-urlencoded` splits only on `&`; accepting `;` enables parameter
smuggling past caches and proxies (Python removed it for CVE-2021-23336).

## Fix
Split on `&` only; a test that `a=1;b=2` is one field `a` with value `1;b=2`.

## Source
example_sass `reports/003-raize-form-semicolon.md`.
