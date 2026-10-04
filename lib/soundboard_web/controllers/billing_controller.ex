defmodule SoundboardWeb.BillingController do
  @moduledoc """
  Stripe subscriptions: plan options, checkout, customer portal, and the
  public webhook receiver (signature-verified, no session auth).

  Checkout/portal delegate to `Soundboard.Billing` so tests can stub at that
  seam instead of Stripe internals.
  """

  use SoundboardWeb, :controller

  alias Soundboard.Billing
  alias Soundboard.Tenants

  def index(conn, _params) do
    guild_id = conn.assigns.current_guild_id
    guild = Tenants.get_guild(guild_id)

    current_tier = guild && Billing.plan_for_cap(guild.max_storage_bytes)
    has_subscription = Billing.known_subscription?(guild_id)

    current_interval =
      if has_subscription,
        do: Billing.interval_for_price(Billing.current_price_id_for_guild(guild_id))

    render(conn, :billing,
      tiers: Billing.tiers(),
      current_tier: current_tier,
      has_subscription: has_subscription,
      current_interval: current_interval,
      plan_label: Billing.plan_label(guild && guild.max_storage_bytes),
      storage_used: Billing.format_bytes(Tenants.storage_used(guild_id)),
      storage_cap: Billing.format_bytes((guild && guild.max_storage_bytes) || 0),
      has_customer: Billing.customer_id_for_guild(guild_id) != nil
    )
  end

  @doc """
  Starts Stripe Checkout. The guild id comes from the session's pending
  billing guild (set when a switch to an unpaid guild was gated) or the
  session's current guild; `Billing` puts it into `client_reference_id` and
  metadata so the webhook can provision the right tenant.
  """
  def checkout(conn, %{"price_id" => price_id}) do
    case pending_or_current_guild_id(conn) do
      nil -> no_guild_selected(conn)
      guild_id -> start_checkout(conn, guild_id, price_id)
    end
  end

  def checkout(conn, _params) do
    conn
    |> put_flash(:error, "Pick a plan first")
    |> redirect(to: "/billing")
  end

  defp pending_or_current_guild_id(conn) do
    case get_session(conn, :billing_guild_id) || conn.assigns.current_guild_id do
      id when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  defp start_checkout(conn, guild_id, price_id) do
    owner = conn.assigns.current_user && conn.assigns.current_user.discord_id

    case Billing.create_checkout_session(guild_id, price_id, owner, base_url: request_base(conn)) do
      {:ok, %{url: url}} when is_binary(url) ->
        conn
        |> delete_session(:billing_guild_id)
        |> redirect(external: url)

      {:ok, _session} ->
        conn
        |> put_flash(:error, "Checkout session did not return a URL")
        |> redirect(to: "/billing")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not start checkout: #{inspect(reason)}")
        |> redirect(to: "/billing")
    end
  end

  defp no_guild_selected(conn) do
    conn
    |> put_flash(:error, "Pick a soundboard first")
    |> redirect(to: "/guilds")
    |> halt()
  end

  @doc "Opens the Stripe customer portal for the session's guild."
  def portal(conn, _params) do
    case Billing.create_portal_session(conn.assigns.current_guild_id,
           base_url: request_base(conn)
         ) do
      {:ok, %{url: url}} when is_binary(url) ->
        redirect(conn, external: url)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not open billing portal: #{inspect(reason)}")
        |> redirect(to: "/billing")
    end
  end

  @doc "Switches the session guild's subscription to another price (tier or interval)."
  def change(conn, %{"price_id" => price_id}) do
    case Billing.change_subscription_price(conn.assigns.current_guild_id, price_id) do
      {:ok, :updated} ->
        conn
        |> put_flash(
          :info,
          "Your plan has been updated. The change is prorated on your next invoice."
        )
        |> redirect(to: "/billing")

      {:error, :no_subscription} ->
        conn
        |> put_flash(:error, "No active subscription found to change — try subscribing again")
        |> redirect(to: "/billing")

      {:error, :invalid_price} ->
        conn
        |> put_flash(:error, "Pick a plan first")
        |> redirect(to: "/billing")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not change plan: #{inspect(reason)}")
        |> redirect(to: "/billing")
    end
  end

  def change(conn, _params) do
    conn
    |> put_flash(:error, "Pick a plan first")
    |> redirect(to: "/billing")
  end

  @doc "Cancels the session guild's subscription at period end."
  def cancel(conn, _params) do
    case Billing.cancel_subscription(conn.assigns.current_guild_id) do
      {:ok, %{cancel_at: ts}} when is_integer(ts) ->
        date = ts |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_iso8601()

        conn
        |> put_flash(
          :info,
          "Your subscription will end on #{date}. You keep your plan until then."
        )
        |> redirect(to: "/billing")

      {:ok, _} ->
        redirect(conn, to: "/billing")

      {:error, :no_subscription} ->
        conn
        |> put_flash(:error, "No active subscription found to cancel")
        |> redirect(to: "/billing")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not cancel subscription: #{inspect(reason)}")
        |> redirect(to: "/billing")
    end
  end

  @doc """
  Public Stripe webhook receiver. No session auth — the Stripe signature
  header is the credential. Bad signatures and malformed payloads get a 400;
  duplicates get a 200 so Stripe stops retrying.
  """
  def webhook(conn, _params) do
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case Billing.handle_webhook(raw_body(conn), signature) do
      {:ok, result} ->
        conn |> json(%{received: true, event: result})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  # Phoenix stores the untouched body in :raw_body when a JSON body parser
  # runs; fall back to a manual read otherwise. The signature is computed over
  # the raw bytes, so this must never see re-encoded JSON.
  defp raw_body(conn) do
    case conn.assigns[:raw_body] do
      [body | _] ->
        body

      _ ->
        case Plug.Conn.read_body(conn) do
          {:ok, body, _conn} -> body
          _ -> ""
        end
    end
  end

  # scheme://host[:port] from the incoming request, no path/query.
  defp request_base(conn) do
    %{scheme: scheme, host: host, port: port} = conn
    default = if scheme == :https, do: 443, else: 80

    if port == default do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
