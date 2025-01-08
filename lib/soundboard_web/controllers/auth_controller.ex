defmodule SoundboardWeb.AuthController do
  use SoundboardWeb, :controller
  plug Ueberauth

  alias Soundboard.Accounts.User
  alias Soundboard.Repo

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
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Error signing in")
        |> redirect(to: ~p"/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: ~p"/")
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

  def request(conn, %{"provider" => "discord"}) do
    callback_url =
      if Application.get_env(:soundboard, :env) == :prod do
        host = System.get_env("PHX_HOST") || raise "PHX_HOST must be set"
        scheme = System.get_env("SCHEME") || "https"
        "#{scheme}://#{host}/auth/discord/callback"
      else
        url(conn, ~p"/auth/discord/callback")
      end

    discord_url =
      "https://discord.com/oauth2/authorize?" <>
        URI.encode_query(%{
          client_id: System.get_env("DISCORD_CLIENT_ID"),
          redirect_uri: callback_url,
          response_type: "code",
          scope: "identify",
          state: get_csrf_token()
        })

    redirect(conn, external: discord_url)
  end
end
