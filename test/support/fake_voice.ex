defmodule Soundboard.FakeVoice do
  @moduledoc """
  Stand-in for `EDA.Voice`, installed through the `:eda_voice_module` config
  key in `config/test.exs`.

  A test claims a guild id with `claim/2`. Every command for that guild
  (`join`, `leave`, `play`, `stop`) is sent to the claiming process as
  `{:fake_voice, guild_id, command}` and answered from the guild's script.
  The fake keeps the guild's voice state the way EDA reports it: `join`
  connects and readies the session, a successful `play` starts audio, `stop`
  ends it (unless the script says stops are ignored), and a `:not_ready`
  play result marks the session unready.

  Options for `claim/2`:

    * `:channel` - the channel EDA already reports for the guild (default nil)
    * `:ready` - whether the session reports ready (default true)
    * `:playing` - whether audio is playing (default false), or `:raise` for
      a status call that raises until the session is reset
    * `:play` - results returned by successive plays: `:ok`, `{:error, atom}`
      or `:hold`; `:ok` once the list runs out. `:hold` starts audio and
      blocks the caller until it is killed (at the latest when the test ends), sending
      `{:fake_voice_holding, guild_id, pid}` first.
    * `:stop` - `:immediate` (default) or `:ignored`, for an EDA stop that
      leaves audio playing until it finishes on its own
    * `:join` - the result of `join` (default `:ok`)

  Unclaimed guilds answer with an idle, ready session and send nothing.
  """

  use Agent

  @idle %{
    owner: nil,
    channel: nil,
    ready: true,
    playing: false,
    play: [],
    stop: :immediate,
    join: :ok,
    holders: []
  }

  def start, do: Agent.start(fn -> %{} end, name: __MODULE__)

  def claim(guild_id, opts \\ []) do
    guild = %{
      @idle
      | owner: self(),
        channel: opts[:channel],
        ready: Keyword.get(opts, :ready, true),
        playing: Keyword.get(opts, :playing, false),
        play: Keyword.get(opts, :play, []),
        stop: Keyword.get(opts, :stop, :immediate),
        join: Keyword.get(opts, :join, :ok)
    }

    Agent.update(__MODULE__, &Map.put(&1, guild_id, guild))
    ExUnit.Callbacks.on_exit(fn -> release(guild_id) end)
    guild_id
  end

  defp release(guild_id) do
    guild = Agent.get_and_update(__MODULE__, &Map.pop(&1, guild_id, @idle))
    Enum.each(guild.holders, &Process.exit(&1, :kill))
  end

  def join(guild_id, channel_id) do
    notify(guild_id, {:join, channel_id})
    update(guild_id, &%{&1 | channel: channel_id, ready: true})
    guild(guild_id).join
  end

  def leave(guild_id) do
    notify(guild_id, :leave)
    update(guild_id, &%{&1 | channel: nil, playing: false})
    :ok
  end

  def play(guild_id, input, type, opts) do
    notify(guild_id, {:play, input, type, opts})

    case next_play_result(guild_id) do
      :hold ->
        holder = self()
        update(guild_id, &%{&1 | playing: true, holders: [holder | &1.holders]})
        notify(guild_id, {:holding, holder})
        receive do: (:never -> :ok)

      :ok ->
        update(guild_id, &%{&1 | playing: true})
        :ok

      {:error, :not_ready} = error ->
        update(guild_id, &%{&1 | ready: false})
        error

      error ->
        error
    end
  end

  def stop(guild_id) do
    notify(guild_id, :stop)

    update(guild_id, fn
      %{stop: :ignored} = guild -> guild
      guild -> %{guild | playing: false}
    end)

    :ok
  end

  def ready?(guild_id), do: guild(guild_id).ready
  def channel_id(guild_id), do: guild(guild_id).channel

  def playing?(guild_id) do
    case guild(guild_id).playing do
      :raise -> raise "playback status unavailable"
      playing -> playing
    end
  end

  def get_voice_state(_guild_id), do: {:ok, %{}}

  defp next_play_result(guild_id) do
    Agent.get_and_update(__MODULE__, fn guilds ->
      case Map.get(guilds, guild_id) do
        %{play: [result | rest]} = guild ->
          {result, Map.put(guilds, guild_id, %{guild | play: rest})}

        _ ->
          {:ok, guilds}
      end
    end)
  end

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
