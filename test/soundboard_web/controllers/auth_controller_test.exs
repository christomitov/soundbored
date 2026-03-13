defmodule SoundboardWeb.AuthControllerTest do
  use SoundboardWeb.ConnCase
  alias Soundboard.{Accounts.User, Repo}
  import Mock
  import ExUnit.CaptureLog

  setup %{conn: conn} do
    # Clean up users before each test
    Repo.delete_all(User)

    # Initialize session and CSRF token for all tests
    conn =
      conn
      |> init_test_session(%{})
      |> fetch_session()
      |> fetch_flash()

    # Mock Discord OAuth config for tests
    Application.put_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth,
      client_id: "test_client_id",
      client_secret: "test_client_secret"
    )
    previous_required_guild_id = Application.get_env(:soundboard, :oauth_required_guild_id)
    previous_allowed_role_ids = Application.get_env(:soundboard, :oauth_allowed_role_ids)
    previous_member_client = Application.get_env(:soundboard, :discord_member_client)

    Application.put_env(:soundboard, :oauth_required_guild_id, "")
    Application.put_env(:soundboard, :oauth_allowed_role_ids, [])
    Application.put_env(:soundboard, :discord_member_client, Soundboard.Discord.MemberClient)

    on_exit(fn ->
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth)
      restore_value(:soundboard, :oauth_required_guild_id, previous_required_guild_id)
      restore_value(:soundboard, :oauth_allowed_role_ids, previous_allowed_role_ids)
      restore_value(:soundboard, :discord_member_client, previous_member_client)
    end)

    {:ok, conn: conn}
  end

  describe "auth flow" do
    test "request/2 initiates Discord auth and sets session", %{conn: conn} do
      conn = get(conn, ~p"/auth/discord")

      # Redirect status
      assert conn.status == 302

      assert String.starts_with?(
               redirected_to(conn),
               "https://discord.com/api/oauth2/authorize"
             )
    end

    test "request/2 rejects unsupported providers with a controlled 404", %{conn: conn} do
      conn = get(conn, "/auth/not-real")

      assert response(conn, 404) == "Unsupported auth provider"
    end

    test "callback/2 creates new user on successful auth", %{conn: conn} do
      auth_data = %{
        uid: "12345",
        info: %{
          nickname: "TestUser",
          image: "test_avatar.jpg"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth_data)
        |> get(~p"/auth/discord/callback")

      assert redirected_to(conn) == "/"
      assert get_session(conn, :user_id)

      user = Repo.get_by(User, discord_id: "12345")
      assert user
      assert user.username == "TestUser"
      assert user.avatar == "test_avatar.jpg"
    end

    test "callback/2 uses existing user if found", %{conn: conn} do
      # Get initial user count
      initial_count = Repo.aggregate(User, :count)

      # Create existing user
      {:ok, existing_user} =
        %User{}
        |> User.changeset(%{
          discord_id: "12345",
          username: "ExistingUser",
          avatar: "old_avatar.jpg"
        })
        |> Repo.insert()

      auth_data = %{
        uid: "12345",
        info: %{
          nickname: "TestUser",
          image: "test_avatar.jpg"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth_data)
        |> get(~p"/auth/discord/callback")

      final_count = Repo.aggregate(User, :count)

      assert redirected_to(conn) == "/"
      assert get_session(conn, :user_id) == existing_user.id
      # Only increased by the one we created
      assert final_count == initial_count + 1
    end

    test "callback/2 handles auth failures", %{conn: conn} do
      capture_log(fn ->
        conn =
          conn
          |> assign(:ueberauth_failure, %{
            errors: [
              %Ueberauth.Failure.Error{
                message_key: "invalid_credentials",
                message: "Invalid credentials"
              }
            ]
          })
          |> get(~p"/auth/discord/callback")

        assert redirected_to(conn) == "/"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed to authenticate"
      end)
    end

    test "callback/2 denies users missing required guild membership", %{conn: conn} do
      Application.put_env(:soundboard, :oauth_required_guild_id, "guild-123")
      Application.put_env(:soundboard, :oauth_allowed_role_ids, ["role-a", "role-b"])

      auth_data = %{
        uid: "12345",
        credentials: %{token: "oauth-token"},
        info: %{
          nickname: "TestUser",
          image: "test_avatar.jpg"
        }
      }

      with_mock Soundboard.Discord.MemberClient,
                [get_member_roles: fn "guild-123", "12345", "oauth-token" -> {:error, :not_in_guild} end] do
        conn =
          conn
          |> assign(:ueberauth_auth, auth_data)
          |> get(~p"/auth/discord/callback")

        assert redirected_to(conn) == "/"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                 "Access denied: not a member of the required Discord server."
        refute get_session(conn, :user_id)
        refute Repo.get_by(User, discord_id: "12345")
      end
    end

    test "callback/2 denies users missing required roles", %{conn: conn} do
      Application.put_env(:soundboard, :oauth_required_guild_id, "guild-123")
      Application.put_env(:soundboard, :oauth_allowed_role_ids, ["role-admin"])

      auth_data = %{
        uid: "12345",
        credentials: %{token: "oauth-token"},
        info: %{
          nickname: "TestUser",
          image: "test_avatar.jpg"
        }
      }

      with_mock Soundboard.Discord.MemberClient,
                [get_member_roles: fn "guild-123", "12345", "oauth-token" -> {:ok, ["role-user"]} end] do
        conn =
          conn
          |> assign(:ueberauth_auth, auth_data)
          |> get(~p"/auth/discord/callback")

        assert redirected_to(conn) == "/"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                 "Access denied: you do not have a required role."
        refute get_session(conn, :user_id)
      end
    end

    test "logout/2 clears session and redirects", %{conn: conn} do
      conn =
        conn
        |> put_session(:user_id, "test_id")
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == "/"
      refute get_session(conn, :user_id)
    end

    test "debug_session/2 returns limited session info", %{conn: conn} do
      user = insert_user()

      conn =
        conn
        |> put_session(:session_id, 123)
        |> put_session(:user_id, user.id)
        |> get(~p"/debug/session")

      assert json = json_response(conn, 200)
      assert json == %{"session" => %{"session_id" => 123, "user_id" => user.id}}
    end
  end

  # Helper function
  defp insert_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer([:positive])}",
        discord_id: "#{System.unique_integer([:positive])}",
        avatar: "test_avatar.jpg"
      })
      |> Repo.insert()

    user
  end

  defp restore_value(app, key, nil), do: Application.delete_env(app, key)
  defp restore_value(app, key, value), do: Application.put_env(app, key, value)
end
