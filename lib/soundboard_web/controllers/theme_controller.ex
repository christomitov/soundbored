defmodule SoundboardWeb.ThemeController do
  use SoundboardWeb, :controller

  alias Soundboard.Theme

  def update(conn, %{"theme" => theme} = params) do
    theme = Theme.normalize(theme)
    return_to = safe_return_to(params["return_to"])

    conn
    |> put_session(:theme, theme)
    |> put_resp_cookie("sb_theme", theme,
      max_age: 60 * 60 * 24 * 365,
      same_site: "Lax",
      http_only: false,
      path: "/"
    )
    |> redirect(to: return_to)
  end

  def update(conn, params) do
    update(conn, Map.put(params, "theme", Theme.default()))
  end

  defp safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path
    else
      ~p"/settings"
    end
  end

  defp safe_return_to(_), do: ~p"/settings"
end
