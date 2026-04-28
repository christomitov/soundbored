defmodule SoundboardWeb.Plugs.RoleCheck do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller

  alias Soundboard.Discord.RoleChecker

  def init(opts), do: opts

  def call(conn, _opts) do
    if RoleChecker.feature_enabled?() do
      check_role(conn)
    else
      conn
    end
  end

  defp check_role(conn) do
    roles_verified_at = get_session(conn, :roles_verified_at)
    recheck_interval = Application.get_env(:soundboard, :role_recheck_interval_seconds, 900)

    if fresh?(roles_verified_at, recheck_interval) do
      conn
    else
      discord_id = conn.assigns.current_user.discord_id

      if RoleChecker.authorized?(discord_id) do
        put_session(conn, :roles_verified_at, System.system_time(:second))
      else
        conn
        |> clear_session()
        |> put_flash(:error, "Your role access has been revoked")
        |> redirect(to: "/")
        |> halt()
      end
    end
  end

  defp fresh?(nil, _interval), do: false

  defp fresh?(verified_at, interval) when is_integer(verified_at) do
    System.system_time(:second) - verified_at < interval
  end
end
