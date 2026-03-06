defmodule Soundboard.Discord.ConsumerTest do
  use ExUnit.Case, async: false

  alias Soundboard.Discord.{Consumer, Handler}

  setup do
    on_exit(fn ->
      if Process.whereis(Handler) == self() do
        Process.unregister(Handler)
      end
    end)

    :ok
  end

  test "dispatches events through the DiscordHandler GenServer boundary" do
    Process.register(self(), Handler)

    assert :ok = Consumer.handle_event({:READY, %{id: "1"}})

    assert_receive {:"$gen_cast", {:eda_event, {:READY, %{id: "1"}, nil}}}
  end

  test "returns error when the DiscordHandler is unavailable" do
    refute Process.whereis(Handler)

    assert :error = Consumer.handle_event({:READY, %{id: "1"}})
  end
end
