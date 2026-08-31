# `SoundboardWeb.Plugs.BasicAuth`

Basic authentication plug.

When both `BASIC_AUTH_USERNAME` and `BASIC_AUTH_PASSWORD` environment variables
are set to non-blank values, every browser request must supply matching Basic
credentials. When either variable is missing or blank, basic auth is disabled
and all requests pass through.

# `call`

# `init`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
