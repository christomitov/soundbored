defmodule SoundboardWeb.Plugs.RoleCheck do
  @moduledoc false
  require Logger
  import Plug.Conn
  import Phoenix.Controller

  alias Soundboard.Discord.RoleChecker

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      is_nil(conn.assigns[:current_user]) -> conn
      not RoleChecker.feature_enabled?() -> conn
      true -> check_role(conn)
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
        Logger.warning("Role check failed for Discord user #{discord_id}, clearing session")

        conn
        |> clear_session()
        |> put_flash(:error, "Error signing in")
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
