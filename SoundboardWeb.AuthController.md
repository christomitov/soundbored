# `SoundboardWeb.AuthController`

Discord sign-in. A signed-out visitor who opened `/g/:slug` has that slug
kept in the session (`:pending_slug`), and lands on it after signing in.

# `callback`

# `logout`

# `request`

Only reached for providers Ueberauth does not handle: the Ueberauth plug
answers `/auth/discord` itself by redirecting to Discord.

# `test_login`

Test-only sign-in for Playwright e2e runs. The route is registered only when
`:enable_test_login` is configured, which is dev/test — never prod.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
