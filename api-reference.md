# soundboard v1.7.0 - API Reference

## Modules

- [Soundboard](Soundboard.md): Soundboard keeps the contexts that define your domain
and business logic.
- [Soundboard.Accounts](Soundboard.Accounts.md): Accounts boundary helpers used by web and runtime code.

- [Soundboard.Accounts.ApiToken](Soundboard.Accounts.ApiToken.md): API access token bound to a user.
- [Soundboard.Accounts.ApiTokens](Soundboard.Accounts.ApiTokens.md): Context for managing API tokens bound to users.

- [Soundboard.Accounts.User](Soundboard.Accounts.User.md): The User module.

- [Soundboard.AudioPlayer](Soundboard.AudioPlayer.md): Facade over the per-guild audio player servers.
- [Soundboard.AudioPlayer.Server](Soundboard.AudioPlayer.Server.md): Per-guild audio playback coordinator.
- [Soundboard.AudioPlayer.State](Soundboard.AudioPlayer.State.md): The state of a per-guild audio player server.

- [Soundboard.Billing](Soundboard.Billing.md): Stripe-backed storage subscriptions for guild tenants.
- [Soundboard.Billing.SubscriptionSnapshot](Soundboard.Billing.SubscriptionSnapshot.md): The guild's live Stripe subscription state cached in memory between
webhooks: the subscription id, its line item id, and the price id.

- [Soundboard.Boundary](Soundboard.Boundary.md): The exception types that can realistically escape across a process or API
boundary here: the Discord gateway (EDA), voice, HTTP, the file system and
SQLite. Code rescues `e in @boundary_exceptions` rather than everything;
exits and throws are caught separately.

- [Soundboard.Discord.Handler](Soundboard.Discord.Handler.md): Handles the Discord events.
- [Soundboard.Discord.Handler.SoundEffects](Soundboard.Discord.Handler.SoundEffects.md): Join and leave sounds. A join is a voice state with no tracked previous one
(a first join, or state lost on restart) or one after a disconnect; a
channel switch or a mute/deafen update is not.

- [Soundboard.Discord.Handler.State](Soundboard.Discord.Handler.State.md): Handles the state of the Discord handler.

- [Soundboard.Discord.InviteURL](Soundboard.Discord.InviteURL.md): Builds the bot invite URL used by the onboarding flow.
- [Soundboard.Favorites](Soundboard.Favorites.md): The Favorites module.

- [Soundboard.Favorites.Favorite](Soundboard.Favorites.Favorite.md): The Favorite module.

- [Soundboard.PublicURL](Soundboard.PublicURL.md): Shared helper for the application's externally visible base URL.
- [Soundboard.Repo](Soundboard.Repo.md)
- [Soundboard.Sound](Soundboard.Sound.md): Sound schema.

- [Soundboard.SoundTag](Soundboard.SoundTag.md): The SoundTag module.

- [Soundboard.Sounds](Soundboard.Sounds.md): Sound domain context.

- [Soundboard.Sounds.Management](Soundboard.Sounds.Management.md): Domain-level sound update/delete operations used by LiveViews.
- [Soundboard.Sounds.Tags](Soundboard.Sounds.Tags.md): Domain helpers for searching, resolving, and persisting sound tags.

- [Soundboard.Sounds.Uploads](Soundboard.Sounds.Uploads.md): Canonical sound upload/create API.

- [Soundboard.Sounds.Uploads.CreateRequest](Soundboard.Sounds.Uploads.CreateRequest.md): The input to create a sound, built from request params (`new/2`).
- [Soundboard.Stats](Soundboard.Stats.md): Handles the stats of the soundboard.

- [Soundboard.Stats.Play](Soundboard.Stats.Play.md): The Play module.

- [Soundboard.TableOwner](Soundboard.TableOwner.md): Owns the app's shared ETS tables (billing's processed events, Stripe
customers and subscriptions, and the sound metadata cache).
- [Soundboard.Tag](Soundboard.Tag.md): The Tag module.

- [Soundboard.Tenants](Soundboard.Tenants.md): Multi-tenant context.
- [Soundboard.Tenants.Guild](Soundboard.Tenants.Guild.md): A tenant: one Discord guild's provisioned soundboard.

- [Soundboard.Tenants.Membership](Soundboard.Tenants.Membership.md): Who may use and who may manage a guild's soundboard.
- [Soundboard.UploadsPath](Soundboard.UploadsPath.md): Central source of truth for uploaded sound storage paths.

- [Soundboard.UserSoundSetting](Soundboard.UserSoundSetting.md): The UserSoundSetting module.

- [Soundboard.Volume](Soundboard.Volume.md): Helpers for working with volume percentages and decimal ratios.

- [SoundboardWeb](SoundboardWeb.md): The entrypoint for defining your web interface, such
as controllers, components, channels, and so on.
- [SoundboardWeb.API.SoundController](SoundboardWeb.API.SoundController.md): The JSON API. `SoundboardWeb.Plugs.APIAuth` has already authenticated the
token's user and `SoundboardWeb.Plugs.Tenant` resolved the guild, so every
action acts as `:current_user` in `:current_guild_id`.

- [SoundboardWeb.AuthController](SoundboardWeb.AuthController.md): Discord sign-in. A signed-out visitor who opened `/g/:slug` has that slug
kept in the session (`:pending_slug`), and lands on it after signing in.

- [SoundboardWeb.BillingController](SoundboardWeb.BillingController.md): Stripe subscriptions: plan options, checkout, customer portal, and the
public webhook receiver (signature-verified, no session auth).
- [SoundboardWeb.BillingHTML](SoundboardWeb.BillingHTML.md): Templates for the billing pages (plan options, storage usage, upgrade).

- [SoundboardWeb.Components.FlashComponent](SoundboardWeb.Components.FlashComponent.md): The flash component.

- [SoundboardWeb.Components.Layouts.Navbar](SoundboardWeb.Components.Layouts.Navbar.md): The navbar component. A plain function component so it renders in both
LiveViews and controller-rendered pages; the mobile menu toggles entirely
client-side via JS.

- [SoundboardWeb.Components.Soundboard.DeleteModal](SoundboardWeb.Components.Soundboard.DeleteModal.md): The delete modal component.

- [SoundboardWeb.Components.Soundboard.EditModal](SoundboardWeb.Components.Soundboard.EditModal.md): The edit modal component.

- [SoundboardWeb.Components.Soundboard.Helpers](SoundboardWeb.Components.Soundboard.Helpers.md): Helper functions for the soundboard.

- [SoundboardWeb.Components.Soundboard.TagComponents](SoundboardWeb.Components.Soundboard.TagComponents.md): Shared tag UI helpers for the soundboard modals.

- [SoundboardWeb.Components.Soundboard.UploadModal](SoundboardWeb.Components.Soundboard.UploadModal.md): The upload modal component.

- [SoundboardWeb.Components.Soundboard.VolumeControl](SoundboardWeb.Components.Soundboard.VolumeControl.md): Shared volume slider with preview support for upload/edit modals.

- [SoundboardWeb.CoreComponents](SoundboardWeb.CoreComponents.md): The flash notices and icons every page uses, and the JS commands that show
and hide them. Icons are [heroicons](https://heroicons.com), bundled into
app.css by the Tailwind plugin.

- [SoundboardWeb.Endpoint](SoundboardWeb.Endpoint.md)
- [SoundboardWeb.ErrorHTML](SoundboardWeb.ErrorHTML.md): Renders fallback HTML error messages.

- [SoundboardWeb.ErrorJSON](SoundboardWeb.ErrorJSON.md): Renders fallback JSON error payloads.

- [SoundboardWeb.FavoritesLive](SoundboardWeb.FavoritesLive.md)
- [SoundboardWeb.Gettext](SoundboardWeb.Gettext.md): A module providing Internationalization with a gettext-based API.
- [SoundboardWeb.GuildController](SoundboardWeb.GuildController.md): Tenant onboarding: list the guilds the shared bot is a member of and let the
signed-in user switch their active soundboard (creating the tenant row on
first use — that is the whole "provisioning" step).
- [SoundboardWeb.Live.Support.LiveTags](SoundboardWeb.Live.Support.LiveTags.md): LiveView-facing tag queries and mutations for the soundboard.

- [SoundboardWeb.Live.Support.PresenceLive](SoundboardWeb.Live.Support.PresenceLive.md)
- [SoundboardWeb.OnboardingController](SoundboardWeb.OnboardingController.md): The onboarding handoff for hosted signups. A signed-in user invites the
shared bot from here, then continues to `/guilds` where switching
provisions the tenant.

- [SoundboardWeb.Plugs.APIAuth](SoundboardWeb.Plugs.APIAuth.md): API authentication plug.

- [SoundboardWeb.Plugs.AppGate](SoundboardWeb.Plugs.AppGate.md): Gate for the soundboard app pages (Sounds, Stats, Favorites, Settings).
- [SoundboardWeb.Plugs.BasicAuth](SoundboardWeb.Plugs.BasicAuth.md): Basic authentication plug.
- [SoundboardWeb.Plugs.RoleCheck](SoundboardWeb.Plugs.RoleCheck.md): Re-checks a signed-in user's required Discord role at most every
`:role_recheck_interval_seconds` (default 15 minutes), and signs them out
when they no longer have it. Runs after `ensure_authenticated_user`, so
there is always a user.

- [SoundboardWeb.Plugs.Tenant](SoundboardWeb.Plugs.Tenant.md): Resolves the current tenant (guild) for a request.
- [SoundboardWeb.Presence](SoundboardWeb.Presence.md): The Presence module.

- [SoundboardWeb.PresenceHandler](SoundboardWeb.PresenceHandler.md): Handles presence tracking for the Soundboard app.

- [SoundboardWeb.RawBodyReader](SoundboardWeb.RawBodyReader.md): A `Plug.Parsers` body_reader that keeps the untouched JSON request body in
`conn.assigns[:raw_body]` (a list of chunks).
- [SoundboardWeb.Router](SoundboardWeb.Router.md): Routes. The app pages (Sounds, Stats, Favorites, Settings) need an active
subscription on hosted deployments (`:app_access`); self-hosted is always
unlocked. Setup pages (pick a guild, claim a subdomain, subscribe) stay
reachable while locked, since they are the way to unlock it; `:auth` only
tells the navbar whether to show the app's links.
- [SoundboardWeb.SettingsLive](SoundboardWeb.SettingsLive.md): API tokens and their docs, and, on hosted deployments, the guild's plan:
shown only when billing is configured and the signed-in user is the
Discord account that provisioned the guild.

- [SoundboardWeb.SoundHelpers](SoundboardWeb.SoundHelpers.md): Shared helpers for formatting sound metadata for UI rendering.

- [SoundboardWeb.Soundboard.SoundFilter](SoundboardWeb.Soundboard.SoundFilter.md): Filters sounds based on the selected tags and search query.

- [SoundboardWeb.SoundboardLive](SoundboardWeb.SoundboardLive.md)
- [SoundboardWeb.StatsLive](SoundboardWeb.StatsLive.md)
- [SoundboardWeb.Telemetry](SoundboardWeb.Telemetry.md)
- [SoundboardWeb.UploadController](SoundboardWeb.UploadController.md): Serves uploaded sound files to the signed-in user, for the browser's local
preview. Only the stored file of a sound in the current soundboard is
served; any other path, including another guild's sound, is a 404.

## Mix Tasks

- [mix credence](Mix.Tasks.Credence.md): Credence finds code that works but isn't written the Elixir way (a list
built only to be summed, a zip then a map) and rewrites it.
`mix credence` fixes each file it finds something in, in place, with
`Credence.fix/2`, and lists what it couldn't fix; `mix credence --check`
(precommit and CI) changes nothing and fails listing what it finds.

