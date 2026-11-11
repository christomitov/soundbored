defmodule Soundboard.FakeVoice do
  @moduledoc """
  Stand-in for `EDA.Voice` (eda 0.2.0), installed through the
  `:eda_voice_module` config key in `config/test.exs`.

  A test claims a guild id with `claim/2`. Every command for that guild
  (`join`, `leave`, `play`, `stop`) is sent to the claiming process as
  `{:fake_voice, guild_id, command}`. The fake keeps the guild's voice
  session the way EDA does and answers from it:

    * with no session (no channel), `play` returns `{:error, :not_connected}`
      and `ready?` is false
    * an unready session makes `play` return `{:error, :not_ready}`, and a
      `:not_connected` or `:not_ready` play marks the session unready
    * while audio plays, `play` returns `{:error, :already_playing}`
    * otherwise `play` starts audio and returns `:ok`
    * `join` always returns `:ok`, opens a session on the channel and stops
      any audio; VOICE_READY is taken to arrive at once unless
      `ready_on_join: false`, in which case `voice_ready/1` delivers it
    * `leave` closes the session, `stop` ends the audio, and `finish/1` is
      audio ending on its own (what precedes VOICE_PLAYBACK_FINISHED)

  Options for `claim/2`:

    * `:channel` - an existing session on this channel (default: no session)
    * `:ready` - whether that session is ready (default true)
    * `:playing` - whether audio is playing (default false)
    * `:play` - scripted results for the next plays, used before the
      session-derived answer: `:ok`, `{:error, reason}` or `:hold`. `:hold`
      starts audio and blocks the caller until it is killed (at the latest
      when the test ends), sending `{:fake_voice_holding, guild_id, pid}`.
    * `:stop` - `:immediate` (default) or `:ignored`, for audio that keeps
      playing after a stop until it finishes on its own
    * `:ready_on_join` - default true
    * `:exit_on` - calls that exit the way a timed-out `GenServer.call` to
      EDA does, e.g. `[:join, :playing?]`

  Unclaimed guilds behave as guilds with no session and send nothing.
  """

  use Agent

  @idle %{
    owner: nil,
    channel: nil,
    ready: false,
    playing: false,
    play: [],
    stop: :immediate,
    ready_on_join: true,
    exit_on: [],
    holders: []
  }

  def start, do: Agent.start(fn -> %{} end, name: __MODULE__)

  def claim(guild_id, opts \\ []) do
    channel = opts[:channel]

    guild = %{
      @idle
      | owner: self(),
        channel: channel,
        ready: channel != nil and Keyword.get(opts, :ready, true),
        playing: Keyword.get(opts, :playing, false),
        play: Keyword.get(opts, :play, []),
        stop: Keyword.get(opts, :stop, :immediate),
        ready_on_join: Keyword.get(opts, :ready_on_join, true),
        exit_on: Keyword.get(opts, :exit_on, [])
    }

    Agent.update(__MODULE__, &Map.put(&1, guild_id, guild))
    ExUnit.Callbacks.on_exit(fn -> release(guild_id) end)
    guild_id
  end

  def voice_ready(guild_id), do: update(guild_id, &%{&1 | ready: &1.channel != nil})

  def finish(guild_id), do: update(guild_id, &%{&1 | playing: false})

  defp release(guild_id) do
    guild = Agent.get_and_update(__MODULE__, &Map.pop(&1, guild_id, @idle))
    Enum.each(guild.holders, &Process.exit(&1, :kill))
  end

  def join(guild_id, channel_id) do
    command(guild_id, :join, {:join, channel_id}, fn guild ->
      %{guild | channel: channel_id, ready: guild.ready_on_join, playing: false}
    end)
  end

  def leave(guild_id) do
    command(guild_id, :leave, :leave, &%{&1 | channel: nil, ready: false, playing: false})
  end

  def play(guild_id, input, type, opts) do
    result = next_play_result(guild_id)

    case result do
      {:error, reason} when reason in [:not_ready, :not_connected] ->
        update(guild_id, &%{&1 | ready: false})

      {:error, _reason} ->
        :ok

      _started ->
        update(guild_id, &%{&1 | playing: true})
    end

    notify(guild_id, {:play, input, type, opts})
    if result == :hold, do: hold(guild_id), else: result
  end

  def stop(guild_id) do
    command(guild_id, :stop, :stop, fn
      %{stop: :ignored} = guild -> guild
      guild -> %{guild | playing: false}
    end)
  end

  defp command(guild_id, call, message, fun) do
    if call in guild(guild_id).exit_on do
      notify(guild_id, message)
      exit_like_eda(guild_id, call)
    end

    update(guild_id, fun)
    notify(guild_id, message)
    :ok
  end

  defp hold(guild_id) do
    holder = self()
    update(guild_id, &%{&1 | holders: [holder | &1.holders]})
    notify(guild_id, {:holding, holder})
    receive do: (:never -> :ok)
  end

  def ready?(guild_id), do: status(guild_id, :ready?, :ready)
  def channel_id(guild_id), do: status(guild_id, :channel_id, :channel)
  def playing?(guild_id), do: status(guild_id, :playing?, :playing)
  def get_voice_state(_guild_id), do: {:ok, %{}}

  defp status(guild_id, call, field) do
    guild = guild(guild_id)
    if call in guild.exit_on, do: exit_like_eda(guild_id, call)
    Map.fetch!(guild, field)
  end

  defp exit_like_eda(guild_id, call),
    do: exit({:timeout, {GenServer, :call, [EDA.Voice, {call, guild_id}, 5000]}})

  defp next_play_result(guild_id) do
    Agent.get_and_update(__MODULE__, fn guilds ->
      case Map.get(guilds, guild_id, @idle) do
        %{play: [result | rest]} = guild ->
          {result, Map.put(guilds, guild_id, %{guild | play: rest})}

        guild ->
          {session_result(guild), guilds}
      end
    end)
  end

  defp session_result(%{channel: nil}), do: {:error, :not_connected}
  defp session_result(%{ready: false}), do: {:error, :not_ready}
  defp session_result(%{playing: true}), do: {:error, :already_playing}
  defp session_result(_guild), do: :ok

  defp guild(guild_id), do: Agent.get(__MODULE__, &Map.get(&1, guild_id, @idle))

  defp update(guild_id, fun) do
    Agent.update(__MODULE__, fn guilds ->
      if Map.has_key?(guilds, guild_id), do: Map.update!(guilds, guild_id, fun), else: guilds
    end)
  end

  defp notify(guild_id, {:holding, pid}) do
    with %{owner: owner} when is_pid(owner) <- guild(guild_id),
         do: send(owner, {:fake_voice_holding, guild_id, pid})
  end

  defp notify(guild_id, command) do
    with %{owner: owner} when is_pid(owner) <- guild(guild_id),
         do: send(owner, {:fake_voice, guild_id, command})
  end
end
