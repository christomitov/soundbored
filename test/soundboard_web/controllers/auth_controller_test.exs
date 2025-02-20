defmodule SoundboardWeb.AuthControllerTest do
  use SoundboardWeb.ConnCase
  alias Soundboard.{Accounts.User, Repo}

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

    on_exit(fn ->
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth)
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

      # Verify the count hasn't changed after the callback
      final_count = Repo.aggregate(User, :count)

      assert redirected_to(conn) == "/"
      assert get_session(conn, :user_id) == existing_user.id
      # Only increased by the one we created
      assert final_count == initial_count + 1
    end

    test "callback/2 handles auth failures", %{conn: conn} do
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
    end

    test "logout/2 clears session and redirects", %{conn: conn} do
      conn =
        conn
        |> put_session(:user_id, "test_id")
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == "/"
      refute get_session(conn, :user_id)
    end

    test "debug_session/2 returns session info", %{conn: conn} do
      user = insert_user()

      conn =
        conn
        |> put_session(:user_id, user.id)
        |> get(~p"/debug/session")

      assert json = json_response(conn, 200)
      assert json["session"]["user_id"] == user.id
      assert is_map(json["cookies"])
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
end
