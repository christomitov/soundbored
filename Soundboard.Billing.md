# `Soundboard.Billing`

Stripe-backed storage subscriptions for guild tenants.

Dormancy: billing is dormant unless `STRIPE_SECRET_KEY` is set. Everything in
this module gates on `configured?/0`; when Stripe is unconfigured the app
behaves exactly as it did before billing existed (provisioning happens on
guild switch, every tenant gets the platform default storage cap).

Plan catalog (price ids come from env, see `config/runtime.exs`):

| Tier   | Cap    | Monthly | Yearly |
|--------|--------|---------|--------|
| Pro    | 1 GB   | $4      | $36    |
| Studio | 5 GB   | $10     | $96    |

The price-id -> cap mapping lives here (`plan_cap/1`) and is the single
source of truth; the webhook is the only hosted provisioning path (it
provisions the tenant row via `Tenants.get_or_create_guild/2` and writes
`max_storage_bytes`), so a guild can never get a paid cap without a Stripe
payment event.

## Idempotency

Stripe retries webhook deliveries until they are acked, so events must be
processed at most once. Processed event ids are remembered in a public ETS
table (`:billing_processed_events`). Tradeoff: ETS is in-memory, so a node
restart forgets the set and Stripe retries arriving across a restart could
replay an event. That is safe here because every handler is an absolute
write (set the cap to the plan's cap, not an increment), so replays are
no-ops; the ETS set just avoids redundant work in the common case.

Stripe customer ids seen on events are kept in a second ETS table
(`:billing_stripe_customers`) so the customer portal can be opened without
a `stripe_customer_id` column on `guilds`. Also in-memory: after a restart
the portal is unavailable until the next event repopulates it.

# `cancel_subscription`

```elixir
@spec cancel_subscription(String.t() | term()) ::
  {:ok, %{cancel_at: non_neg_integer() | nil}}
  | {:error, :not_configured | :no_subscription | term()}
```

Flags the guild's subscription to cancel at the end of the current billing
period (Stripe keeps it active until then; customer.subscription.deleted
later reverts the guild to no plan).

# `change_subscription_price`

```elixir
@spec change_subscription_price(String.t() | term(), String.t()) ::
  {:ok, :updated}
  | {:error, :not_configured | :no_subscription | :invalid_price | term()}
```

Moves the guild's live subscription to another price (tier or interval
change). Stripe prorates automatically; the subscription.updated webhook
applies the new cap.

# `config`

Billing configuration (set in `config/runtime.exs` from STRIPE_* env vars).

# `configured?`

Whether Stripe billing is active (STRIPE_SECRET_KEY present).

# `create_checkout_session`

```elixir
@spec create_checkout_session(String.t() | term(), String.t(), term(), keyword()) ::
  {:ok, %{id: String.t(), url: String.t() | nil}} | {:error, term()}
```

Creates a Stripe Checkout Session for `guild_id` at `price_id`.

The session carries the guild id in `client_reference_id` (Stripe's
reconciliation key) and in metadata (read back by the webhook). The price id
is also mirrored into metadata because checkout session payloads do not
include line items unless they are expanded.

Returns `{:ok, %{id: id, url: url}}` or `{:error, :not_configured |
:invalid_price | term()}`.

# `create_portal_session`

```elixir
@spec create_portal_session(
  String.t() | term(),
  keyword()
) ::
  {:ok, %{url: String.t()}} | {:error, :not_configured | :no_customer | term()}
```

Creates a Stripe customer portal session for the guild's customer. Requires
the guild to have a customer id already seen on a billing webhook event
(kept in-memory; see the module doc).

# `current_price_id_for_guild`

```elixir
@spec current_price_id_for_guild(String.t() | term()) :: String.t() | nil
```

The price id last seen on the guild's subscription, or nil.

# `customer_id_for_guild`

```elixir
@spec customer_id_for_guild(String.t() | term()) :: String.t() | nil
```

The Stripe customer id last seen for a guild, or nil.

# `format_bytes`

```elixir
@spec format_bytes(non_neg_integer()) :: String.t()
```

Bytes formatted for display: MB up to 1000 MB, then GB.

# `format_price`

```elixir
@spec format_price(pos_integer()) :: String.t()
```

Cents to a display price like "$3.99".

# `handle_event`

```elixir
@spec handle_event(map()) :: :ok | {:error, term()}
```

Handles a decoded Stripe event map. Public for direct unit testing.

# `handle_webhook`

```elixir
@spec handle_webhook(binary(), String.t() | nil) ::
  {:ok, String.t() | :duplicate} | {:error, term()}
```

Verifies the Stripe signature header, then dispatches the event.

Returns `{:ok, event_id | :duplicate}` on success (both ack the delivery),
`{:error, :invalid_signature}` for tampered/foreign payloads, or
`{:error, term()}` for malformed payloads / handler failures.

# `interval_for_price`

```elixir
@spec interval_for_price(String.t() | nil) :: :monthly | :yearly | nil
```

Maps a known plan price id to its billing interval (:monthly/:yearly), or nil.

# `known_subscription?`

```elixir
@spec known_subscription?(String.t() | term()) :: boolean()
```

Whether the guild has a Stripe subscription we can act on. Falls back to a
Stripe lookup by remembered customer when in-memory state is missing (e.g.
after a restart, or events processed by older code).

# `plan_cap`

```elixir
@spec plan_cap(String.t() | nil) :: non_neg_integer() | nil
```

The storage cap in bytes for a Stripe price id, or nil when unknown.

# `plan_for_cap`

```elixir
@spec plan_for_cap(non_neg_integer() | nil) :: :studio | :pro | nil
```

The plan a storage cap belongs to: :studio, :pro, or nil.

# `plan_label`

```elixir
@spec plan_label(non_neg_integer() | nil) :: String.t()
```

Human plan name for a cap value.

# `price_cap_map`

```elixir
@spec price_cap_map() :: %{required(String.t()) =&gt; pos_integer()}
```

Maps every configured Stripe price id to its storage cap in bytes. This is
the single source of truth for the price -> plan mapping.

# `remember_subscription`

```elixir
@spec remember_subscription(
  String.t() | term(),
  Soundboard.Billing.SubscriptionSnapshot.t()
) :: :ok
```

Caches the guild's subscription state (id, item, price) in memory.

# `reset_memory`

Clears in-memory billing state (processed events, customer ids). Test and
ops helper; production state is intentionally reconstructible (see the
module doc on idempotency).

# `subscription_active?`

```elixir
@spec subscription_active?(String.t() | term()) :: boolean()
```

Whether a guild has an active subscription: a tenant row whose storage cap
exactly matches a paid plan (the webhook only writes exact plan caps).
Rows with cap 0, legacy/default caps, or no row at all count as unpaid —
on hosted there is no free tier; self-hosted never reaches this check
because the paywall gate short-circuits when billing is dormant.

# `subscription_id_for_guild`

```elixir
@spec subscription_id_for_guild(String.t() | term()) :: String.t() | nil
```

The Stripe subscription id last seen for a guild, or nil.

# `tiers`

Plan catalog entries for display (name, cap, amounts, configured price ids).

# `valid_price?`

Whether the price id belongs to the configured plan catalog.

# `verify_webhook_signature`

```elixir
@spec verify_webhook_signature(
  binary(),
  String.t() | nil,
  String.t() | nil,
  pos_integer()
) ::
  :ok | {:error, :invalid_signature | :not_configured}
```

Verifies a Stripe webhook signature header (`t=...,v1=...`) against
`payload` using HMAC-SHA256. Verified locally instead of via
`Stripe.Webhook.construct_event/3` so the boundary is testable without
network or Stripe SDK behavior drift.

# `webhook_configured?`

Whether webhook signature verification is possible.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
