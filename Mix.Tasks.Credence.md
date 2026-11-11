# `mix credence`

Credence finds code that works but isn't written the Elixir way (a list
built only to be summed, a zip then a map) and rewrites it.
`mix credence` fixes each file it finds something in, in place, with
`Credence.fix/2`, and lists what it couldn't fix; `mix credence --check`
(precommit and CI) changes nothing and fails listing what it finds.

Only the rules that hold for any Unicode text run (`config :credence,
assumptions: :strict`, in dev and test): sound names and tags aren't
plain ASCII.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
