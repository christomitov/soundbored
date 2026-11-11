defmodule SoundboardWeb.RawBodyReaderTest do
  @moduledoc """
  Only JSON bodies are kept for the webhook's signature check (proven end to
  end by the webhook tests in `SoundboardWeb.BillingWebTest`); other bodies,
  such as uploads, must not be held in memory.
  """

  use ExUnit.Case, async: true

  alias SoundboardWeb.RawBodyReader

  test "a non-JSON body is not cached" do
    conn =
      :post
      |> Plug.Test.conn("/upload", "binary-bytes")
      |> Plug.Conn.put_req_header("content-type", "multipart/form-data")

    assert {:ok, "binary-bytes", conn} = RawBodyReader.read_body(conn, [])
    assert conn.assigns[:raw_body] == nil
  end
end
