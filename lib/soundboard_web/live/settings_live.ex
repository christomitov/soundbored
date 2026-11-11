defmodule SoundboardWeb.SettingsLive do
  @moduledoc """
  API tokens and their docs, and, on hosted deployments, the guild's plan:
  shown only when billing is configured and the signed-in user is the
  Discord account that provisioned the guild.
  """
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  alias Soundboard.{Accounts.ApiTokens, Billing, PublicURL, Tenants}

  @impl true
  def mount(_params, session, socket) do
    user = get_user_from_session(session)

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/settings")
      |> assign(:current_user, user)
      |> assign(:tokens, [])
      |> assign(:new_token, nil)
      |> assign(:base_url, PublicURL.current())
      |> assign(:billing, plan_card(user, session))

    {:ok, load_tokens(socket)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :base_url, PublicURL.from_uri_or_current(uri))}
  end

  @impl true
  def handle_event(
        "create_token",
        %{"label" => label},
        %{assigns: %{current_user: user}} = socket
      ) do
    case ApiTokens.generate_token(user, %{label: String.trim(label)}) do
      {:ok, raw, _token} ->
        {:noreply,
         socket
         |> assign(:new_token, raw)
         |> load_tokens()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create token")}
    end
  end

  @impl true
  def handle_event("revoke_token", %{"id" => id}, %{assigns: %{current_user: user}} = socket) do
    case ApiTokens.revoke_token(user, id) do
      {:ok, _} -> {:noreply, socket |> load_tokens() |> put_flash(:info, "Token revoked")}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, "Not allowed")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Token not found")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to revoke token")}
    end
  end

  defp plan_card(user, session) do
    guild = Tenants.get_guild(session["guild_id"])

    owner? =
      Billing.configured?() and guild != nil and is_binary(guild.owner_discord_id) and
        user != nil and guild.owner_discord_id == user.discord_id

    if owner? do
      used = Tenants.storage_used(guild.discord_guild_id)
      cap = guild.max_storage_bytes || 0

      %{
        plan_label: Billing.plan_label(guild.max_storage_bytes),
        storage_used: Billing.format_bytes(used),
        storage_cap: Billing.format_bytes(cap),
        usage_pct: if(cap > 0, do: min(100, div(used * 100, cap)), else: 0)
      }
    else
      nil
    end
  end

  defp load_tokens(%{assigns: %{current_user: nil}} = socket), do: socket

  defp load_tokens(%{assigns: %{current_user: user}} = socket) do
    tokens = ApiTokens.list_tokens(user)

    socket
    |> assign(:tokens, tokens)
    |> assign(:example_token, socket.assigns[:new_token])
  end

  defp format_dt(nil), do: nil
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
