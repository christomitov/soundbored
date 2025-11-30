defmodule SoundboardWeb.RouterAuthFlowTest do
  # Not async: manipulates global env and basic auth credentials.
  use SoundboardWeb.ConnCase, async: false

  alias Soundboard.Accounts.Tenants

  setup do
    original = Application.get_env(:soundboard, :edition, :community)

    on_exit(fn ->
      Application.put_env(:soundboard, :edition, original)
      System.delete_env("BASIC_AUTH_USERNAME")
      System.delete_env("BASIC_AUTH_PASSWORD")
      System.delete_env("API_TOKEN")
    end)

    Application.put_env(:soundboard, :edition, :community)
    Tenants.ensure_default_tenant!()
    :ok
  end

  test "allows community access via basic auth without Discord", %{conn: conn} do
    System.put_env("BASIC_AUTH_USERNAME", "u")
    System.put_env("BASIC_AUTH_PASSWORD", "p")

    header = "Basic " <> Base.encode64("u:p")

    conn =
      conn
      |> put_req_header("authorization", header)
      |> get("/")

    assert html_response(conn, 200) =~ "SoundBored"
  end

  test "allows community access via API token without basic auth challenge", %{conn: conn} do
    System.put_env("BASIC_AUTH_USERNAME", "u")
    System.put_env("BASIC_AUTH_PASSWORD", "p")
    System.put_env("API_TOKEN", "sb-token")

    conn =
      conn
      |> put_req_header("authorization", "Bearer sb-token")
      |> get("/")

    assert html_response(conn, 200) =~ "SoundBored"
  end
end
