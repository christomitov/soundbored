# `SoundboardWeb.GuildController`

Tenant onboarding: list the guilds the shared bot is a member of and let the
signed-in user switch their active soundboard (creating the tenant row on
first use — that is the whole "provisioning" step).

# `claim`

Claims a slug (subdomain name) for the session's current guild.

Availability is pre-checked with `Tenants.slug_available?/1` for a clean
error path; reserved/duplicate slugs are rejected authoritatively inside
`Tenants.claim_slug/2`.

# `index`

# `show`

Scopes the app to the tenant resolved by slug. Resolution never creates a
row: an unknown slug is a 404. Setting the session `:guild_id` is what makes
the Tenant plug (and LiveViews on subsequent requests) pick the guild up.

# `switch`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
