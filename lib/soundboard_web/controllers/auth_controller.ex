defmodule SoundboardWeb.AuthController do
  use SoundboardWeb, :controller
  require Logger

  plug :ensure_scheme
  plug Ueberauth
  plug :override_callback_url

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
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: get_session(conn, :return_to) || "/")

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
    |> put_flash(:error, "Failed to authenticate: #{inspect(fails.errors)}")
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
    |> redirect(to: ~p"/")
  end

  def request(conn, %{"provider" => "discord"} = _params) do
    callback_url = Application.get_env(:ueberauth, Ueberauth.Strategy.Discord)[:callback_url]
    Logger.debug("Using callback URL: #{callback_url}")

    conn
  end

  defp ensure_scheme(conn, _opts) do
    scheme = System.get_env("SCHEME") || "https"
    %{conn | scheme: String.to_atom(scheme)}
  end

  defp override_callback_url(conn, _opts) do
    scheme = System.get_env("SCHEME") || "https"
    host = System.get_env("PHX_HOST")
    callback_url = "#{scheme}://#{host}/auth/discord/callback"

    conn
    |> assign(:ueberauth_callback_url, callback_url)
    |> put_private(:ueberauth_callback_url, callback_url)
  end

  def debug_session(conn, _params) do
    json(conn, %{
      session: get_session(conn),
      current_user: conn.assigns[:current_user],
      cookies: conn.cookies
    })
  end
end
