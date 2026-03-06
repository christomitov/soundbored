defmodule SoundboardWeb.EDAConsumerTest do
  use ExUnit.Case, async: false

  alias SoundboardWeb.{DiscordHandler, EDAConsumer}

  setup do
    on_exit(fn ->
      if Process.whereis(DiscordHandler) == self() do
        Process.unregister(DiscordHandler)
      end
    end)

    :ok
  end

  test "dispatches events through the DiscordHandler GenServer boundary" do
    Process.register(self(), DiscordHandler)

    assert :ok = EDAConsumer.handle_event({:READY, %{id: "1"}})

    assert_receive {:"$gen_cast", {:eda_event, {:READY, %{id: "1"}, nil}}}
  end

  test "returns error when the DiscordHandler is unavailable" do
    refute Process.whereis(DiscordHandler)

    assert :error = EDAConsumer.handle_event({:READY, %{id: "1"}})
  end
end
