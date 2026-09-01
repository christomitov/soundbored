defmodule Soundboard.AudioPlayer do
  @moduledoc """
  Facade over the per-guild audio player servers.

  One `Soundboard.AudioPlayer.Server` process exists per guild. All functions
  route by `guild_id`; when omitted, the default guild is used so existing
  single-guild deployments behave exactly as before.
  """

  alias Soundboard.AudioPlayer.Server
  alias Soundboard.AudioPlayer.SoundLibrary
  alias Soundboard.Tenants

  @registry Soundboard.AudioPlayer.Registry
  @supervisor Soundboard.AudioPlayer.Supervisor

  @doc "Starts the player for `guild_id` if not already running. Returns its pid."
  @spec ensure_started(String.t()) :: pid()
  def ensure_started(guild_id) do
    case Registry.lookup(@registry, guild_id) do
      [{pid, _value} | _] ->
        pid

      [] ->
        case DynamicSupervisor.start_child(@supervisor, Server.child_spec(guild_id)) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
          {:error, {:already_present, pid}} -> pid
        end
    end
  end

  @doc "Pid of the player server for `guild_id`, if running."
  @spec server_pid(String.t()) :: pid() | nil
  def server_pid(guild_id) do
    case Registry.lookup(@registry, guild_id) do
      [{pid, _value} | _] -> pid
      [] -> nil
    end
  end

  def play_sound(sound_name, actor, guild_id \\ nil),
    do: cast(guild_id, {:play_sound, sound_name, actor})

  def stop_sound(guild_id \\ nil), do: cast(guild_id, :stop_sound)

  def set_voice_channel(guild_id, channel_id),
    do: cast(guild_id, {:set_voice_channel, Tenants.scope_guild_id(guild_id), channel_id})

  def last_user_left(guild_id),
    do: cast(guild_id, {:last_user_left, Tenants.scope_guild_id(guild_id)})

  def user_joined_channel(guild_id),
    do: cast(guild_id, {:user_joined_channel, Tenants.scope_guild_id(guild_id)})

  def playback_finished(guild_id),
    do: cast(guild_id, {:playback_finished, Tenants.scope_guild_id(guild_id)})

  def current_voice_channel(guild_id \\ nil) do
    guild_id = Tenants.scope_guild_id(guild_id)

    case server_pid(guild_id) do
      nil ->
        {:ok, nil}

      pid ->
        {:ok, GenServer.call(pid, :get_voice_channel)}
    end
  rescue
    error -> {:error, {:voice_channel_unavailable, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:voice_channel_unavailable, reason}}
  end

  @doc """
  Removes any cached metadata for `filename` in `guild_id` so future plays use
  fresh data. The 1-arity form targets the default guild (back-compat).
  """
  def invalidate_cache(guild_id, filename) when is_binary(filename),
    do: SoundLibrary.invalidate_cache(Tenants.scope_guild_id(guild_id), filename)

  def invalidate_cache(filename) when is_binary(filename),
    do: SoundLibrary.invalidate_cache(Tenants.default_guild_id(), filename)

  def invalidate_cache(_), do: :ok

  defp cast(guild_id, message) do
    guild_id = Tenants.scope_guild_id(guild_id)
    ensure_started(guild_id)
    GenServer.cast(Server.via(guild_id), message)
  end
end
