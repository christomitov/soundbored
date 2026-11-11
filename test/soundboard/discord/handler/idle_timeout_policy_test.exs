defmodule Soundboard.Discord.Handler.IdleTimeoutPolicyTest do
  use ExUnit.Case, async: false

  alias Soundboard.Discord.Handler.IdleTimeoutPolicy

  setup do
    on_exit(fn -> System.delete_env("VOICE_IDLE_TIMEOUT_SECONDS") end)
  end

  test "VOICE_IDLE_TIMEOUT_SECONDS sets the timeout, defaulting to ten minutes" do
    table = [
      {nil, 600_000},
      {"300", 300_000},
      {"  30  ", 30_000},
      {"0", nil},
      {"-1", nil},
      {"ten", 600_000}
    ]

    for {value, timeout_ms} <- table do
      if value,
        do: System.put_env("VOICE_IDLE_TIMEOUT_SECONDS", value),
        else: System.delete_env("VOICE_IDLE_TIMEOUT_SECONDS")

      assert {value, IdleTimeoutPolicy.timeout_ms()} == {value, timeout_ms}
    end
  end
end
