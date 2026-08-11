defmodule Soundboard.Discord.Invite do
  @moduledoc """
  Builds the Discord bot invite URL and reports whether the bot is already in a guild.
  """

  alias Soundboard.Discord.GuildCache

  # View Channels | Send Messages | Read Message History | Connect | Speak
  @bot_permissions 3_214_336

  @spec url() :: String.t() | nil
  def url do
    case client_id() do
      id when is_binary(id) and id != "" ->
        "https://discord.com/api/oauth2/authorize?" <>
          URI.encode_query(%{
            "client_id" => id,
            "permissions" => Integer.to_string(@bot_permissions),
            "scope" => "bot"
          })

      _ ->
        nil
    end
  end

  @spec in_guild?() :: boolean()
  def in_guild? do
    case GuildCache.all() do
      [_ | _] -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp client_id do
    Application.get_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth)[:client_id]
  end
end
