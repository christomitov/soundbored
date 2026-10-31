# `SoundboardWeb.RawBodyReader`

A `Plug.Parsers` body_reader that keeps the untouched JSON request body in
`conn.assigns[:raw_body]` (a list of chunks).

Stripe webhook signatures are computed over the raw bytes, and the JSON
parser consumes the body before the controller runs, so the raw body must be
captured during parsing. Only JSON bodies are cached — upload bodies go
through the multipart parser and would otherwise be held in memory whole.

# `read_body`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
