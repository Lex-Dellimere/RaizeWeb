# 017: `match` rejects plain (payload-less) enums, so a message enum needs at least one payload

- **Project:** Mettle compiler
- **Kind:** compiler
- **Severity:** low
- **Status:** worked around: rzpp reports a payload-less `<T>Msg` as an error (DECISIONS A1)
