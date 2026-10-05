defmodule SoundboardWeb.BillingHTML do
  @moduledoc """
  Templates for the billing pages (plan options, storage usage, upgrade).
  """

  use SoundboardWeb, :html

  embed_templates "billing_html/*"

  @doc "Storage cap for a tier atom (:pro/:studio), used for upgrade/downgrade math."
  def current_tier_cap(tier) do
    Enum.find_value(Soundboard.Billing.tiers(), fn t ->
      if t.name |> String.downcase() |> String.to_atom() == tier, do: t.cap_bytes
    end)
  end

  @doc "Checkout button label by relationship to the current plan."
  def cta_label(state) do
    case state do
      :upgrade -> "Upgrade"
      :downgrade -> "Downgrade"
      _ -> "Subscribe"
    end
  end

  @doc "Label for change-plan (existing subscription) buttons, per billing interval."
  def form_label(state, interval) do
    case state do
      :upgrade -> "Upgrade"
      :downgrade -> "Downgrade"
      _ -> "Switch to #{interval}"
    end
  end
end
