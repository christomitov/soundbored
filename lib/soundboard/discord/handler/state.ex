defmodule Soundboard.Discord.Handler.State do
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
