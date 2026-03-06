defmodule Soundboard.Discord.Consumer do
  @moduledoc false
  @behaviour EDA.Consumer

  alias Soundboard.Discord.Handler

  @impl true
  def handle_event({event_name, payload}) do
    event = {event_name, payload, nil}
    Handler.dispatch_event(event)
  end
end
