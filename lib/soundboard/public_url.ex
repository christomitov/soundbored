defmodule Soundboard.PublicURL do
  @moduledoc """
  Shared helper for the application's externally visible base URL.

  Web and Discord-facing features use this so URL generation follows one
  application-level contract instead of reaching into endpoint config details in
  multiple places.
  """

  def current, do: SoundboardWeb.Endpoint.url()

  def from_uri_or_current(nil), do: current()

  def from_uri_or_current(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host, port: port} when is_binary(scheme) and is_binary(host) ->
        scheme <> "://" <> host <> port_suffix(scheme, port)

      _ ->
        current()
    end
  end

  defp port_suffix("http", 80), do: ""
  defp port_suffix("https", 443), do: ""
  defp port_suffix(_scheme, nil), do: ""
  defp port_suffix(_scheme, port), do: ":#{port}"
end
