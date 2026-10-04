defmodule SoundboardWeb.OnboardingController do
  @moduledoc """
  The onboarding handoff for hosted signups. A signed-in user invites the
  shared bot from here, then continues to `/guilds` where switching
  provisions the tenant.
  """

  use SoundboardWeb, :controller

  alias Soundboard.Discord.InviteURL

  def show(conn, _params) do
    conn
    |> assign(:current_path, conn.request_path)
    |> render(:show, invite_url: InviteURL.build())
  end
end
