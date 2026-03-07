defmodule SoundboardWeb.AuthController do
  use SoundboardWeb, :controller

  plug Ueberauth

  alias Soundboard.Accounts.User
  alias Soundboard.Repo

  def request(conn, %{"provider" => "discord"} = _params) do
    conn
    |> put_session(:session_id, System.unique_integer())
    |> configure_session(renew: true)
  end

  def request(conn, _params) do
    conn
    |> put_status(:not_found)
    |> text("Unsupported auth provider")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_params = %{
      discord_id: auth.uid,
      username: auth.info.nickname || auth.info.name,
      avatar: auth.info.image
    }

    case find_or_create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> redirect(to: "/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Error signing in")
        |> redirect(to: "/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
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
      session: %{
        session_id: get_session(conn, :session_id),
        user_id: get_session(conn, :user_id)
      }
    })
  end
end
