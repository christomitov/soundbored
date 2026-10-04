defmodule SoundboardWeb.BillingHTML do
  @moduledoc """
  Templates for the billing pages (plan options, storage usage, upgrade).
  """

  use SoundboardWeb, :html

  embed_templates "billing_html/*"
end
