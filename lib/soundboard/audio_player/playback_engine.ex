defmodule Soundboard.AudioPlayer.PlaybackEngine do
  @moduledoc false

  require Logger

  alias Soundboard.Accounts.User
  alias Soundboard.AudioPlayer
  alias Soundboard.AudioPlayer.SoundLibrary
  alias Soundboard.Discord.Voice

  @system_users ["System", "API User"]
  @rtp_probe_poll_ms 20
  @rtp_probe_default_timeout_ms 6_000
  @voice_not_ready_retry_ms 350
  @voice_ready_poll_ms 100
  @voice_ready_timeout_ms 4_000
  @voice_ready_fast_timeout_ms 1_200
  @voice_settle_ms 120
  @rejoin_retry_threshold 3
  @max_play_attempts 20

  def play(guild_id, channel_id, sound_name, path_or_url, volume, username) do
    join_state = ensure_joined_channel(guild_id, channel_id)
    maybe_settle_before_play(join_state)
    play_sound_with_connection(guild_id, sound_name, path_or_url, volume, username)
  end

  defp maybe_settle_before_play({:joined, :ok}) do
    Process.sleep(@voice_settle_ms)
  end

  defp maybe_settle_before_play(_), do: :ok

  defp play_sound_with_connection(guild_id, sound_name, path_or_url, volume, username) do
    if is_nil(System.find_executable("ffmpeg")) do
      Logger.error("ffmpeg not found in PATH. Cannot play #{sound_name}")
      broadcast_error("ffmpeg is not installed on this host")
      :error
    else
      {play_input, play_type} = SoundLibrary.prepare_play_input(sound_name, path_or_url)

      Logger.info(
        "Calling Voice.play with guild_id: #{guild_id}, input: #{play_input}, type: #{play_type}"
      )

      Logger.info(
        "Voice channel: #{inspect(Voice.channel_id(guild_id))}, Playing: #{Voice.playing?(guild_id)}"
      )

      play_options = [volume: clamp_volume(volume)]
      Logger.info("Play options: #{inspect(play_options)}")

      play_with_retries(
        guild_id,
        play_input,
        play_type,
        play_options,
        sound_name,
        username,
        0,
        false
      )
    end
  end

  defp play_with_retries(
         guild_id,
         play_input,
         play_type,
         play_options,
         sound_name,
         username,
         attempt,
         refresh_attempted
       )
       when attempt < @max_play_attempts do
    case Voice.play(guild_id, play_input, play_type, play_options) do
      :ok ->
        Logger.info("Voice.play succeeded for #{sound_name} (attempt #{attempt + 1})")
        maybe_probe_first_rtp(guild_id, sound_name, attempt + 1)
        track_play_if_needed(sound_name, username)
        broadcast_success(sound_name, username)
        :ok

      {:error, "Audio already playing in voice channel."} ->
        Logger.warning("Audio still playing on attempt #{attempt + 1}, stopping and retrying...")
        Voice.stop(guild_id)
        Process.sleep(50)

        play_with_retries(
          guild_id,
          play_input,
          play_type,
          play_options,
          sound_name,
          username,
          attempt + 1,
          refresh_attempted
        )

      {:error, "Must be connected to voice channel to play audio."} ->
        Logger.warning("Voice reported not connected, waiting before retry...")

        refresh_attempted =
          maybe_trigger_rejoin(guild_id, attempt, refresh_attempted, false)

        Process.sleep(@voice_not_ready_retry_ms)

        play_with_retries(
          guild_id,
          play_input,
          play_type,
          play_options,
          sound_name,
          username,
          attempt + 1,
          refresh_attempted
        )

      {:error, "Voice session is still negotiating encryption."} ->
        Logger.warning(
          "Voice encryption not ready yet, waiting #{@voice_not_ready_retry_ms}ms before retry..."
        )

        refresh_attempted =
          maybe_trigger_rejoin(guild_id, attempt, refresh_attempted, true)

        Process.sleep(@voice_not_ready_retry_ms)

        play_with_retries(
          guild_id,
          play_input,
          play_type,
          play_options,
          sound_name,
          username,
          attempt + 1,
          refresh_attempted
        )

      {:error, reason} ->
        Logger.error("Voice.play failed: #{inspect(reason)} (attempt #{attempt + 1})")
        broadcast_error("Failed to play sound: #{reason}")
        :error
    end
  end

  defp play_with_retries(
         _guild_id,
         _play_input,
         _play_type,
         _play_options,
         sound_name,
         _username,
         attempt,
         _refresh_attempted
       ) do
    Logger.error("Exceeded max retries (#{attempt}) for playing #{sound_name}")
    broadcast_error("Failed to play sound after multiple attempts")
    :error
  end

  defp maybe_trigger_rejoin(guild_id, attempt, refresh_attempted, force_refresh) do
    if attempt >= @rejoin_retry_threshold and not refresh_attempted do
      maybe_rejoin_current_channel(guild_id, force_refresh)
      true
    else
      refresh_attempted
    end
  end

  defp maybe_rejoin_current_channel(guild_id, force_refresh) do
    case AudioPlayer.current_voice_channel() do
      {^guild_id, channel_id} ->
        maybe_rejoin_for_channel(guild_id, channel_id, force_refresh)

      _ ->
        :ok
    end

    :ok
  rescue
    _ -> :ok
  end

  defp maybe_rejoin_for_channel(guild_id, channel_id, true) do
    joined? = Voice.channel_id(guild_id) == to_string(channel_id)
    ready? = safe_voice_ready(guild_id)

    cond do
      joined? and not ready? ->
        refresh_voice_session(guild_id, channel_id)

      joined? and ready? ->
        Logger.debug("Skipping refresh; voice already ready in channel #{channel_id}")

      true ->
        rejoin_voice_channel(guild_id, channel_id)
    end
  end

  defp maybe_rejoin_for_channel(guild_id, channel_id, false) do
    joined? = Voice.channel_id(guild_id) == to_string(channel_id)
    ready? = safe_voice_ready(guild_id)

    if joined? and ready? do
      Logger.debug("Skipping rejoin; already in voice channel #{channel_id}")
    else
      rejoin_voice_channel(guild_id, channel_id)
    end
  end

  defp refresh_voice_session(guild_id, channel_id) do
    Logger.info("Refreshing voice session in channel #{channel_id} with in-place rejoin")
    Voice.join_channel(guild_id, channel_id)
    wait_for_voice_ready(guild_id)
  end

  defp rejoin_voice_channel(guild_id, channel_id) do
    Logger.info("Rejoining voice channel #{channel_id}")
    Voice.join_channel(guild_id, channel_id)
    wait_for_voice_ready(guild_id)
  end

  defp ensure_joined_channel(guild_id, channel_id) do
    if Voice.channel_id(guild_id) == to_string(channel_id) do
      {:already_joined, wait_for_voice_ready(guild_id, @voice_ready_fast_timeout_ms)}
    else
      Logger.info("Joining voice channel #{channel_id}")
      Voice.join_channel(guild_id, channel_id)
      Process.sleep(150)
      {:joined, wait_for_voice_ready(guild_id)}
    end
  end

  defp maybe_probe_first_rtp(guild_id, sound_name, attempt_number) do
    if Application.get_env(:soundboard, :voice_rtp_probe, false) do
      timeout_ms =
        Application.get_env(
          :soundboard,
          :voice_rtp_probe_timeout_ms,
          @rtp_probe_default_timeout_ms
        )

      initial_seq = current_rtp_sequence(guild_id)
      started_at = System.monotonic_time(:millisecond)

      Task.start(fn ->
        wait_for_first_rtp(
          guild_id,
          sound_name,
          attempt_number,
          initial_seq,
          started_at,
          timeout_ms
        )
      end)
    end

    :ok
  end

  defp wait_for_first_rtp(
         guild_id,
         sound_name,
         attempt_number,
         initial_seq,
         started_at,
         timeout_ms
       ) do
    elapsed_ms = System.monotonic_time(:millisecond) - started_at
    current_seq = current_rtp_sequence(guild_id)

    cond do
      is_integer(initial_seq) and is_integer(current_seq) and current_seq != initial_seq ->
        Logger.info(
          "RTP probe: first packet for #{sound_name} after #{elapsed_ms}ms " <>
            "(attempt #{attempt_number}, seq #{initial_seq} -> #{current_seq})"
        )

      is_nil(initial_seq) and is_integer(current_seq) ->
        Logger.info(
          "RTP probe: sequence initialized for #{sound_name} after #{elapsed_ms}ms " <>
            "(attempt #{attempt_number}, seq #{current_seq})"
        )

      elapsed_ms >= timeout_ms ->
        {channel, playing} = safe_voice_status(guild_id)

        Logger.warning(
          "RTP probe: no progress for #{sound_name} within #{timeout_ms}ms " <>
            "(attempt #{attempt_number}, initial_seq=#{inspect(initial_seq)}, " <>
            "current_seq=#{inspect(current_seq)}, channel=#{inspect(channel)}, playing=#{playing})"
        )

      true ->
        Process.sleep(@rtp_probe_poll_ms)

        wait_for_first_rtp(
          guild_id,
          sound_name,
          attempt_number,
          initial_seq,
          started_at,
          timeout_ms
        )
    end
  end

  defp wait_for_voice_ready(guild_id, timeout_ms \\ @voice_ready_timeout_ms) do
    started_at = System.monotonic_time(:millisecond)
    do_wait_for_voice_ready(guild_id, started_at, timeout_ms)
  end

  defp do_wait_for_voice_ready(guild_id, started_at, timeout_ms) do
    cond do
      safe_voice_ready(guild_id) ->
        :ok

      System.monotonic_time(:millisecond) - started_at >= timeout_ms ->
        Logger.warning(
          "Timed out waiting for voice readiness in guild #{guild_id} " <>
            "(channel=#{inspect(safe_voice_channel(guild_id))})"
        )

        :timeout

      true ->
        Process.sleep(@voice_ready_poll_ms)
        do_wait_for_voice_ready(guild_id, started_at, timeout_ms)
    end
  end

  defp current_rtp_sequence(guild_id) do
    case Voice.get_voice(guild_id) do
      %{rtp_sequence: seq} when is_integer(seq) -> seq
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp safe_voice_status(guild_id) do
    {safe_voice_channel(guild_id), safe_voice_playing(guild_id)}
  end

  defp safe_voice_ready(guild_id) do
    Voice.ready?(guild_id)
  rescue
    _ -> false
  end

  defp safe_voice_channel(guild_id) do
    Voice.channel_id(guild_id)
  rescue
    _ -> :unknown
  end

  defp safe_voice_playing(guild_id) do
    {:ok, Voice.playing?(guild_id)}
  rescue
    _ -> :error
  end

  defp track_play_if_needed(sound_name, username) do
    if system_user?(username) do
      Logger.info("Skipping play tracking for system user: #{username}")
    else
      case Soundboard.Repo.get_by(User, username: username) do
        %{id: user_id} -> Soundboard.Stats.track_play(sound_name, user_id)
        nil -> Logger.warning("Could not find user_id for #{username}")
      end
    end
  end

  defp broadcast_success(sound_name, username) do
    Phoenix.PubSub.broadcast(
      Soundboard.PubSub,
      "soundboard",
      {:sound_played, %{filename: sound_name, played_by: username}}
    )
  end

  defp broadcast_error(message) do
    Phoenix.PubSub.broadcast(
      Soundboard.PubSub,
      "soundboard",
      {:error, message}
    )
  end

  defp clamp_volume(value) when is_number(value) do
    value
    |> max(0.0)
    |> min(1.5)
    |> Float.round(4)
  end

  defp clamp_volume(_), do: 1.0

  defp system_user?(username), do: username in @system_users
end
