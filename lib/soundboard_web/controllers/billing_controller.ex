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

    render(conn, :billing,
      tiers: Billing.tiers(),
      plan_label: Billing.plan_label(guild && guild.max_storage_bytes),
      storage_used: Billing.format_bytes(Tenants.storage_used(guild_id)),
      storage_cap: Billing.format_bytes(guild.max_storage_bytes || 0),
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
    guild_id =
      get_session(conn, :billing_guild_id) ||
        conn.assigns.current_guild_id

    case Billing.create_checkout_session(guild_id, price_id) do
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

  def checkout(conn, _params) do
    conn
    |> put_flash(:error, "Pick a plan first")
    |> redirect(to: "/billing")
  end

  @doc "Opens the Stripe customer portal for the session's guild."
  def portal(conn, _params) do
    case Billing.create_portal_session(conn.assigns.current_guild_id) do
      {:ok, %{url: url}} when is_binary(url) ->
        redirect(conn, external: url)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not open billing portal: #{inspect(reason)}")
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
end
