defmodule SoundboardWeb.GuildController do
  @moduledoc """
  Tenant onboarding: list the guilds the shared bot is a member of and let the
  signed-in user switch their active soundboard (creating the tenant row on
  first use — that is the whole "provisioning" step).
  """

  use SoundboardWeb, :controller

  alias Soundboard.{Billing, Discord.GuildCache, Tenants}

  def index(conn, _params) do
    current_guild = Tenants.get_guild(conn.assigns.current_guild_id)

    render(conn, :index,
      bot_guilds: Tenants.bot_guilds(),
      current_guild_id: conn.assigns.current_guild_id,
      current_guild: current_guild,
      stripe_configured: Billing.configured?(),
      plan_label: Billing.plan_label(current_guild && current_guild.max_storage_bytes),
      storage_used: Billing.format_bytes(Tenants.storage_used(conn.assigns.current_guild_id)),
      storage_cap: Billing.format_bytes((current_guild && current_guild.max_storage_bytes) || 0)
    )
  end

  def switch(conn, %{"discord_guild_id" => discord_guild_id}) do
    if Billing.configured?() and not Billing.subscription_active?(discord_guild_id) do
      # Paywall: the guild has no active subscription. Remember the intended
      # guild so checkout can provision it (the webhook is the only hosted
      # provisioning path); no tenant row is created here.
      conn
      |> put_session(:billing_guild_id, to_string(discord_guild_id))
      |> put_flash(:info, "That soundboard needs a subscription - pick a plan")
      |> redirect(to: "/billing")
    else
      do_switch(conn, discord_guild_id)
    end
  end

  defp do_switch(conn, discord_guild_id) do
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

  @doc """
  Claims a slug (subdomain name) for the session's current guild.

  Availability is pre-checked with `Tenants.slug_available?/1` for a clean
  error path; reserved/duplicate slugs are rejected authoritatively inside
  `Tenants.claim_slug/2`.
  """
  def claim(conn, %{"slug" => slug}) do
    guild_id = conn.assigns.current_guild_id
    current_guild = Tenants.get_guild(guild_id)
    normalized = slug |> String.trim() |> String.downcase()

    cond do
      # Re-submitting the current slug is a no-op, not a duplicate.
      current_guild && current_guild.slug == normalized ->
        already_claimed(conn, normalized)

      Tenants.slug_available?(slug) ->
        case Tenants.claim_slug(guild_id, slug) do
          {:ok, guild} ->
            conn
            |> put_flash(
              :info,
              "Claimed! Your soundboard is now at https://app.soundbored.app/g/#{guild.slug}"
            )
            |> redirect(to: "/guilds")

          {:error, _reason} ->
            unavailable(conn)
        end

      true ->
        unavailable(conn)
    end
  end

  def claim(conn, _params), do: unavailable(conn)

  @doc """
  Scopes the app to the tenant resolved by slug. Resolution never creates a
  row: an unknown slug is a 404. Setting the session `:guild_id` is what makes
  the Tenant plug (and LiveViews on subsequent requests) pick the guild up.
  """
  def show(conn, %{"slug" => slug}) do
    case Tenants.get_by_slug(slug) do
      %Tenants.Guild{} = guild ->
        conn
        |> put_session(:guild_id, guild.discord_guild_id)
        |> put_flash(:info, "Now viewing the \"#{slug}\" soundboard")
        |> redirect(to: "/")

      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(SoundboardWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  defp already_claimed(conn, slug) do
    conn
    |> put_flash(:info, "Already claimed: https://app.soundbored.app/g/#{slug}")
    |> redirect(to: "/guilds")
  end

  defp unavailable(conn) do
    conn
    |> put_flash(:error, "That subdomain is not available")
    |> redirect(to: "/guilds")
  end
end
