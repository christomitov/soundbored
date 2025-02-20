defmodule SoundboardWeb.Plugs.BasicAuthTest do
  use SoundboardWeb.ConnCase
  alias SoundboardWeb.Plugs.BasicAuth

  setup do
    # Store original env values
    original_username = System.get_env("BASIC_AUTH_USERNAME")
    original_password = System.get_env("BASIC_AUTH_PASSWORD")

    on_exit(fn ->
      # Restore original env values after each test
      if original_username, do: System.put_env("BASIC_AUTH_USERNAME", original_username)
      if original_password, do: System.put_env("BASIC_AUTH_PASSWORD", original_password)
    end)

    :ok
  end

  describe "basic auth plug" do
    test "allows request when credentials are not configured", %{conn: conn} do
      System.delete_env("BASIC_AUTH_USERNAME")
      System.delete_env("BASIC_AUTH_PASSWORD")

      conn = BasicAuth.call(conn, [])
      refute conn.halted
      refute conn.status == 401
    end

    test "allows request with valid credentials", %{conn: conn} do
      System.put_env("BASIC_AUTH_USERNAME", "admin")
      System.put_env("BASIC_AUTH_PASSWORD", "secret")

      auth_header = "Basic " <> Base.encode64("admin:secret")

      conn =
        conn
        |> put_req_header("authorization", auth_header)
        |> BasicAuth.call([])

      refute conn.halted
      refute conn.status == 401
    end

    test "rejects request with invalid credentials", %{conn: conn} do
      System.put_env("BASIC_AUTH_USERNAME", "admin")
      System.put_env("BASIC_AUTH_PASSWORD", "secret")

      auth_header = "Basic " <> Base.encode64("wrong:password")

      conn =
        conn
        |> put_req_header("authorization", auth_header)
        |> BasicAuth.call([])

      assert conn.halted
      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="Soundbored")]
    end

    test "rejects request with missing auth header when credentials are configured", %{conn: conn} do
      System.put_env("BASIC_AUTH_USERNAME", "admin")
      System.put_env("BASIC_AUTH_PASSWORD", "secret")

      conn = BasicAuth.call(conn, [])

      assert conn.halted
      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="Soundbored")]
    end

    test "rejects request with malformed auth header", %{conn: conn} do
      System.put_env("BASIC_AUTH_USERNAME", "admin")
      System.put_env("BASIC_AUTH_PASSWORD", "secret")

      conn =
        conn
        |> put_req_header("authorization", "Basic not-base64")
        |> BasicAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects request with invalid base64 in auth header", %{conn: conn} do
      System.put_env("BASIC_AUTH_USERNAME", "admin")
      System.put_env("BASIC_AUTH_PASSWORD", "secret")

      conn =
        conn
        |> put_req_header("authorization", "Basic %%%%")
        |> BasicAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects request with wrong number of credential parts", %{conn: conn} do
      System.put_env("BASIC_AUTH_USERNAME", "admin")
      System.put_env("BASIC_AUTH_PASSWORD", "secret")

      # Encode just username without password
      auth_header = "Basic " <> Base.encode64("admin")

      conn =
        conn
        |> put_req_header("authorization", auth_header)
        |> BasicAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end
end
