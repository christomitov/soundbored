defmodule Soundboard.Discord.Handler.IdleTimeoutPolicyTest do
  use ExUnit.Case, async: false

  alias Soundboard.Discord.Handler.IdleTimeoutPolicy

  setup do
    original = System.get_env("VOICE_IDLE_TIMEOUT_MINUTES")

    on_exit(fn ->
      if is_nil(original) do
        System.delete_env("VOICE_IDLE_TIMEOUT_MINUTES")
      else
        System.put_env("VOICE_IDLE_TIMEOUT_MINUTES", original)
      end
    end)

    :ok
  end

  test "defaults to 10 minutes when env var is not set" do
    System.delete_env("VOICE_IDLE_TIMEOUT_MINUTES")
    assert IdleTimeoutPolicy.timeout_ms() == 10 * 60_000
  end

  test "reads VOICE_IDLE_TIMEOUT_MINUTES from environment" do
    System.put_env("VOICE_IDLE_TIMEOUT_MINUTES", "5")
    assert IdleTimeoutPolicy.timeout_ms() == 5 * 60_000
  end

  test "handles whitespace around the value" do
    System.put_env("VOICE_IDLE_TIMEOUT_MINUTES", "  3  ")
    assert IdleTimeoutPolicy.timeout_ms() == 3 * 60_000
  end
end
