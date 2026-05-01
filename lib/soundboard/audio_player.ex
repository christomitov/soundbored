defmodule Soundboard.AudioPlayer do
  @moduledoc """
  Handles audio playback coordination.
  """

  use GenServer

  require Logger

  alias Soundboard.Accounts.User
  alias Soundboard.AudioPlayer.{Notifier, PlaybackQueue, SoundLibrary, VoiceSession}
  alias Soundboard.Discord.Handler.{AutoJoinPolicy, IdleTimeoutPolicy, VoicePresence}
  alias Soundboard.Discord.Voice

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
      :interrupt_watchdog_attempt,
      :idle_timeout_ref
    ]

    @type t :: %__MODULE__{
            voice_channel: {String.t(), String.t()} | nil,
            current_playback: map() | nil,
            pending_request: map() | nil,
            interrupting: boolean() | nil,
            interrupt_watchdog_ref: reference() | nil,
            interrupt_watchdog_attempt: non_neg_integer() | nil,
            idle_timeout_ref: {reference(), reference()} | nil
          }
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  def play_sound(sound_name, actor) do
    GenServer.cast(__MODULE__, {:play_sound, sound_name, actor})
  end

  def stop_sound do
    GenServer.cast(__MODULE__, :stop_sound)
  end

  def set_voice_channel(guild_id, channel_id) do
    GenServer.cast(__MODULE__, {:set_voice_channel, guild_id, channel_id})
  end

  def last_user_left(guild_id) do
    GenServer.cast(__MODULE__, {:last_user_left, guild_id})
  end

  def user_joined_channel(guild_id) do
    GenServer.cast(__MODULE__, {:user_joined_channel, guild_id})
  end

  def playback_finished(guild_id) do
    GenServer.cast(__MODULE__, {:playback_finished, guild_id})
  end

  def current_voice_channel do
    {:ok, GenServer.call(__MODULE__, :get_voice_channel)}
  rescue
    error -> {:error, {:voice_channel_unavailable, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:voice_channel_unavailable, reason}}
  end

  @doc """
  Removes any cached metadata for the given `sound_name` so future plays use fresh data.
  """
  def invalidate_cache(sound_name), do: SoundLibrary.invalidate_cache(sound_name)

  @impl true
  def init(state) do
    SoundLibrary.ensure_cache()
    schedule_voice_check()

    {:ok,
     %{
       state
       | current_playback: nil,
         pending_request: nil,
         interrupting: false,
         interrupt_watchdog_ref: nil,
         interrupt_watchdog_attempt: 0,
         idle_timeout_ref: nil
     }}
  end

  @impl true
  def handle_cast({:set_voice_channel, guild_id, channel_id}, state) do
    next_state =
      case VoiceSession.normalize_channel(guild_id, channel_id) do
        nil ->
          state
          |> PlaybackQueue.clear_all()
          |> cancel_idle_timeout()
          |> Map.put(:voice_channel, nil)

        voice_channel ->
          new_state =
            state
            |> cancel_idle_timeout()
            |> Map.put(:voice_channel, voice_channel)

          if AutoJoinPolicy.mode() == :play, do: schedule_idle_timeout(new_state), else: new_state
      end

    {:noreply, next_state}
  end

  def handle_cast(:stop_sound, %{voice_channel: {guild_id, _channel_id}} = state) do
    Voice.stop(guild_id)
    Notifier.sound_played("All sounds stopped", "System")

    {:noreply, PlaybackQueue.clear_all(state)}
  end

  def handle_cast(:stop_sound, state) do
    Notifier.error("Bot is not connected to a voice channel")
    {:noreply, state}
  end

  def handle_cast({:playback_finished, guild_id}, state) do
    {:noreply, PlaybackQueue.handle_playback_finished(state, guild_id)}
  end

  def handle_cast({:play_sound, sound_name, actor}, %{voice_channel: nil} = state) do
    if AutoJoinPolicy.mode() == :play do
      case try_auto_join(actor) do
        {:ok, {guild_id, channel_id}} ->
          new_state =
            state
            |> Map.put(:voice_channel, {guild_id, channel_id})
            |> schedule_idle_timeout()

          do_play_sound(sound_name, actor, new_state)

        :not_found ->
          Notifier.error("Bot is not connected to a voice channel. Use !join in Discord first.")
          {:noreply, state}
      end
    else
      Notifier.error("Bot is not connected to a voice channel. Use !join in Discord first.")
      {:noreply, state}
    end
  end

  def handle_cast({:play_sound, sound_name, actor}, state) do
    do_play_sound(sound_name, actor, state)
  end

  def handle_cast({:last_user_left, guild_id}, %{voice_channel: {guild_id, _}} = state) do
    case AutoJoinPolicy.mode() do
      mode when mode in [:presence, :play] ->
        Logger.info("Last user left (#{mode} mode); leaving guild #{guild_id}")
        safely_leave(guild_id)

        new_state =
          state
          |> cancel_idle_timeout()
          |> PlaybackQueue.clear_all()
          |> Map.put(:voice_channel, nil)

        {:noreply, new_state}

      false ->
        Logger.info("Last user left (false mode); starting idle timer")
        {:noreply, reset_idle_timeout(state)}
    end
  end

  def handle_cast({:last_user_left, _guild_id}, state), do: {:noreply, state}

  def handle_cast({:user_joined_channel, _guild_id}, state) do
    {:noreply, cancel_idle_timeout(state)}
  end

  @impl true
  def handle_call(:get_voice_channel, _from, state) do
    {:reply, state.voice_channel, state}
  end

  @impl true
  def handle_info(
        {:idle_timeout, token},
        %{idle_timeout_ref: {_ref, token}, voice_channel: {guild_id, _}} = state
      ) do
    Logger.info("Voice idle timeout in guild #{guild_id}; leaving channel")
    safely_leave(guild_id)

    new_state =
      %{state | idle_timeout_ref: nil}
      |> PlaybackQueue.clear_all()
      |> Map.put(:voice_channel, nil)

    {:noreply, new_state}
  end

  def handle_info({:idle_timeout, _stale_token}, state), do: {:noreply, state}

  @impl true
  def handle_info(:check_voice_connection, state) do
    schedule_voice_check()
    {:noreply, VoiceSession.maintain_connection(state)}
  end

  @impl true
  def handle_info({ref, result}, %{current_playback: %{task_ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, PlaybackQueue.handle_task_result(state, result)}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_playback: %{task_ref: ref}} = state
      ) do
    {:noreply, PlaybackQueue.handle_task_down(state, reason)}
  end

  @impl true
  def handle_info({:interrupt_watchdog, guild_id, attempt}, state) do
    {:noreply,
     PlaybackQueue.handle_interrupt_watchdog(
       state,
       guild_id,
       attempt,
       @interrupt_watchdog_max_attempts,
       @interrupt_watchdog_ms
     )}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp do_play_sound(sound_name, actor, %{voice_channel: voice_channel} = state) do
    case PlaybackQueue.build_request(voice_channel, sound_name, actor) do
      {:ok, request} ->
        new_state =
          if AutoJoinPolicy.mode() == :play, do: reset_idle_timeout(state), else: state

        {:noreply, PlaybackQueue.enqueue(new_state, request, @interrupt_watchdog_ms)}

      {:error, reason} ->
        Notifier.error(reason)
        {:noreply, state}
    end
  end

  defp try_auto_join(actor) do
    case actor_discord_id(actor) do
      nil -> :not_found
      discord_id -> find_and_join_voice(discord_id)
    end
  end

  defp find_and_join_voice(discord_id) do
    case VoicePresence.find_user_voice_channel(discord_id) do
      {:ok, {guild_id, channel_id}} ->
        Logger.info(
          "Auto-joining channel #{channel_id} in guild #{guild_id} for user #{discord_id}"
        )

        Voice.join_channel(guild_id, channel_id)
        {:ok, {guild_id, channel_id}}

      :not_found ->
        Logger.info("User #{discord_id} not in a voice channel; skipping auto-join")
        :not_found
    end
  rescue
    error ->
      Logger.warning("Auto-join failed: #{inspect(error)}")
      :not_found
  end

  defp safely_leave(guild_id) do
    Voice.leave_channel(guild_id)
  rescue
    error -> Logger.warning("Voice leave failed: #{inspect(error)}")
  end

  defp actor_discord_id(%User{discord_id: id}) when is_binary(id) and id != "", do: id
  defp actor_discord_id(%{discord_id: id}) when is_binary(id) and id != "", do: id
  defp actor_discord_id(_), do: nil

  defp schedule_idle_timeout(state) do
    case IdleTimeoutPolicy.timeout_ms() do
      nil ->
        state

      ms ->
        token = make_ref()
        ref = Process.send_after(self(), {:idle_timeout, token}, ms)
        %{state | idle_timeout_ref: {ref, token}}
    end
  end

  defp cancel_idle_timeout(%{idle_timeout_ref: nil} = state), do: state

  defp cancel_idle_timeout(%{idle_timeout_ref: {ref, _token}} = state) do
    Process.cancel_timer(ref)
    %{state | idle_timeout_ref: nil}
  end

  defp reset_idle_timeout(state) do
    state |> cancel_idle_timeout() |> schedule_idle_timeout()
  end

  defp schedule_voice_check do
    if Application.get_env(:soundboard, __MODULE__, [])[:voice_maintenance_enabled] != false do
      Process.send_after(self(), :check_voice_connection, 30_000)
    end
  end
end
