defmodule Soundboard.Discord.Handler.CommandHandler do
  @moduledoc false

  alias Soundboard.Discord.Handler.VoiceRuntime
  alias Soundboard.Discord.Message
  alias Soundboard.PublicURL

  @join_failed "I couldn't join your voice channel. Try again in a moment."
  @leave_failed "I couldn't leave the voice channel. Try again in a moment."

  def handle_message(%{content: "!join"} = msg) do
    case VoiceRuntime.user_voice_channel(msg.guild_id, msg.author.id) do
      nil ->
        Message.create(msg.channel_id, "You need to be in a voice channel!")

      channel_id ->
        case VoiceRuntime.join_voice_channel(msg.guild_id, channel_id) do
          :ok -> Message.create(msg.channel_id, joined_message())
          {:error, _reason} -> Message.create(msg.channel_id, @join_failed)
        end
    end
  end

  def handle_message(%{content: "!leave", guild_id: nil}), do: :ignore

  def handle_message(%{content: "!leave", guild_id: guild_id, channel_id: channel_id}) do
    case VoiceRuntime.leave_voice_channel(guild_id) do
      :ok -> Message.create(channel_id, "Left the voice channel!")
      {:error, _reason} -> Message.create(channel_id, @leave_failed)
    end
  end

  def handle_message(_msg), do: :ignore

  defp joined_message do
    url = PublicURL.current()

    """
    Joined your voice channel!
    Access the soundboard here: #{url}
    """
  end
end
