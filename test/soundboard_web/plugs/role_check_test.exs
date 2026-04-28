defmodule SoundboardWeb.Plugs.RoleCheckTest do
  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.Discord.RoleChecker
  alias Soundboard.Repo
  alias SoundboardWeb.Plugs.RoleCheck

  setup do
    previous_guild = Application.get_env(:soundboard, :required_guild_id)
    previous_roles = Application.get_env(:soundboard, :required_role_ids)
    previous_interval = Application.get_env(:soundboard, :role_recheck_interval_seconds)

    on_exit(fn ->
      restore_env(:required_guild_id, previous_guild)
      restore_env(:required_role_ids, previous_roles)
      restore_env(:role_recheck_interval_seconds, previous_interval)
    end)

    {:ok, user: insert_user()}
  end

  defp restore_env(key, nil), do: Application.delete_env(:soundboard, key)
  defp restore_env(key, value), do: Application.put_env(:soundboard, key, value)

  defp insert_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer([:positive])}",
        discord_id: "discord_#{System.unique_integer([:positive])}",
        avatar: "avatar.jpg"
      })
      |> Repo.insert()

    user
  end

  defp build_conn_with_session(conn, user, session_params) do
    conn
    |> init_test_session(session_params)
    |> fetch_session()
    |> fetch_flash()
    |> assign(:current_user, user)
  end

  describe "feature disabled" do
    test "passes through without calling authorized? when feature is disabled", %{
      conn: conn,
      user: user
    } do
      with_mock RoleChecker,
        feature_enabled?: fn -> false end,
        authorized?: fn _ -> flunk("should not be called") end do
        result =
          conn
          |> build_conn_with_session(user, %{user_id: user.id})
          |> RoleCheck.call(RoleCheck.init([]))

        refute result.halted
      end
    end
  end

  describe "fresh timestamp" do
    setup do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])
      :ok
    end

    test "passes through without calling authorized? when roles_verified_at is fresh", %{
      conn: conn,
      user: user
    } do
      fresh_ts = System.system_time(:second)

      with_mock RoleChecker,
        feature_enabled?: fn -> true end,
        authorized?: fn _ -> flunk("should not be called") end do
        result =
          conn
          |> build_conn_with_session(user, %{
            user_id: user.id,
            roles_verified_at: fresh_ts
          })
          |> RoleCheck.call(RoleCheck.init([]))

        refute result.halted
      end
    end
  end

  describe "missing timestamp" do
    setup do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])
      :ok
    end

    test "triggers re-check and updates session when authorized and roles_verified_at is absent",
         %{conn: conn, user: user} do
      with_mock RoleChecker,
        feature_enabled?: fn -> true end,
        authorized?: fn _discord_id -> true end do
        result =
          conn
          |> build_conn_with_session(user, %{user_id: user.id})
          |> RoleCheck.call(RoleCheck.init([]))

        refute result.halted
        assert is_integer(get_session(result, :roles_verified_at))
        assert_called(RoleChecker.authorized?(user.discord_id))
      end
    end
  end

  describe "stale timestamp" do
    setup do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])
      :ok
    end

    test "triggers re-check and updates session when authorized and roles_verified_at is stale",
         %{
           conn: conn,
           user: user
         } do
      stale_ts = System.system_time(:second) - 999

      with_mock RoleChecker,
        feature_enabled?: fn -> true end,
        authorized?: fn _discord_id -> true end do
        result =
          conn
          |> build_conn_with_session(user, %{
            user_id: user.id,
            roles_verified_at: stale_ts
          })
          |> RoleCheck.call(RoleCheck.init([]))

        refute result.halted
        new_ts = get_session(result, :roles_verified_at)
        assert is_integer(new_ts)
        assert new_ts > stale_ts
        assert_called(RoleChecker.authorized?(user.discord_id))
      end
    end

    test "clears session, redirects, and halts when unauthorized", %{conn: conn, user: user} do
      stale_ts = System.system_time(:second) - 999

      with_mock RoleChecker,
        feature_enabled?: fn -> true end,
        authorized?: fn _discord_id -> false end do
        result =
          conn
          |> build_conn_with_session(user, %{
            user_id: user.id,
            roles_verified_at: stale_ts
          })
          |> RoleCheck.call(RoleCheck.init([]))

        assert result.halted
        assert redirected_to(result) == "/"

        assert Phoenix.Flash.get(result.assigns.flash, :error) ==
                 "Your role access has been revoked"

        refute get_session(result, :user_id)
        assert_called(RoleChecker.authorized?(user.discord_id))
      end
    end
  end
end
