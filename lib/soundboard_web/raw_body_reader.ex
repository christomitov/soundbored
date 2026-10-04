defmodule SoundboardWeb.RawBodyReader do
  @moduledoc """
  A `Plug.Parsers` body_reader that keeps the untouched JSON request body in
  `conn.assigns[:raw_body]` (a list of chunks).

  Stripe webhook signatures are computed over the raw bytes, and the JSON
  parser consumes the body before the controller runs, so the raw body must be
  captured during parsing. Only JSON bodies are cached — upload bodies go
  through the multipart parser and would otherwise be held in memory whole.
  """

  def read_body(conn, opts) do
    json? =
      conn
      |> Plug.Conn.get_req_header("content-type")
      |> Enum.any?(fn
        "application/json" <> _ -> true
        _ -> false
      end)

    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      conn =
        if json? do
          Plug.Conn.assign(conn, :raw_body, [body | List.wrap(conn.assigns[:raw_body])])
        else
          conn
        end

      {:ok, body, conn}
    end
  end
end
