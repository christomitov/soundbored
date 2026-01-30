defmodule SoundboardWeb.VoiceJoinGuard do
  @moduledoc """
  Coordinates voice join attempts to avoid reconnect storms.
  """

  require Logger
  alias Nostrum.Voice

  @table :voice_join_guard
  @default_min_interval_ms 3_000
  @default_in_flight_ttl_ms 10_000

  def join(guild_id, channel_id, opts \\ []) do
    min_interval_ms = Keyword.get(opts, :min_interval_ms, @default_min_interval_ms)
    in_flight_ttl_ms = Keyword.get(opts, :in_flight_ttl_ms, @default_in_flight_ttl_ms)

    ensure_table()
    now_ms = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, guild_id) do
      [{^guild_id, %{last_attempt_ms: last, in_flight: true}}]
      when now_ms - last < in_flight_ttl_ms ->
        Logger.debug("Voice join skipped for guild #{guild_id}: join in flight")
        {:skip, :in_flight}

      [{^guild_id, %{last_attempt_ms: last}}] when now_ms - last < min_interval_ms ->
        Logger.debug("Voice join skipped for guild #{guild_id}: throttled")
        {:skip, :rate_limited}

      _ ->
        :ets.insert(@table, {guild_id, %{last_attempt_ms: now_ms, in_flight: true}})

        try do
          Voice.join_channel(guild_id, channel_id)
          :ok
        rescue
          error ->
            Logger.error("Voice join failed for guild #{guild_id}: #{inspect(error)}")
            {:error, error}
        catch
          :exit, reason ->
            Logger.error("Voice join crashed for guild #{guild_id}: #{inspect(reason)}")
            {:error, reason}
        after
          mark_complete(guild_id)
        end
    end
  end

  defp mark_complete(guild_id) do
    ensure_table()

    case :ets.lookup(@table, guild_id) do
      [{^guild_id, data}] -> :ets.insert(@table, {guild_id, %{data | in_flight: false}})
      _ -> :ok
    end
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [
          :set,
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end
end
