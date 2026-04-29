defmodule Soundboard.Discord.Handler.IdleTimeoutPolicyTest do
  use ExUnit.Case, async: false

  alias Soundboard.Discord.Handler.IdleTimeoutPolicy

  setup do
    original = System.get_env("VOICE_IDLE_TIMEOUT_SECONDS")

    on_exit(fn ->
      if is_nil(original) do
        System.delete_env("VOICE_IDLE_TIMEOUT_SECONDS")
      else
        System.put_env("VOICE_IDLE_TIMEOUT_SECONDS", original)
      end
    end)

    :ok
  end

  test "defaults to 600 seconds (10 minutes) when env var is not set" do
    System.delete_env("VOICE_IDLE_TIMEOUT_SECONDS")
    assert IdleTimeoutPolicy.timeout_ms() == 600 * 1_000
  end

  test "reads VOICE_IDLE_TIMEOUT_SECONDS from environment" do
    System.put_env("VOICE_IDLE_TIMEOUT_SECONDS", "300")
    assert IdleTimeoutPolicy.timeout_ms() == 300 * 1_000
  end

  test "handles whitespace around the value" do
    System.put_env("VOICE_IDLE_TIMEOUT_SECONDS", "  30  ")
    assert IdleTimeoutPolicy.timeout_ms() == 30 * 1_000
  end

  test "returns nil when set to 0 (disabled)" do
    System.put_env("VOICE_IDLE_TIMEOUT_SECONDS", "0")
    assert IdleTimeoutPolicy.timeout_ms() == nil
  end

  test "returns nil when set to a negative value" do
    System.put_env("VOICE_IDLE_TIMEOUT_SECONDS", "-1")
    assert IdleTimeoutPolicy.timeout_ms() == nil
  end
end
