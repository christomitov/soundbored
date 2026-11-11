defmodule SoundboardWeb.BasicAuthPlugTest do
  @moduledoc """
  Optional HTTP basic auth: the credential parsing (plug level) and where the
  router applies it (signed-in browser pages; not sign-in itself, not the
  token API).
  """

  use SoundboardWeb.ConnCase, async: false

  alias SoundboardWeb.Plugs.BasicAuth

  setup do
    previous = Enum.map(~w(BASIC_AUTH_USERNAME BASIC_AUTH_PASSWORD), &{&1, System.get_env(&1)})

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    System.delete_env("BASIC_AUTH_USERNAME")
    System.delete_env("BASIC_AUTH_PASSWORD")
    :ok
  end

  describe "when not fully configured" do
    test "is off when both credentials are missing or blank" do
      for {user, pass} <- [{nil, nil}, {"  ", ""}] do
        configure(user, pass)
        refute BasicAuth.call(Plug.Test.conn(:get, "/"), %{}).halted
      end
    end

    test "fails closed when only one credential is set" do
      for {user, pass} <- [{"u", nil}, {nil, "p"}] do
        configure(user, pass)
        conn = BasicAuth.call(Plug.Test.conn(:get, "/"), %{})

        assert conn.halted
        assert conn.status == 401
      end
    end
  end

  describe "when configured" do
    test "admits matching credentials, including a password with a colon" do
      for {user, pass} <- [{"u", "p"}, {"u", "p:extra"}] do
        configure(user, pass)
        refute "u" |> header(pass) |> call() |> Map.get(:halted)
      end
    end

    test "challenges a missing, wrong or non-Basic authorization" do
      configure("u", "p")

      for authorization <- [nil, "Basic " <> Base.encode64("wrong:creds"), "Bearer token123"] do
        conn = call(authorization)

        assert conn.halted
        assert conn.status == 401
        assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="Soundboard")]
        assert conn.resp_body == "Unauthorized"
      end
    end

    test "guards signed-in pages but not sign-in or the token API", %{conn: conn} do
      configure("u", "p")
      user = user_fixture()

      assert conn |> sign_in(user) |> get("/guilds") |> response(401)

      assert conn
             |> sign_in(user)
             |> put_req_header("authorization", header("u", "p"))
             |> get("/onboarding")
             |> html_response(200)

      assert conn |> init_test_session(%{}) |> get("/") |> redirected_to() == "/auth/discord"
      Application.put_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth, client_id: "id")
      on_exit(fn -> Application.delete_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth) end)
      assert conn |> get("/auth/discord") |> redirected_to() =~ "discord.com"
      assert conn |> get("/api/sounds") |> json_response(401) == %{"error" => "Invalid API token"}
    end
  end

  defp configure(user, pass) do
    for {key, value} <- [{"BASIC_AUTH_USERNAME", user}, {"BASIC_AUTH_PASSWORD", pass}] do
      if value, do: System.put_env(key, value), else: System.delete_env(key)
    end
  end

  defp header(user, pass), do: "Basic " <> Base.encode64("#{user}:#{pass}")

  defp call(nil), do: BasicAuth.call(Plug.Test.conn(:get, "/"), %{})

  defp call(authorization) do
    :get
    |> Plug.Test.conn("/")
    |> put_req_header("authorization", authorization)
    |> BasicAuth.call(%{})
  end
end
