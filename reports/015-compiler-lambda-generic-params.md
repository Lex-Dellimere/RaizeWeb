# 015: A lambda inside a generic function cannot see its type parameters; `&generic<T>` does not parse

- **Project:** Mettle compiler
- **Kind:** compiler
- **Severity:** medium
- **Status:** worked around with rzpp-generated non-generic glue (`<Type>__handle`, `<s>_signal`)
