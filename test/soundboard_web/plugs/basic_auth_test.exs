defmodule SoundboardWeb.BasicAuthPlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias SoundboardWeb.Plugs.BasicAuth

  setup do
    previous_username = System.get_env("BASIC_AUTH_USERNAME")
    previous_password = System.get_env("BASIC_AUTH_PASSWORD")

    System.delete_env("BASIC_AUTH_USERNAME")
    System.delete_env("BASIC_AUTH_PASSWORD")

    # Reset env between tests and restore shell values afterward.
    on_exit(fn ->
      restore_env("BASIC_AUTH_USERNAME", previous_username)
      restore_env("BASIC_AUTH_PASSWORD", previous_password)
    end)

    :ok
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  test "skips when credentials not configured" do
    conn = conn(:get, "/") |> BasicAuth.call(%{})
    refute conn.halted
  end

  test "skips when credentials blank" do
    System.put_env("BASIC_AUTH_USERNAME", "  ")
    System.put_env("BASIC_AUTH_PASSWORD", "")

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

  test "authorizes when password contains a colon" do
    System.put_env("BASIC_AUTH_USERNAME", "u")
    System.put_env("BASIC_AUTH_PASSWORD", "p:extra")

    header = "Basic " <> Base.encode64("u:p:extra")

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
    assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="Soundboard")]
    assert conn.resp_body == "Unauthorized"
  end
end
