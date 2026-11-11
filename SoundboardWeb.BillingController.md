# `SoundboardWeb.BillingController`

Stripe subscriptions: plan options, checkout, customer portal, and the
public webhook receiver (signature-verified, no session auth).

Only a guild's owner (`Soundboard.Tenants.Membership.owner?/2`) may open
its portal, change or cancel its plan, or start a checkout for it once it
has an owner; a new guild can be subscribed by the member who picked it.

The webhook signature is computed over the raw request bytes, so the
webhook reads the untouched JSON body that `SoundboardWeb.RawBodyReader`
kept in `:raw_body`, never re-encoded JSON.

# `cancel`

Cancels the session guild's subscription at period end.

# `change`

Switches the session guild's subscription to another price (tier or interval).

# `checkout`

Starts Stripe Checkout. The guild id comes from the session's pending
billing guild (set when a switch to an unpaid guild was gated) or the
picked soundboard (a tenant row, not the default-guild fallback); with
neither, the user is sent to pick one. `Billing` puts it into
`client_reference_id` and metadata so the webhook can provision the right
tenant.

# `index`

# `portal`

Opens the Stripe customer portal for the session's guild.

# `webhook`

Public Stripe webhook receiver. No session auth — the Stripe signature
header is the credential. Bad signatures and malformed payloads get a 400;
duplicates get a 200 so Stripe stops retrying.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
