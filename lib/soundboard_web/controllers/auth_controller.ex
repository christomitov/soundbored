defmodule SoundboardWeb.AuthController do
  use SoundboardWeb, :controller
  require Logger

  plug Ueberauth

  alias Soundboard.Accounts.{Tenants, User}
  alias Soundboard.Repo

  def request(conn, %{"provider" => "discord"} = _params) do
    Logger.debug("""
    Auth Request Debug:
    Session ID: #{inspect(get_session(conn, :session_id))}
    All Session Data: #{inspect(get_session(conn))}
    Cookies: #{inspect(conn.cookies)}
    """)

    # Set a session ID to track session consistency
    conn
    |> put_session(:session_id, System.unique_integer())
    |> configure_session(renew: true)
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    tenant = Tenants.ensure_default_tenant!()

    user_params = %{
      discord_id: auth.uid,
      username: auth.info.nickname || auth.info.name,
      avatar: auth.info.image,
      tenant_id: tenant.id
    }

    case find_or_create_user(user_params, tenant) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_session(:tenant_id, tenant.id)
        |> redirect(to: "/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Error signing in")
        |> redirect(to: "/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: fails}} = conn, _params) do
    Logger.error("""
    Authentication failed:
    Failure: #{inspect(fails)}
    Session ID: #{inspect(get_session(conn, :session_id))}
    All Session Data: #{inspect(get_session(conn))}
    Cookies: #{inspect(conn.cookies)}
    """)

    conn
    |> put_flash(:error, "Failed to authenticate")
    |> redirect(to: "/")
  end

  defp find_or_create_user(%{discord_id: discord_id} = params, tenant) do
    case Repo.get_by(User, discord_id: discord_id, tenant_id: tenant.id) do
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
end
