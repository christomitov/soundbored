defmodule SoundboardWeb.AuthController do
  use SoundboardWeb, :controller
  require Logger

  plug Ueberauth

  alias Soundboard.Accounts.User
  alias Soundboard.Repo

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    Logger.debug("Auth callback received with uid: #{auth.uid}")

    user_params = %{
      discord_id: auth.uid,
      username: auth.info.nickname || auth.info.name,
      avatar: auth.info.image
    }

    case find_or_create_user(user_params) do
      {:ok, user} ->
        Logger.debug("User found/created successfully: #{user.id}")
        return_to = get_session(conn, :return_to) || "/"

        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> delete_session(:return_to)
        |> redirect(to: return_to)

      {:error, reason} ->
        Logger.error("Failed to create/find user: #{inspect(reason)}")
        conn
        |> put_flash(:error, "Error signing in")
        |> redirect(to: "/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: fails}} = conn, _params) do
    Logger.error("Authentication failed: #{inspect(fails)}")
    conn
    |> put_flash(:error, "Failed to authenticate")
    |> redirect(to: "/")
  end

  defp find_or_create_user(%{discord_id: discord_id} = params) do
    case Repo.get_by(User, discord_id: discord_id) do
      nil ->
        %User{}
        |> User.changeset(params)
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/")
  end

  def debug_session(conn, _params) do
    json(conn, %{
      session: get_session(conn),
      current_user: conn.assigns[:current_user],
      cookies: conn.cookies
    })
  end

  def request(conn, %{"provider" => "discord"} = _params) do
    client_id = System.get_env("DISCORD_CLIENT_ID")
    client_secret = System.get_env("DISCORD_CLIENT_SECRET")

    Logger.debug("""
    Discord OAuth Debug:
    Client ID: #{client_id || "not set"}
    Client Secret: #{if client_secret, do: "set", else: "not set"}
    """)

    conn
  end
end
