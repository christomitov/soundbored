defmodule SoundboardWeb.EDAConsumer do
  @moduledoc false
  @behaviour EDA.Consumer

  @impl true
  def handle_event({event_name, payload}) do
    event = {event_name, payload, nil}
    SoundboardWeb.DiscordHandler.dispatch_event(event)
  end
end
