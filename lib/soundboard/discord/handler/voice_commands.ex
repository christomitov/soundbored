defmodule Soundboard.Discord.Handler.VoiceCommands do
  @moduledoc false

  require Logger

  alias Soundboard.AudioPlayer
  alias Soundboard.Discord.{BotIdentity, Voice}

  def join_voice_channel(guild_id, channel_id) do
    execute(
      connected_to_discord?(),
      "Skipping join_voice_channel - not connected to Discord",
      fn ->
        Logger.info("Bot joining voice channel #{channel_id} in guild #{guild_id}")
        run("join voice channel", fn -> Voice.join_channel(guild_id, channel_id) end)
      end,
      fn -> AudioPlayer.set_voice_channel(guild_id, channel_id) end,
      fn error_msg -> Logger.error("Error joining voice channel: #{error_msg}") end
    )
  end

  def leave_voice_channel(guild_id) do
    execute(
      connected_to_discord?(),
      "Skipping leave_voice_channel - not connected to Discord",
      fn ->
        Logger.info("Bot leaving voice channel in guild #{guild_id}")
        run("leave voice channel", fn -> Voice.leave_channel(guild_id) end)
      end,
      fn -> AudioPlayer.set_voice_channel(nil, nil) end,
      fn error_msg -> Logger.error("Error leaving voice channel: #{error_msg}") end
    )
  end

  def connected_to_discord? do
    ready = :persistent_term.get(:soundboard_bot_ready, false)

    if ready do
      try do
        case BotIdentity.fetch() do
          {:ok, _} ->
            Logger.debug("Discord connection check: Connected and ready")
            true

          error ->
            Logger.debug("Discord connection check failed: #{inspect(error)}")
            false
        end
      rescue
        error ->
          Logger.debug("Discord connection check error: #{inspect(error)}")
          false
      end
    else
      Logger.debug("Discord connection check: Bot not ready (READY event not received)")
      false
    end
  end

  defp execute(true, _skip_message, command_fun, success_fun, error_fun) do
    case command_fun.() do
      :ok -> success_fun.()
      {:error, error_msg} -> error_fun.(error_msg)
    end
  end

  defp execute(false, skip_message, _command_fun, _success_fun, _error_fun) do
    Logger.warning(skip_message)
  end

  defp run(action, command) do
    case safely_run(command) do
      :ok ->
        :ok

      {:error, error_msg} ->
        if rate_limited?(error_msg) do
          Logger.warning("Rate limited while trying to #{action}, retrying in 5 seconds...")
          Process.sleep(5000)
          safely_run(command)
        else
          {:error, error_msg}
        end
    end
  end

  defp safely_run(command) do
    case command.() do
      :ok -> :ok
      other -> {:error, inspect(other)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp rate_limited?(error_msg) do
    is_binary(error_msg) and String.contains?(String.downcase(error_msg), "rate limit")
  end
end
