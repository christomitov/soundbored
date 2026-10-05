defmodule SoundboardWeb.RawBodyReaderTest do
  @moduledoc """
  The raw-body cache feeds Stripe webhook signature verification, so JSON
  bodies must land in assigns untouched and non-JSON bodies must not be cached.
  """

  use ExUnit.Case, async: true

  alias SoundboardWeb.RawBodyReader

  test "a JSON body is cached in assigns.raw_body" do
    conn =
      :post
      |> Plug.Test.conn("/billing/webhook", ~s({"type":"ping"}))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    assert {:ok, ~s({"type":"ping"}), conn} = RawBodyReader.read_body(conn, [])
    assert conn.assigns[:raw_body] == [~s({"type":"ping"})]
  end

  test "a non-JSON body is not cached" do
    conn =
      :post
      |> Plug.Test.conn("/upload", "binary-bytes")
      |> Plug.Conn.put_req_header("content-type", "multipart/form-data")

    assert {:ok, "binary-bytes", conn} = RawBodyReader.read_body(conn, [])
    assert conn.assigns[:raw_body] == nil
  end
end
