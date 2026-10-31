# `SoundboardWeb.Plugs.AppGate`

Gate for the soundboard app pages (Sounds, Stats, Favorites, Settings).

Self-hosted (billing dormant) everything is unlocked — the pre-billing
behavior is unchanged. On hosted, a signed-in user must have picked a guild
whose tenant row carries an active subscription before they can use the app;
otherwise they are steered to `/guilds` (pick a soundboard) or `/billing`
(subscribe). Setup pages (/guilds, /onboarding, /billing) are never gated —
they are the path to getting unlocked.

Also assigns `:app_unlocked` so the navbar can hide app navigation until the
gate opens.

# `call`

Runs in :auth (assign only) and again in :app_access (gate + redirect).

# `init`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
