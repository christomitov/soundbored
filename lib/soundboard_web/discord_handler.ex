defmodule SoundboardWeb.DiscordHandler do
  use Nostrum.Consumer
  require Logger

  alias Nostrum.Api
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Voice

  def handle_event({:VOICE_READY, payload, _ws_state}) do
    Logger.info("""
    Voice Ready Event:
    Guild ID: #{payload.guild_id}
    Channel ID: #{payload.channel_id}
    """)

    # Try to play any pending audio when voice is ready
    if voice_channel = Process.get(:pending_audio) do
      {guild_id, sound_path} = voice_channel
      Process.sleep(100)
      Voice.play(guild_id, sound_path, :url, volume: 1.0)
      Process.delete(:pending_audio)
    end

    :noop
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case msg.content do
      "!join" ->
        Logger.info("Join command received from user #{msg.author.username}")

        case get_user_voice_channel(msg.guild_id, msg.author.id) do
          nil ->
            Logger.warning("No voice channel found for user #{msg.author.username}")
            Api.create_message(msg.channel_id, "You need to be in a voice channel!")

          channel_id ->
            Logger.info("Found voice channel: #{inspect(channel_id)}")

            # Store the current voice channel info in the Discord Handler process
            Process.put(:current_voice_channel, {msg.guild_id, channel_id})
            Voice.join_channel(msg.guild_id, channel_id)

            # Also store it in the AudioPlayer process
            GenServer.cast(
              SoundboardWeb.AudioPlayer,
              {:set_voice_channel, msg.guild_id, channel_id}
            )

            # Send web interface URL
            scheme = System.get_env("SCHEME")

            web_url =
              Application.get_env(:soundboard, SoundboardWeb.Endpoint)[:url][:host] || "localhost"

            url = "#{scheme}://#{web_url}"

            Api.create_message(msg.channel_id, """
            Joined your voice channel!
            Access the soundboard here: #{url}
            """)
        end

      "!leave" ->
        if msg.guild_id do
          Process.delete(:current_voice_channel)
          Voice.leave_channel(msg.guild_id)
          Api.create_message(msg.channel_id, "Left the voice channel!")
        end

      _ ->
        :ignore
    end
  end

  def handle_event({:VOICE_STATE_UPDATE, _payload, _ws_state}) do
    :noop
  end

  def handle_event({:VOICE_SERVER_UPDATE, _payload, _ws_state}) do
    :noop
  end

  def handle_event({:VOICE_SPEAKING_UPDATE, _payload, _ws_state}) do
    :noop
  end

  def handle_event(event) do
    try do
      # Logger.debug("Received Discord event: #{inspect(event, pretty: true)}")
      :noop
    rescue
      e ->
        Logger.error(
          "Error handling Discord event: #{Exception.format(:error, e, __STACKTRACE__)}",
          error_code: :event_handler_error,
          event: event
        )

        :noop
    end
  end

  defp get_user_voice_channel(guild_id, user_id) do
    guild = GuildCache.get!(guild_id)

    case Enum.find(guild.voice_states, fn vs -> vs.user_id == user_id end) do
      nil -> nil
      voice_state -> voice_state.channel_id
    end
  end

  def get_current_voice_channel do
    Process.get(:current_voice_channel)
  end
end
