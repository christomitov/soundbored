defmodule Soundboard.VideoPlayer.DiscordAudio do
  @moduledoc false

  require Logger

  alias Soundboard.Accounts.User
  alias Soundboard.AudioPlayer
  alias Soundboard.Discord.Voice

  @guild_key {__MODULE__, :guild_id}

  @spec play_from(String.t(), non_neg_integer(), User.t() | String.t() | nil) ::
          :ok | {:error, String.t()}
  def play_from(media_path, start_at_ms, actor)
      when is_binary(media_path) and is_integer(start_at_ms) and start_at_ms >= 0 do
    AudioPlayer.clear_playback()

    with {:ok, voice_channel} <- AudioPlayer.ensure_voice_channel(actor),
         {:ok, play_path} <- prepare_input(media_path, start_at_ms),
         :ok <- ensure_ready(voice_channel) do
      {guild_id, _channel_id} = voice_channel
      Voice.stop(guild_id)

      case Voice.play(guild_id, play_path, :url, volume: 1.0) do
        :ok ->
          remember_guild(guild_id)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec stop() :: :ok
  def stop do
    guild_ids =
      [Process.get(@guild_key), voice_channel_guild()]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.each(guild_ids, fn guild_id ->
      Logger.info("Stopping Discord video audio for guild #{guild_id}")
      Voice.stop(guild_id)
    end)

    Process.delete(@guild_key)
    :ok
  end

  @doc false
  @spec stop_tracked() :: :ok
  def stop_tracked do
    case Process.get(@guild_key) do
      nil ->
        :ok

      guild_id ->
        Logger.info("Suspending Discord video audio for guild #{guild_id}")
        Voice.stop(guild_id)
    end

    Process.delete(@guild_key)
    :ok
  end

  defp remember_guild(guild_id), do: Process.put(@guild_key, guild_id)

  defp voice_channel_guild do
    case AudioPlayer.current_voice_channel() do
      {:ok, {guild_id, _}} -> guild_id
      _ -> nil
    end
  end

  defp ensure_ready({guild_id, _channel_id}) do
    if Voice.ready?(guild_id) do
      :ok
    else
      # Auto-join needs a bit longer for Discord voice handshake.
      wait_until_ready(guild_id, 80)
    end
  end

  defp wait_until_ready(_guild_id, 0),
    do: {:error, "Voice session is still negotiating encryption."}

  defp wait_until_ready(guild_id, attempts) do
    if Voice.ready?(guild_id) do
      :ok
    else
      Process.sleep(100)
      wait_until_ready(guild_id, attempts - 1)
    end
  end

  defp prepare_input(media_path, 0), do: {:ok, media_path}

  defp prepare_input(media_path, start_at_ms) do
    case Soundboard.SystemCmd.configured_executable(:ffmpeg_executable, "ffmpeg") do
      nil ->
        {:error, "ffmpeg is not installed on this host"}

      exe ->
        extract_seeked_audio(exe, media_path, start_at_ms)
    end
  end

  defp extract_seeked_audio(exe, media_path, start_at_ms) do
    start_seconds = start_at_ms / 1000
    out_path = seeked_audio_path(media_path, start_at_ms)

    # Place -ss after -i for frame-accurate seeks so Discord matches HLS currentTime.
    args = [
      "-y",
      "-i",
      media_path,
      "-ss",
      :erlang.float_to_binary(start_seconds * 1.0, decimals: 3),
      "-vn",
      "-c:a",
      "aac",
      "-ac",
      "2",
      out_path
    ]

    case cmd().(exe, args, stderr_to_stdout: true, timeout: 120_000) do
      {_, 0} -> verify_seeked_audio(out_path)
      {output, code} -> seek_error(output, code)
    end
  end

  defp verify_seeked_audio(path) do
    if File.regular?(path), do: {:ok, path}, else: {:error, "Seeked audio missing"}
  end

  defp seek_error(output, code) do
    Logger.warning("ffmpeg seek extract failed (#{code}): #{String.slice(output, 0, 300)}")
    {:error, "Failed to seek Discord audio"}
  end

  defp seeked_audio_path(media_path, start_at_ms) do
    dir = Path.dirname(media_path)
    Path.join(dir, "discord_seek_#{start_at_ms}.m4a")
  end

  defp cmd do
    Application.get_env(:soundboard, :ffmpeg_cmd, &Soundboard.SystemCmd.run/3)
  end
end
