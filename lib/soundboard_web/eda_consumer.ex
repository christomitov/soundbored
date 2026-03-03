defmodule SoundboardWeb.EDAConsumer do
  @moduledoc false
  @behaviour EDA.Consumer

  @impl true
  def handle_event({event_name, payload}) do
    event = {event_name, payload, nil}

    case Process.whereis(SoundboardWeb.DiscordHandler) do
      nil -> SoundboardWeb.DiscordHandler.handle_event(event)
      _pid -> GenServer.cast(SoundboardWeb.DiscordHandler, {:eda_event, event})
    end
  end
end
