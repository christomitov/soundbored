defmodule SoundboardWeb.OnboardingTest do
  @moduledoc """
  Web tests for the onboarding handoff: signed-out visitors are sent to
  Discord auth, and a signed-in user sees the shared bot's invite link (with
  the pinned permission integer and scope) plus the continue path to /guilds.
  """

  use SoundboardWeb.ConnCase, async: false

  alias Soundboard.Accounts.User
  alias Soundboard.Repo

  @client_id "987654321098765432"

  setup do
    on_exit(fn ->
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth)
    end)

    :ok
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{discord_id: "discord-onboarding", username: "onboarder"})
    |> Repo.insert!()
  end

  test "a signed-out visit to /onboarding redirects to Discord auth", %{conn: conn} do
    conn = conn |> init_test_session(%{}) |> get("/onboarding")

    assert redirected_to(conn) == "/auth/discord"
  end

  test "a signed-in user gets the invite link for the configured client id", %{conn: conn} do
    Application.put_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth,
      client_id: @client_id,
      redirect_uri: "http://localhost:4000/auth/discord/callback"
    )

    user = insert_user!()

    html =
      conn
      |> init_test_session(%{user_id: user.id})
      |> get("/onboarding")
      |> response(200)

    assert html =~ "discord.com/oauth2/authorize"
    assert html =~ "client_id=#{@client_id}"
    assert html =~ "permissions=1049608"
    assert html =~ "scope=bot%20applications.commands"
    assert html =~ "Continue"
    assert html =~ "/guilds"
  end
end
