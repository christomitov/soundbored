defmodule Soundboard.PubSubTopics do
  @moduledoc """
  Helpers for building consistent PubSub topics per tenant.
  """
  @stats_prefix "stats:"
  @soundboard_prefix "soundboard:"

  def stats_topic(tenant_id), do: build(@stats_prefix, tenant_id)
  def soundboard_topic(tenant_id), do: build(@soundboard_prefix, tenant_id)

  defp build(prefix, tenant_id) when is_integer(tenant_id) do
    prefix <> Integer.to_string(tenant_id)
  end

  defp build(prefix, tenant_id) when is_binary(tenant_id) do
    prefix <> tenant_id
  end
end
