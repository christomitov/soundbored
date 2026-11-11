# `SoundboardWeb.Plugs.RoleCheck`

Re-checks a signed-in user's required Discord role at most every
`:role_recheck_interval_seconds` (default 15 minutes), and signs them out
when they no longer have it. Runs after `ensure_authenticated_user`, so
there is always a user.

# `call`

# `init`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
