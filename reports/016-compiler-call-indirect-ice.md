# 016: Codegen ICE `call_indirect_unsupported` on some indirect calls

- **Project:** Mettle compiler
- **Kind:** compiler
- **Severity:** high
- **Status:** worked around (pass string variables, never cast fn pointers from rawptr, call update() directly)

Fails when an indirect call's argument is a string literal (`dp->handle(st, "Add")`; a string
variable works), when the pointer came from a `rawptr` cast, or when an argument is a tagged
enum by value. fn-to-fn pointer casts (S* -> rawptr parameter) work.
