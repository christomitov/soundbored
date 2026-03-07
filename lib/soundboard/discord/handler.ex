defmodule Soundboard.Discord.Handler do
  @moduledoc """
  Handles the Discord events.
  """
  use GenServer
  require Logger

  alias Soundboard.Discord.Handler.{CommandHandler, SoundEffects, VoiceRuntime}

  defmodule State do
    @moduledoc """
    Handles the state of the Discord handler.
    """
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def init(_) do
      {:ok, %{voice_states: %{}}}
    end

    def get_state(user_id) do
      GenServer.call(__MODULE__, {:get_state, user_id})
    catch
      :exit, _ -> nil
    end

    def update_state(user_id, channel_id, session_id) do
      GenServer.cast(__MODULE__, {:update_state, user_id, channel_id, session_id})
    catch
      :exit, _ -> :error
    end

    def handle_call({:get_state, user_id}, _from, state) do
      {:reply, Map.get(state.voice_states, user_id), state}
    end

    def handle_cast({:update_state, user_id, channel_id, session_id}, state) do
      {:noreply,
       %{state | voice_states: Map.put(state.voice_states, user_id, {channel_id, session_id})}}
    end
  end

  def init do
    VoiceRuntime.bootstrap()
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def dispatch_event(event) do
    case Process.whereis(__MODULE__) do
      nil ->
        Logger.warning("DiscordHandler is not running; dropping event #{inspect(elem(event, 0))}")
        :error

      _pid ->
        GenServer.cast(__MODULE__, {:eda_event, event})
        :ok
    end
  end

  @impl GenServer
  def init([]) do
    init()
    {:ok, nil}
  end

  def handle_event({:VOICE_STATE_UPDATE, %{channel_id: nil} = payload, _ws_state}) do
    Logger.info("User #{payload.user_id} disconnected from voice")
    State.update_state(payload.user_id, nil, payload.session_id)

    if VoiceRuntime.bot_user?(payload.user_id) do
      Logger.debug("Skipping leave sound lookup for bot user #{payload.user_id}")
    else
      SoundEffects.handle_leave(payload.user_id)
    end

    VoiceRuntime.handle_disconnect(payload)
  end

  def handle_event({:VOICE_STATE_UPDATE, payload, _ws_state}) do
    Logger.info("Voice state update received: #{inspect(payload)}")

    if VoiceRuntime.bot_user?(payload.user_id) do
      Logger.info(
        "BOT VOICE STATE UPDATE - Bot joined channel #{payload.channel_id} in guild #{payload.guild_id}"
      )
    end

    previous_state = State.get_state(payload.user_id)
    State.update_state(payload.user_id, payload.channel_id, payload.session_id)

    runtime_actions = VoiceRuntime.handle_connect(payload)

    if VoiceRuntime.bot_user?(payload.user_id) do
      Logger.debug("Skipping join sound lookup for bot user #{payload.user_id}")
    else
      SoundEffects.handle_join(payload.user_id, previous_state, payload.channel_id)
    end

    runtime_actions
  end

  def handle_event({:READY, _payload, _ws_state}) do
    Logger.info("Bot is READY - gateway connection established")
    :persistent_term.put(:soundboard_bot_ready, true)
    []
  end

  def handle_event({:VOICE_READY, payload, _ws_state}) do
    Logger.info("""
    Voice Ready Event:
    Guild ID: #{payload.guild_id}
    Channel ID: #{payload.channel_id}
    """)

    []
  end

  def handle_event({:VOICE_PLAYBACK_FINISHED, payload, _ws_state}) do
    Soundboard.AudioPlayer.playback_finished(payload.guild_id)
    []
  end

  def handle_event({:VOICE_SERVER_UPDATE, _payload, _ws_state}), do: []

  def handle_event({:VOICE_CHANNEL_STATUS_UPDATE, _payload, _ws_state}), do: []

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    CommandHandler.handle_message(msg)
    []
  end

  def handle_event(_event), do: []

  @impl true
  def handle_cast({:eda_event, event}, state) do
    event
    |> handle_event()
    |> apply_runtime_actions()

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, {event_name, payload, ws_state}}, state) do
    {event_name, payload, ws_state}
    |> handle_event()
    |> apply_runtime_actions()

    {:noreply, state}
  end

  def handle_info({:recheck_alone, guild_id, channel_id}, state) do
    guild_id
    |> VoiceRuntime.recheck_alone(channel_id)
    |> apply_runtime_actions()

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def get_current_voice_channel do
    VoiceRuntime.get_current_voice_channel()
  end

  defp apply_runtime_actions(actions) when is_list(actions) do
    Enum.each(actions, &apply_runtime_action/1)
  end

  defp apply_runtime_actions(_actions), do: :ok

  defp apply_runtime_action({:schedule_recheck_alone, guild_id, channel_id, delay_ms}) do
    Process.send_after(self(), {:recheck_alone, guild_id, channel_id}, delay_ms)
  end

  defp apply_runtime_action(_action), do: :ok
end
