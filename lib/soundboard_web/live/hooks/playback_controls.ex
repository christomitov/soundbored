defmodule SoundboardWeb.Live.Hooks.PlaybackControls do
  @moduledoc """
  Shared playback controls available from layout chrome (e.g. desk transport).
  """

  import Phoenix.LiveView

  alias Soundboard.AudioPlayer

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :playback_controls, :handle_event, &handle_event/3)}
  end

  defp handle_event("stop_sound", _params, socket) do
    socket = push_event(socket, "stop-all-sounds", %{})
    AudioPlayer.stop_sound()
    {:halt, socket}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
