defmodule SoundboardWeb.BasicAuthPlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias SoundboardWeb.Plugs.BasicAuth

  setup do
    # Reset env between tests
    on_exit(fn ->
      System.delete_env("BASIC_AUTH_USERNAME")
      System.delete_env("BASIC_AUTH_PASSWORD")
    end)

    :ok
  end

  test "skips when credentials not configured" do
    conn = conn(:get, "/") |> BasicAuth.call(%{})
    refute conn.halted
  end

  test "authorizes with valid Basic header" do
    System.put_env("BASIC_AUTH_USERNAME", "u")
    System.put_env("BASIC_AUTH_PASSWORD", "p")

    header = "Basic " <> Base.encode64("u:p")

    conn =
      conn(:get, "/")
      |> put_req_header("authorization", header)
      |> BasicAuth.call(%{})

    refute conn.halted
  end

  test "rejects with 401 when header invalid" do
    System.put_env("BASIC_AUTH_USERNAME", "u")
    System.put_env("BASIC_AUTH_PASSWORD", "p")

    conn = conn(:get, "/") |> BasicAuth.call(%{})
    assert conn.halted
    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="Soundbored")]
    assert conn.resp_body == "Unauthorized"
  end
end
