# `Soundboard.Boundary`

The exception types that can realistically escape across a process or API
boundary here: the Discord gateway (EDA), voice, HTTP, the file system and
SQLite. Code rescues `e in @boundary_exceptions` rather than everything;
exits and throws are caught separately.

# `exceptions`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
