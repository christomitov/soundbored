defmodule Soundboard.Discord.Handler.CommandHandler do
  @moduledoc false

  alias Soundboard.Discord.Handler.VoiceRuntime
  alias Soundboard.Discord.Message

  def handle_message(%{content: "!join"} = msg) do
    case VoiceRuntime.user_voice_channel(msg.guild_id, msg.author.id) do
      nil ->
        Message.create(msg.channel_id, "You need to be in a voice channel!")

      channel_id ->
        VoiceRuntime.join_voice_channel(msg.guild_id, channel_id)
        Message.create(msg.channel_id, joined_message())
    end
  end

  def handle_message(%{content: "!leave", guild_id: guild_id, channel_id: channel_id})
      when not is_nil(guild_id) do
    VoiceRuntime.leave_voice_channel(guild_id)
    Message.create(channel_id, "Left the voice channel!")
  end

  def handle_message(_msg), do: :ignore

  defp joined_message do
    scheme = System.get_env("SCHEME")
    web_url = Application.get_env(:soundboard, SoundboardWeb.Endpoint)[:url][:host] || "localhost"
    url = "#{scheme}://#{web_url}"

    """
    Joined your voice channel!
    Access the soundboard here: #{url}
    """
  end
end
