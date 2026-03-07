defmodule Soundboard.Discord.RuntimeCapability do
  @moduledoc false

  require Logger

  alias EDA.Voice.Dave.Native

  def discord_handler_enabled? do
    Application.get_env(:soundboard, :env) != :test and voice_runtime_available?()
  end

  def voice_runtime_available? do
    match?(:ok, voice_runtime_status())
  end

  def voice_runtime_status do
    cond do
      Application.get_env(:soundboard, :env) == :test ->
        :ok

      not Application.get_env(:eda, :dave, false) ->
        :ok

      Native.available?() ->
        :ok

      true ->
        {:degraded, :dave_unavailable}
    end
  end

  def log_degraded_mode do
    case voice_runtime_status() do
      {:degraded, :dave_unavailable} ->
        Logger.error("""
        Discord voice runtime is disabled because EDA DAVE is enabled but the native library is unavailable.
        The web app will continue to boot, but Discord voice features stay offline until DAVE is packaged correctly
        or EDA_DAVE=false is configured.
        """)

        :ok

      _ ->
        :ok
    end
  end
end
