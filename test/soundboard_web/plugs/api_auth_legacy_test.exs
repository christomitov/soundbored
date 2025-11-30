defmodule SoundboardWeb.APIAuthLegacyTest do
  use SoundboardWeb.ConnCase, async: true

  alias Soundboard.Accounts.Tenants
  alias SoundboardWeb.Plugs.APIAuth

  setup do
    original = Application.get_env(:soundboard, :edition, :community)
    original_token = System.get_env("API_TOKEN")

    on_exit(fn ->
      Application.put_env(:soundboard, :edition, original)

      if original_token,
        do: System.put_env("API_TOKEN", original_token),
        else: System.delete_env("API_TOKEN")
    end)

    :ok
  end

  test "rejects requests without bearer token", %{conn: conn} do
    conn = conn |> Plug.Test.init_test_session(%{}) |> APIAuth.call(%{})

    assert conn.halted
    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "Invalid API token"
  end

  test "accepts legacy token in community mode and persists session", %{conn: conn} do
    tenant = Tenants.ensure_default_tenant!()
    Application.put_env(:soundboard, :edition, :community)
    System.put_env("API_TOKEN", "legacy-token")

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.assign(:tenant_resolution_source, nil)
      |> Plug.Conn.assign(:tenant_resolution_reason, nil)
      |> Plug.Conn.put_req_header("authorization", "Bearer legacy-token")
      |> APIAuth.call(%{})

    refute conn.halted
    assert conn.assigns.api_token == :legacy
    assert conn.assigns.current_tenant.id == tenant.id
    assert get_session(conn, :tenant_id) == tenant.id
  end
end
