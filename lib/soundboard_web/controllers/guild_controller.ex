defmodule SoundboardWeb.GuildController do
  @moduledoc """
  Tenant onboarding: list the guilds the shared bot is a member of and let the
  signed-in user switch their active soundboard (creating the tenant row on
  first use — that is the whole "provisioning" step).
  """

  use SoundboardWeb, :controller

  alias Soundboard.{Discord.GuildCache, Tenants}

  def index(conn, _params) do
    render(conn, :index,
      bot_guilds: Tenants.bot_guilds(),
      current_guild_id: conn.assigns.current_guild_id
    )
  end

  def switch(conn, %{"discord_guild_id" => discord_guild_id}) do
    with {:ok, _discord_guild} <- GuildCache.get(discord_guild_id),
         {:ok, _tenant} <- Tenants.get_or_create_guild(discord_guild_id) do
      conn
      |> put_session(:guild_id, to_string(discord_guild_id))
      |> put_flash(:info, "Switched soundboard")
      |> redirect(to: "/")
    else
      :error ->
        conn
        |> put_flash(:error, "Bot is not a member of that guild")
        |> redirect(to: "/guilds")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Could not provision soundboard: #{inspect(changeset.errors)}")
        |> redirect(to: "/guilds")
    end
  end
end
