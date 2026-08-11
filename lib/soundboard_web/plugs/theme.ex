defmodule SoundboardWeb.Plugs.Theme do
  @moduledoc """
  Loads the UI theme preference into the session from cookie when missing.
  """

  import Plug.Conn

  alias Soundboard.Theme

  def init(opts), do: opts

  def call(conn, _opts) do
    session_theme = get_session(conn, :theme)

    if Theme.valid?(session_theme) do
      assign(conn, :theme, Theme.normalize(session_theme))
    else
      conn = fetch_cookies(conn)
      theme = Theme.normalize(conn.cookies["sb_theme"])

      conn
      |> put_session(:theme, theme)
      |> assign(:theme, theme)
    end
  end
end
