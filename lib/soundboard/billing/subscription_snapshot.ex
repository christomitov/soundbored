defmodule Soundboard.Billing.SubscriptionSnapshot do
  @moduledoc """
  The guild's live Stripe subscription state cached in memory between
  webhooks: the subscription id, its line item id, and the price id.
  """

  defstruct [:id, :item_id, :price_id]

  @type t :: %__MODULE__{
          id: String.t(),
          item_id: String.t() | nil,
          price_id: String.t() | nil
        }
end
