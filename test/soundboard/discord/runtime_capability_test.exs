defmodule Soundboard.Discord.RuntimeCapabilityTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias EDA.Voice.Dave.Native
  alias Soundboard.Discord.RuntimeCapability

  setup do
    original_env = Application.get_env(:soundboard, :env)
    original_dave = Application.get_env(:eda, :dave)
    Application.put_env(:soundboard, :env, :dev)

    on_exit(fn ->
      Application.put_env(:soundboard, :env, original_env)
      Application.put_env(:eda, :dave, original_dave)
    end)
  end

  test "voice runtime is available when dave is disabled" do
    Application.put_env(:eda, :dave, false)

    assert :ok = RuntimeCapability.voice_runtime_status()
    assert RuntimeCapability.discord_handler_enabled?()
  end

  test "dave without its native library degrades voice and keeps the handler off" do
    Application.put_env(:eda, :dave, true)

    with_mock Native, available?: fn -> false end do
      assert {:degraded, :dave_unavailable} = RuntimeCapability.voice_runtime_status()
      refute RuntimeCapability.discord_handler_enabled?()
      assert capture_log(&RuntimeCapability.log_degraded_mode/0) =~ "EDA DAVE is enabled"
    end
  end
end
