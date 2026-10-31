# `Soundboard.Billing.SubscriptionSnapshot`

The guild's live Stripe subscription state cached in memory between
webhooks: the subscription id, its line item id, and the price id.

# `t`

```elixir
@type t() :: %Soundboard.Billing.SubscriptionSnapshot{
  id: String.t(),
  item_id: String.t() | nil,
  price_id: String.t() | nil
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
