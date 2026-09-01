defmodule SoundboardWeb.GuildControllerTest do
  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias EDA.Cache
  alias Soundboard.Tenants

  @guild %{"id" => "guild-controller-test", "name" => "Test Guild"}

  defp conn!(conn),
    do: conn |> init_test_session(%{}) |> fetch_query_params() |> fetch_flash() |> Map.update!(:params, &Map.put(&1, "_format", "html"))

  defp call!(conn, action, params \\ %{}) do
    conn = Map.update!(conn, :params, &Map.merge(&1, params))
    SoundboardWeb.GuildController.call(conn, action)
  end

  test "GET /guilds renders the guild list", %{conn: conn} do
    with_mocks([
      {Cache, [],
       [
         guilds: fn -> [@guild] end,
         channels_for_guild: fn _ -> [] end,
         voice_states: fn _ -> [] end
       ]}
    ]) do
      conn = call!(conn!(conn) |> assign(:current_guild_id, nil) |> assign(:current_user, %{id: 1, username: "owner"}) |> assign(:current_path, "/guilds") |> assign(:presences, []), :index)

      assert html_response(conn, 200) =~ "Test Guild"
    end
  end

  test "POST /guilds/switch provisions the tenant and stores the session", %{conn: conn} do
    with_mocks([
      {Cache, [],
       [
         get_guild: fn _ -> @guild end,
         channels_for_guild: fn _ -> [] end,
         voice_states: fn _ -> [] end
       ]}
    ]) do
      conn = call!(conn!(conn), :switch, %{"discord_guild_id" => @guild["id"]})

      assert redirected_to(conn) == "/"
      assert get_session(conn, :guild_id) == @guild["id"]
      assert %Tenants.Guild{} = Tenants.get_guild(@guild["id"])
    end
  end

  test "POST /guilds/switch with unknown guild redirects with an error", %{conn: conn} do
    with_mocks([{Cache, [], [get_guild: fn _ -> nil end]}]) do
      conn = call!(conn!(conn), :switch, %{"discord_guild_id" => "guild-nope"})

      assert redirected_to(conn) == "/guilds"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Bot is not a member"
    end
  end
end
