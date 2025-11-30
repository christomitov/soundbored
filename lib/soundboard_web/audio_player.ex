defmodule SoundboardWeb.AudioPlayer do
  @moduledoc """
  Handles the audio playback.
  """
  use GenServer
  require Logger
  alias Nostrum.Voice
  alias Soundboard.Accounts.{Tenants, User}
  alias Soundboard.{PubSubTopics, Sound}

  # System users that don't need play tracking
  @system_users ["System", "API User"]

  defmodule State do
    @moduledoc """
    The state of the audio player.
    """
    defstruct [:voice_channel, :current_playback]
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

  def stop_sound(tenant_id \\ nil) do
    Logger.info("Stopping all sounds")
    GenServer.cast(__MODULE__, {:stop_sound, tenant_id})
  end

  def set_voice_channel(guild_id, channel_id) do
    Logger.info("Setting voice channel - Guild: #{guild_id}, Channel: #{channel_id}")
    GenServer.cast(__MODULE__, {:set_voice_channel, guild_id, channel_id})
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
    {:ok, state}
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

    {:noreply, %{state | voice_channel: voice_channel}}
  end

  def handle_cast({:stop_sound, tenant_id}, %{voice_channel: {guild_id, _channel_id}} = state) do
    Logger.info("Stopping all sounds in guild: #{guild_id}")
    Voice.stop(guild_id)
    broadcast_success("All sounds stopped", "System", tenant_id)
    {:noreply, state}
  end

  def handle_cast({:stop_sound, tenant_id}, state) do
    Logger.info("Attempted to stop sounds but no voice channel connected")
    broadcast_error("Bot is not connected to a voice channel", tenant_id)
    {:noreply, state}
  end

  def handle_cast({:play_sound, sound_name, _username}, %{voice_channel: nil} = state) do
    broadcast_error(
      "Bot is not connected to a voice channel. Use !join in Discord first.",
      tenant_id_for_sound(sound_name)
    )

    {:noreply, state}
  end

  def handle_cast(
        {:play_sound, sound_name, username},
        %{voice_channel: {guild_id, channel_id}} = state
      ) do
    case get_sound_path(sound_name) do
      {:ok, {path_or_url, volume}} ->
        task =
          Task.async(fn ->
            play_sound_task(guild_id, channel_id, sound_name, path_or_url, volume, username)
          end)

        {:noreply, %{state | current_playback: task}}

      {:error, reason} ->
        broadcast_error(reason, tenant_id_for_sound(sound_name))
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
    # Check and maintain voice connection health
    new_state =
      case state.voice_channel do
        {guild_id, channel_id} when not is_nil(guild_id) and not is_nil(channel_id) ->
          if Voice.ready?(guild_id) do
            Logger.debug("Voice connection healthy for guild #{guild_id}")
            state
          else
            Logger.warning(
              "Voice connection not ready for guild #{guild_id}, attempting to rejoin"
            )

            # Wrap in try-catch to handle potential errors
            try do
              Voice.join_channel(guild_id, channel_id)
              state
            rescue
              error ->
                Logger.error("Failed to rejoin voice channel: #{inspect(error)}")
                # Clear the voice channel if we can't rejoin
                %{state | voice_channel: nil}
            end
          end

        _ ->
          Logger.debug("No voice channel set")
          state
      end

    # Schedule next check
    schedule_voice_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, _result}, %{current_playback: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | current_playback: nil}}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_playback: %Task{ref: ref}} = state
      ) do
    Logger.error("Playback task crashed: #{inspect(reason)}")
    {:noreply, %{state | current_playback: nil}}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  # Helper function to check if a username is a system user
  defp system_user?(username), do: username in @system_users

  defp play_sound_task(guild_id, channel_id, sound_name, path_or_url, volume, username) do
    # Stop any currently playing sound immediately
    # Direct call is fast enough, no need for Task.start which causes process leaks
    if Voice.playing?(guild_id) do
      Voice.stop(guild_id)
    end

    # Ensure we're connected and ready
    if ensure_voice_ready(guild_id, channel_id) do
      play_sound_with_connection(guild_id, sound_name, path_or_url, volume, username)
    else
      Logger.error("Failed to establish voice connection")
      broadcast_error("Failed to connect to voice channel", tenant_id_for_sound(sound_name))
    end
  end

  defp play_sound_with_connection(guild_id, sound_name, path_or_url, volume, username) do
    {play_input, play_type} = prepare_play_input(sound_name, path_or_url)

    Logger.info(
      "Calling Voice.play with guild_id: #{guild_id}, input: #{play_input}, type: #{play_type}"
    )

    # Check voice state
    Logger.info("Voice ready: #{Voice.ready?(guild_id)}, Playing: #{Voice.playing?(guild_id)}")

    # Disable ffmpeg realtime processing to avoid `-re` pacing.
    # Nostrum already paces via bursts; `-re` can cause latency buildup
    # and slower cleanup of ffmpeg processes over time.
    play_options = [volume: clamp_volume(volume), realtime: false]
    Logger.info("Play options: #{inspect(play_options)}")

    # Keep track of attempts
    play_with_retries(guild_id, play_input, play_type, play_options, sound_name, username, 0)
  end

  defp play_with_retries(
         guild_id,
         play_input,
         play_type,
         play_options,
         sound_name,
         username,
         attempt
       )
       when attempt < 3 do
    case Voice.play(guild_id, play_input, play_type, play_options) do
      :ok ->
        Logger.info("Voice.play succeeded for #{sound_name} (attempt #{attempt + 1})")
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
          attempt + 1
        )

      {:error, "Must be connected to voice channel to play audio."} ->
        Logger.error("Voice connection lost, attempting to reconnect...")

        handle_voice_reconnect(
          guild_id,
          play_input,
          play_type,
          play_options,
          sound_name,
          username,
          attempt
        )

      {:error, reason} ->
        Logger.error("Voice.play failed: #{inspect(reason)} (attempt #{attempt + 1})")
        broadcast_error("Failed to play sound: #{reason}", tenant_id_for_sound(sound_name))
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
         attempt
       ) do
    Logger.error("Exceeded max retries (#{attempt}) for playing #{sound_name}")

    broadcast_error(
      "Failed to play sound after multiple attempts",
      tenant_id_for_sound(sound_name)
    )

    :error
  end

  defp handle_voice_reconnect(
         guild_id,
         play_input,
         play_type,
         play_options,
         sound_name,
         username,
         attempt
       ) do
    # Get the channel from state
    case GenServer.call(__MODULE__, :get_voice_channel) do
      {^guild_id, channel_id} ->
        Logger.info("Rejoining voice channel #{channel_id}")

        # Voice.join_channel returns :ok or crashes (no_return)
        try do
          Voice.join_channel(guild_id, channel_id)
          # Reduced delay - just enough for connection handshake
          Process.sleep(50)

          play_with_retries(
            guild_id,
            play_input,
            play_type,
            play_options,
            sound_name,
            username,
            attempt + 1
          )
        rescue
          error ->
            Logger.error("Failed to rejoin voice channel: #{inspect(error)}")

            broadcast_error(
              "Failed to reconnect to voice channel",
              tenant_id_for_sound(sound_name)
            )

            :error
        end

      _ ->
        Logger.error("No voice channel info available")
        broadcast_error("Voice channel not configured")
        :error
    end
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
    cond do
      system_user?(username) ->
        Logger.info("Skipping play tracking for system user: #{username}")

      user = Soundboard.Repo.get_by(User, username: username) ->
        track_user_play(sound_name, user.id)

      true ->
        Logger.warning("Could not find user_id for #{username}")
    end
  end

  defp track_user_play(sound_name, user_id) do
    case Soundboard.Stats.track_play(sound_name, user_id) do
      {:ok, _play} -> :ok
      {:error, reason} -> Logger.warning("Failed to track play: #{inspect(reason)}")
    end
  end

  defp ensure_voice_ready(guild_id, channel_id) do
    if Voice.ready?(guild_id) do
      Logger.info("Voice connection ready for guild #{guild_id}")
      true
    else
      Logger.info("Voice not ready, attempting to join channel #{channel_id}")
      join_and_verify_channel(guild_id, channel_id)
    end
  end

  defp join_and_verify_channel(guild_id, channel_id) do
    # Voice.join_channel returns :ok or crashes (no_return)
    # Using rescue to handle potential crashes
    Voice.join_channel(guild_id, channel_id)

    # Check immediately if ready, no sleep needed
    if Voice.ready?(guild_id) do
      Logger.info("Successfully connected to voice channel")
      true
    else
      # Minimal sleep - just 20ms for network round-trip
      Process.sleep(20)

      if Voice.ready?(guild_id) do
        Logger.info("Successfully connected to voice channel after brief wait")
        true
      else
        Logger.error("Voice connection not ready after join attempt")
        false
      end
    end
  rescue
    error ->
      Logger.error("Failed to join voice channel: #{inspect(error)}")
      false
  end

  defp broadcast_success(sound_name, username, tenant_id \\ nil)

  defp broadcast_success(sound_name, username, nil) do
    broadcast_success(sound_name, username, tenant_id_for_sound(sound_name))
  end

  defp broadcast_success(sound_name, username, tenant_id) do
    message =
      {:sound_played,
       %{
         filename: sound_name,
         played_by: username,
         tenant_id: tenant_id
       }}

    broadcast_to_soundboard_topics(message, tenant_id)
  end

  defp broadcast_error(message, tenant_id \\ nil) do
    broadcast_to_soundboard_topics({:error, message}, tenant_id)
  end

  defp broadcast_to_soundboard_topics(message, tenant_id) do
    tenant_id = tenant_id || Tenants.ensure_default_tenant!().id

    Phoenix.PubSub.broadcast(
      Soundboard.PubSub,
      PubSubTopics.soundboard_topic(tenant_id),
      message
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

  defp tenant_id_for_sound(sound_name) do
    case Soundboard.Repo.get_by(Sound, filename: sound_name) do
      %Sound{tenant_id: tenant_id} when is_integer(tenant_id) ->
        tenant_id

      _ ->
        Tenants.ensure_default_tenant!().id
    end
  rescue
    _ -> Tenants.ensure_default_tenant!().id
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
