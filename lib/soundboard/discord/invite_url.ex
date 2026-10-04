defmodule Soundboard.Discord.InviteURL do
  @moduledoc """
  Builds the bot invite URL used by the onboarding flow.

  The shared bot only needs to see the channels it is invited to, connect to
  voice, and speak. The permissions integer is pinned by a test in
  `SoundboardWeb.OnboardingTest` so the scope cannot drift silently.
  """

  import Bitwise

  @view_channel 1 <<< 10
  @connect 1 <<< 20
  @speak 1 <<< 3

  @permissions @view_channel ||| @connect ||| @speak

  @spec permissions() :: non_neg_integer()
  def permissions, do: @permissions

  @spec build(String.t() | nil) :: String.t()
  def build(client_id \\ configured_client_id()) do
    "https://discord.com/oauth2/authorize" <>
      "?client_id=#{client_id}" <>
      "&permissions=#{@permissions}" <>
      "&scope=bot%20applications.commands"
  end

  defp configured_client_id do
    Application.get_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth, [])
    |> Keyword.get(:client_id)
  end
end
