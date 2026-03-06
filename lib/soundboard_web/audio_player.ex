defmodule SoundboardWeb.AudioPlayer do
  @moduledoc """
  Handles the audio playback.
  """
  use GenServer
  require Logger
  alias Soundboard.Accounts.User
  alias Soundboard.Discord.Voice
  alias Soundboard.Sound

  # System users that don't need play tracking
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
  @interrupt_watchdog_ms 35
  @interrupt_watchdog_max_attempts 20

  defmodule State do
    @moduledoc """
    The state of the audio player.
    """
    defstruct [
      :voice_channel,
      :current_playback,
      :pending_request,
      :interrupting,
      :interrupt_watchdog_ref,
      :interrupt_watchdog_attempt
    ]
  end

  # Client API
  def start_link(_opts) do
    Logger.info("Starting AudioPlayer GenServer")
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  def play_sound(sound_name, username) do
    Logger.info("Received play_sound request for: #{sound_name} from #{username}")
    GenServer.cast(__MODULE__, {:play_sound, sound_name, username})
  end

  def stop_sound do
    Logger.info("Stopping all sounds")
    GenServer.cast(__MODULE__, :stop_sound)
  end

  def set_voice_channel(guild_id, channel_id) do
    Logger.info("Setting voice channel - Guild: #{guild_id}, Channel: #{channel_id}")
    GenServer.cast(__MODULE__, {:set_voice_channel, guild_id, channel_id})
  end

  def playback_finished(guild_id) do
    GenServer.cast(__MODULE__, {:playback_finished, guild_id})
  end

  def current_voice_channel do
    GenServer.call(__MODULE__, :get_voice_channel)
  rescue
    _ -> nil
  end

  # Server Callbacks
  @impl true
  def init(state) do
    Logger.info("Initializing AudioPlayer with state: #{inspect(state)}")
    # Create a fast in-memory cache for sound metadata
    ensure_sound_cache()
    # Schedule periodic voice connection check
    schedule_voice_check()

    {:ok,
     %{
       state
       | current_playback: nil,
         pending_request: nil,
         interrupting: false,
         interrupt_watchdog_ref: nil,
         interrupt_watchdog_attempt: 0
     }}
  end

  @impl true
  def handle_cast({:set_voice_channel, guild_id, channel_id}, state) do
    # Handle nil values properly - set to nil instead of {nil, nil}
    voice_channel =
      if is_nil(guild_id) or is_nil(channel_id) do
        nil
      else
        {guild_id, channel_id}
      end

    next_state =
      case voice_channel do
        nil ->
          state
          |> clear_current_playback()
          |> Map.merge(%{
            voice_channel: nil,
            pending_request: nil,
            interrupting: false,
            interrupt_watchdog_attempt: 0
          })

        _ ->
          %{state | voice_channel: voice_channel}
      end

    {:noreply, next_state}
  end

  def handle_cast(:stop_sound, %{voice_channel: {guild_id, _channel_id}} = state) do
    Logger.info("Stopping all sounds in guild: #{guild_id}")
    Voice.stop(guild_id)
    broadcast_success("All sounds stopped", "System")

    {:noreply,
     state
     |> clear_current_playback()
     |> Map.merge(%{
       pending_request: nil,
       interrupting: false,
       interrupt_watchdog_attempt: 0
     })}
  end

  def handle_cast(:stop_sound, state) do
    Logger.info("Attempted to stop sounds but no voice channel connected")
    broadcast_error("Bot is not connected to a voice channel")
    {:noreply, state}
  end

  def handle_cast({:playback_finished, guild_id}, state) do
    {:noreply, handle_playback_finished(state, guild_id)}
  end

  def handle_cast({:play_sound, _sound_name, _username}, %{voice_channel: nil} = state) do
    broadcast_error("Bot is not connected to a voice channel. Use !join in Discord first.")
    {:noreply, state}
  end

  def handle_cast(
        {:play_sound, sound_name, username},
        %{voice_channel: {guild_id, channel_id}} = state
      ) do
    case get_sound_path(sound_name) do
      {:ok, {path_or_url, volume}} ->
        request = %{
          guild_id: guild_id,
          channel_id: channel_id,
          sound_name: sound_name,
          path_or_url: path_or_url,
          volume: volume,
          username: username
        }

        new_state =
          case state.current_playback do
            nil ->
              state
              |> cancel_interrupt_watchdog()
              |> Map.merge(%{interrupting: false, interrupt_watchdog_attempt: 0})
              |> start_playback(request)

            _ ->
              state
              |> Map.put(:pending_request, request)
              |> maybe_interrupt_current()
          end

        {:noreply, new_state}

      {:error, reason} ->
        broadcast_error(reason)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_voice_channel, _from, state) do
    {:reply, state.voice_channel, state}
  end

  @impl true
  def handle_info({:play_delayed_sound, sound}, state) do
    Logger.info("Playing delayed join sound: #{sound}")
    # Play the sound as System user
    handle_cast({:play_sound, sound, "System"}, state)
  end

  @impl true
  def handle_info(:check_voice_connection, state) do
    new_state = maintain_voice_connection(state)

    # Schedule next check
    schedule_voice_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, result}, %{current_playback: %{task_ref: ref} = current} = state) do
    Process.demonitor(ref, [:flush])

    next_state =
      case result do
        :ok ->
          %{
            state
            | current_playback:
                current
                |> Map.put(:task_ref, nil)
                |> Map.put(:task_pid, nil)
          }

        :error ->
          Logger.error("Playback start failed for #{current.sound_name}")
          state |> clear_current_playback() |> maybe_start_pending()
      end

    {:noreply, next_state}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_playback: %{task_ref: ref}} = state
      ) do
    Logger.error("Playback task crashed: #{inspect(reason)}")
    {:noreply, state |> clear_current_playback() |> maybe_start_pending()}
  end

  @impl true
  def handle_info(
        {:interrupt_watchdog, guild_id, attempt},
        %{interrupting: true, interrupt_watchdog_attempt: attempt} = state
      ) do
    cond do
      state.current_playback == nil ->
        {:noreply, state |> reset_interrupt_state() |> maybe_start_pending()}

      attempt >= @interrupt_watchdog_max_attempts ->
        Logger.warning(
          "Interrupt watchdog timed out for guild #{guild_id}; forcing latest request"
        )

        Voice.stop(guild_id)
        {:noreply, state |> clear_current_playback() |> maybe_start_pending()}

      Voice.playing?(guild_id) ->
        Logger.debug(
          "Interrupt watchdog: audio still playing in guild #{guild_id}, retrying stop"
        )

        Voice.stop(guild_id)
        {:noreply, schedule_interrupt_watchdog(state, guild_id, attempt + 1)}

      true ->
        Logger.debug("Interrupt watchdog: playback already stopped for guild #{guild_id}")
        {:noreply, state |> clear_current_playback() |> maybe_start_pending()}
    end
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp start_playback(state, request) do
    task =
      Task.async(fn ->
        play_sound_task(
          request.guild_id,
          request.channel_id,
          request.sound_name,
          request.path_or_url,
          request.volume,
          request.username
        )
      end)

    %{
      state
      | current_playback: request |> Map.put(:task_ref, task.ref) |> Map.put(:task_pid, task.pid)
    }
  end

  defp maybe_interrupt_current(%{current_playback: %{guild_id: guild_id}} = state) do
    Logger.debug("Interrupting current playback in guild #{guild_id} for latest request")
    Voice.stop(guild_id)

    if Voice.playing?(guild_id) do
      state
      |> Map.put(:interrupting, true)
      |> schedule_interrupt_watchdog(guild_id, 1)
    else
      Logger.debug("Interrupt fast-path: playback stopped immediately in guild #{guild_id}")

      state
      |> clear_current_playback()
      |> maybe_start_pending()
    end
  end

  defp maybe_interrupt_current(state), do: state

  defp maintain_voice_connection(%{voice_channel: {guild_id, channel_id}} = state)
       when not is_nil(guild_id) and not is_nil(channel_id) do
    joined? = Voice.channel_id(guild_id) == to_string(channel_id)
    ready? = safe_voice_ready(guild_id)
    playing? = safe_voice_playing(guild_id)

    cond do
      playing? ->
        Logger.debug("Skipping voice maintenance while audio is playing in guild #{guild_id}")
        state

      joined? and ready? ->
        Logger.debug("Voice connection healthy for guild #{guild_id}")
        state

      joined? ->
        Logger.warning(
          "Voice session unready for guild #{guild_id} in channel #{channel_id}, attempting refresh"
        )

        attempt_voice_join(state, guild_id, channel_id, "refresh")

      true ->
        Logger.warning(
          "Voice channel mismatch for guild #{guild_id}, attempting to rejoin #{channel_id}"
        )

        attempt_voice_join(state, guild_id, channel_id, "rejoin")
    end
  end

  defp maintain_voice_connection(state) do
    Logger.debug("No voice channel set")
    state
  end

  defp attempt_voice_join(state, guild_id, channel_id, action) do
    Voice.join_channel(guild_id, channel_id)
    state
  rescue
    error ->
      Logger.error("Failed to #{action} voice channel: #{inspect(error)}")
      %{state | voice_channel: nil}
  end

  defp handle_playback_finished(state, guild_id) do
    cond do
      match?(%{guild_id: ^guild_id}, state.current_playback) ->
        state
        |> clear_current_playback()
        |> maybe_start_pending()

      state.interrupting and match?({^guild_id, _}, state.voice_channel) ->
        state
        |> reset_interrupt_state()
        |> maybe_start_pending()

      true ->
        state
    end
  end

  defp maybe_start_pending(%{pending_request: nil} = state), do: state

  defp maybe_start_pending(state) do
    request = state.pending_request

    case state.voice_channel do
      {guild_id, channel_id}
      when guild_id == request.guild_id and channel_id == request.channel_id ->
        state
        |> Map.put(:pending_request, nil)
        |> start_playback(request)

      _ ->
        %{state | pending_request: nil}
    end
  end

  defp clear_current_playback(state) do
    cancel_playback_task(state.current_playback)

    state
    |> cancel_interrupt_watchdog()
    |> Map.merge(%{
      current_playback: nil,
      interrupting: false,
      interrupt_watchdog_attempt: 0
    })
  end

  defp reset_interrupt_state(state) do
    state
    |> cancel_interrupt_watchdog()
    |> Map.merge(%{interrupting: false, interrupt_watchdog_attempt: 0})
  end

  defp schedule_interrupt_watchdog(state, guild_id, attempt) do
    state = cancel_interrupt_watchdog(state)

    ref =
      Process.send_after(self(), {:interrupt_watchdog, guild_id, attempt}, @interrupt_watchdog_ms)

    %{state | interrupt_watchdog_ref: ref, interrupt_watchdog_attempt: attempt}
  end

  defp cancel_interrupt_watchdog(%{interrupt_watchdog_ref: nil} = state), do: state

  defp cancel_interrupt_watchdog(state) do
    Process.cancel_timer(state.interrupt_watchdog_ref)
    %{state | interrupt_watchdog_ref: nil}
  end

  defp cancel_playback_task(nil), do: :ok

  defp cancel_playback_task(%{task_pid: pid, task_ref: ref}) when is_pid(pid) do
    if is_reference(ref), do: Process.demonitor(ref, [:flush])

    if Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    :ok
  end

  defp cancel_playback_task(_), do: :ok

  # Helper function to check if a username is a system user
  defp system_user?(username), do: username in @system_users

  defp play_sound_task(guild_id, channel_id, sound_name, path_or_url, volume, username) do
    join_state = ensure_joined_channel(guild_id, channel_id)
    maybe_settle_before_play(join_state)
    play_sound_with_connection(guild_id, sound_name, path_or_url, volume, username)
  end

  defp maybe_settle_before_play({:joined, :ok}) do
    # Give Discord voice transport a brief settle window after a fresh join so
    # the first audible frame is less likely to get dropped.
    Process.sleep(@voice_settle_ms)
  end

  defp maybe_settle_before_play(_), do: :ok

  defp play_sound_with_connection(guild_id, sound_name, path_or_url, volume, username) do
    if is_nil(System.find_executable("ffmpeg")) do
      Logger.error("ffmpeg not found in PATH. Cannot play #{sound_name}")
      broadcast_error("ffmpeg is not installed on this host")
      :error
    else
      {play_input, play_type} = prepare_play_input(sound_name, path_or_url)

      Logger.info(
        "Calling Voice.play with guild_id: #{guild_id}, input: #{play_input}, type: #{play_type}"
      )

      Logger.info(
        "Voice channel: #{inspect(Voice.channel_id(guild_id))}, Playing: #{Voice.playing?(guild_id)}"
      )

      # Keep ffmpeg in realtime mode (default) to avoid bursty/skip-prone playback.
      play_options = [volume: clamp_volume(volume)]
      Logger.info("Play options: #{inspect(play_options)}")

      # Keep track of attempts
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
        # Force stop the current audio
        Voice.stop(guild_id)
        # Small delay to ensure stop completes
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

        # Avoid repeated OP4 churn while a reconnect is in flight.
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

        # If negotiation appears stuck, do one explicit refresh per play request.
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
    case GenServer.call(__MODULE__, :get_voice_channel) do
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

    # Avoid an explicit leave here; that can strand the bot outside the channel
    # if Discord/gateway timing races during reconnect.
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
    Voice.playing?(guild_id)
  rescue
    _ -> :unknown
  end

  # Removed unused wait_for_audio_to_finish/2 to keep compile clean and hot path lean

  defp schedule_voice_check do
    # Check voice connection every 30 seconds
    Process.send_after(self(), :check_voice_connection, 30_000)
  end

  # Ensure ETS table exists (idempotent)
  defp ensure_sound_cache do
    case :ets.info(:sound_meta_cache) do
      :undefined ->
        :ets.new(:sound_meta_cache, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        :ok
    end
  end

  defp prepare_play_input(sound_name, path_or_url) do
    # Prefer cached metadata to avoid DB on hot path
    case :ets.lookup(:sound_meta_cache, sound_name) do
      [{^sound_name, %{source_type: "url"}}] ->
        Logger.info("Using URL directly for remote sound (cached)")
        {path_or_url, :url}

      [{^sound_name, %{source_type: "local"}}] ->
        Logger.info("Using raw path for local file with :url type (cached)")
        {path_or_url, :url}

      _ ->
        sound = Soundboard.Repo.get_by(Sound, filename: sound_name)
        Logger.info("Playing sound (uncached): #{inspect(sound)}")
        Logger.info("Original path/URL: #{path_or_url}")

        case sound do
          %{source_type: "url"} ->
            Logger.info("Using URL directly for remote sound")
            {path_or_url, :url}

          %{source_type: "local"} ->
            Logger.info("Using raw path for local file with :url type")
            {path_or_url, :url}

          _ ->
            Logger.warning("Unknown source type, defaulting to raw path with :url type")
            {path_or_url, :url}
        end
    end
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
    |> min(1.0)
    |> Float.round(4)
  end

  defp clamp_volume(_), do: 1.0

  defp get_sound_path(sound_name) do
    Logger.info("Getting sound path for: #{sound_name}")
    ensure_sound_cache()

    case lookup_cached_sound(sound_name) do
      {:hit, {_type, input, volume}} -> {:ok, {input, volume}}
      :miss -> resolve_and_cache_sound(sound_name)
    end
  end

  defp lookup_cached_sound(sound_name) do
    case :ets.lookup(:sound_meta_cache, sound_name) do
      [{^sound_name, %{source_type: source, input: input, volume: volume}}] ->
        Logger.info(
          "Found sound in cache: #{inspect(%{source_type: source, input: input, volume: volume})}"
        )

        {:hit, {source, input, volume}}

      _ ->
        :miss
    end
  end

  defp resolve_and_cache_sound(sound_name) do
    case Soundboard.Repo.get_by(Sound, filename: sound_name) do
      nil ->
        Logger.error("Sound not found in database: #{sound_name}")
        {:error, "Sound not found"}

      %{source_type: "url", url: url, volume: volume} when is_binary(url) ->
        Logger.info("Found URL sound: #{url}")
        meta = %{source_type: "url", input: url, volume: volume || 1.0}
        cache_sound(sound_name, meta)
        {:ok, {meta.input, meta.volume}}

      %{source_type: "local", filename: filename, volume: volume} when is_binary(filename) ->
        path = resolve_upload_path(filename)
        Logger.info("Resolved local file path: #{path}")

        if File.exists?(path) do
          meta = %{source_type: "local", input: path, volume: volume || 1.0}
          cache_sound(sound_name, meta)
          {:ok, {meta.input, meta.volume}}
        else
          Logger.error("Local file not found: #{path}")
          {:error, "Sound file not found at #{path}"}
        end

      sound ->
        Logger.error("Invalid sound configuration: #{inspect(sound)}")
        {:error, "Invalid sound configuration"}
    end
  end

  defp resolve_upload_path(filename) do
    if File.exists?("/app/priv/static/uploads") do
      "/app/priv/static/uploads/#{filename}"
    else
      priv_dir = :code.priv_dir(:soundboard)
      Path.join([priv_dir, "static/uploads", filename])
    end
  end

  @doc """
  Removes any cached metadata for the given `sound_name` so future plays use fresh data.
  """
  def invalidate_cache(sound_name) when is_binary(sound_name) do
    ensure_sound_cache()
    :ets.delete(:sound_meta_cache, sound_name)
    :ok
  end

  def invalidate_cache(_), do: :ok

  defp cache_sound(sound_name, meta) do
    :ets.insert(:sound_meta_cache, {sound_name, meta})
  end
end
