defmodule SoundboardWeb.Live.Hooks.Theme do
  @moduledoc """
  Assigns the active UI theme from the session (or cookie fallback).
  """

  import Phoenix.Component, only: [assign: 3]

  alias Soundboard.Theme

  def on_mount(:default, _params, session, socket) do
    theme =
      session
      |> Map.get("theme")
      |> Kernel.||(Map.get(session, :theme))
      |> Theme.normalize()

    {:cont, assign(socket, :theme, theme)}
  end
end
