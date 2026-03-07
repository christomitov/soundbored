defmodule Soundboard.Discord.RuntimeCapabilityTest do
  use ExUnit.Case, async: false

  alias Soundboard.Discord.RuntimeCapability

  setup do
    original_env = Application.get_env(:soundboard, :env)
    original_dave = Application.get_env(:eda, :dave)

    on_exit(fn ->
      Application.put_env(:soundboard, :env, original_env)
      Application.put_env(:eda, :dave, original_dave)
    end)

    :ok
  end

  test "voice runtime is always available in test" do
    Application.put_env(:soundboard, :env, :test)
    Application.put_env(:eda, :dave, true)

    assert :ok = RuntimeCapability.voice_runtime_status()
    refute RuntimeCapability.discord_handler_enabled?()
  end

  test "voice runtime is available when dave is disabled" do
    Application.put_env(:soundboard, :env, :dev)
    Application.put_env(:eda, :dave, false)

    assert :ok = RuntimeCapability.voice_runtime_status()
    assert RuntimeCapability.discord_handler_enabled?()
  end
end
