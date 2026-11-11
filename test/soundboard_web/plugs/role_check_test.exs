defmodule SoundboardWeb.Plugs.RoleCheckTest do
  @moduledoc """
  The periodic Discord role re-check for signed-in users: skipped when the
  feature is off or the last check is fresh, refreshed when it is due, and a
  user who lost the role is signed out (through the router).
  """

  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias EDA.API.Member
  alias Soundboard.Discord.RoleChecker
  alias SoundboardWeb.Plugs.RoleCheck

  setup do
    previous =
      for key <- [:required_guild_id, :required_role_ids, :role_recheck_interval_seconds],
          do: {key, Application.get_env(:soundboard, key)}

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:soundboard, key),
          else: Application.put_env(:soundboard, key, value)
      end
    end)

    {:ok, user: user_fixture()}
  end

  test "makes no Discord call when roles are not required", %{conn: conn, user: user} do
    with_mock RoleChecker,
      feature_enabled?: fn -> false end,
      authorized?: fn _ -> flunk("should not be called") end do
      refute conn |> signed_in(user, %{}) |> RoleCheck.call([]) |> Map.get(:halted)
    end
  end

  describe "with roles required" do
    setup do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])
      :ok
    end

    test "makes no Discord call while the last check is fresh", %{conn: conn, user: user} do
      with_mock RoleChecker, [:passthrough],
        authorized?: fn _ -> flunk("should not be called") end do
        session = %{roles_verified_at: System.system_time(:second)}
        refute conn |> signed_in(user, session) |> RoleCheck.call([]) |> Map.get(:halted)
      end
    end

    test "re-checks a missing or stale check and records the new time", %{
      conn: conn,
      user: user
    } do
      stale = System.system_time(:second) - 999

      with_mock RoleChecker, [:passthrough], authorized?: fn _ -> true end do
        for session <- [%{}, %{roles_verified_at: stale}] do
          result = conn |> signed_in(user, session) |> RoleCheck.call([])

          refute result.halted
          assert get_session(result, :roles_verified_at) > stale
        end

        assert_called(RoleChecker.authorized?(user.discord_id))
      end
    end

    test "signs out a user who no longer has the role", %{conn: conn, user: user} do
      stale = System.system_time(:second) - 999

      with_mock Member, get: fn "g1", _ -> {:ok, %{"roles" => ["other"]}} end do
        conn = conn |> sign_in(user, %{roles_verified_at: stale}) |> get("/guilds")

        assert redirected_to(conn) == "/"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Error signing in"
        assert get_session(conn, :user_id) == nil
      end
    end
  end

  defp signed_in(conn, user, session) do
    conn
    |> sign_in(user, session)
    |> fetch_session()
    |> fetch_flash()
    |> assign(:current_user, user)
  end
end
