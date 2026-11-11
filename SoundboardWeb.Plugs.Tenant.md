# `SoundboardWeb.Plugs.Tenant`

Resolves the current tenant (guild) for a request.

Resolution order:
1. Subdomain — `{slug}.soundbored.app` (base host configured as
   `:tenant_base_host`) must map to an existing guild slug, else 404.
2. Session — `guild_id` set by the guild switcher.
3. Default guild — keeps zero-config single-guild deployments unchanged.

A signed-in user (browser session or API token) must be a member of the
resolved guild (`Soundboard.Tenants.Membership`): a subdomain they are not
in is a 403, and a session guild they are not in falls back to the default
guild. Signed-out requests resolve normally; the routes that need a user
redirect them to sign in afterwards.

Assigns `:current_guild_id` (string) and `:current_guild` (row or nil), and
mirrors the id into the session so LiveViews receive it on mount.

# `call`

# `init`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
