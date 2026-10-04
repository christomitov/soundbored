defmodule Soundboard.Billing do
  @moduledoc """
  Stripe-backed storage subscriptions for guild tenants.

  Dormancy: billing is dormant unless `STRIPE_SECRET_KEY` is set. Everything in
  this module gates on `configured?/0`; when Stripe is unconfigured the app
  behaves exactly as it did before billing existed (provisioning happens on
  guild switch, every tenant gets the platform default storage cap).

  Plan catalog (price ids come from env, see `config/runtime.exs`):

  | Tier   | Cap    | Monthly | Yearly |
  |--------|--------|---------|--------|
  | Pro    | 25 GB  | $4      | $36    |
  | Studio | 100 GB | $10     | $96    |

  The price-id -> cap mapping lives here (`plan_cap/1`) and is the single
  source of truth; the webhook is the only hosted provisioning path (it
  provisions the tenant row via `Tenants.get_or_create_guild/2` and writes
  `max_storage_bytes`), so a guild can never get a paid cap without a Stripe
  payment event.

  ## Idempotency

  Stripe retries webhook deliveries until they are acked, so events must be
  processed at most once. Processed event ids are remembered in a public ETS
  table (`:billing_processed_events`). Tradeoff: ETS is in-memory, so a node
  restart forgets the set and Stripe retries arriving across a restart could
  replay an event. That is safe here because every handler is an absolute
  write (set the cap to the plan's cap, not an increment), so replays are
  no-ops; the ETS set just avoids redundant work in the common case.

  Stripe customer ids seen on events are kept in a second ETS table
  (`:billing_stripe_customers`) so the customer portal can be opened without
  a `stripe_customer_id` column on `guilds`. Also in-memory: after a restart
  the portal is unavailable until the next event repopulates it.
  """

  alias Soundboard.Repo
  alias Soundboard.Tenants
  alias Soundboard.Tenants.Guild
  require Logger

  @events_ets :billing_processed_events
  @customers_ets :billing_stripe_customers
  @signature_tolerance_seconds 300

  @cap_by_tier %{pro: 26_843_545_600, studio: 107_374_182_400}

  # -- Configuration ----------------------------------------------------------

  @doc """
  Billing configuration (set in `config/runtime.exs` from STRIPE_* env vars).
  """
  def config, do: Application.get_env(:soundboard, __MODULE__, [])

  defp cfg(key), do: Keyword.get(config(), key)

  defp present?(value), do: is_binary(value) and value != ""

  @doc "Whether Stripe billing is active (STRIPE_SECRET_KEY present)."
  def configured?, do: present?(cfg(:secret_key))

  @doc "Whether webhook signature verification is possible."
  def webhook_configured?, do: present?(cfg(:webhook_secret))

  @doc """
  Maps every configured Stripe price id to its storage cap in bytes. This is
  the single source of truth for the price -> plan mapping.
  """
  @spec price_cap_map() :: %{String.t() => pos_integer()}
  def price_cap_map do
    [
      {cfg(:price_pro_monthly), @cap_by_tier.pro},
      {cfg(:price_pro_yearly), @cap_by_tier.pro},
      {cfg(:price_studio_monthly), @cap_by_tier.studio},
      {cfg(:price_studio_yearly), @cap_by_tier.studio}
    ]
    |> Enum.reject(fn {price_id, _cap} -> not present?(price_id) end)
    |> Map.new()
  end

  @doc "The storage cap in bytes for a Stripe price id, or nil when unknown."
  @spec plan_cap(String.t() | nil) :: non_neg_integer() | nil
  def plan_cap(price_id) when is_binary(price_id), do: Map.get(price_cap_map(), price_id)
  def plan_cap(_), do: nil

  @doc "Whether the price id belongs to the configured plan catalog."
  def valid_price?(price_id), do: plan_cap(price_id) != nil

  @doc "Plan catalog entries for display (name, cap, amounts, configured price ids)."
  def tiers do
    [
      %{
        name: "Pro",
        cap_bytes: @cap_by_tier.pro,
        monthly_amount_cents: 400,
        yearly_amount_cents: 3600,
        price_ids: %{
          monthly: cfg(:price_pro_monthly),
          yearly: cfg(:price_pro_yearly)
        }
      },
      %{
        name: "Studio",
        cap_bytes: @cap_by_tier.studio,
        monthly_amount_cents: 1000,
        yearly_amount_cents: 9600,
        price_ids: %{
          monthly: cfg(:price_studio_monthly),
          yearly: cfg(:price_studio_yearly)
        }
      }
    ]
  end

  @doc "The plan a storage cap belongs to: :studio, :pro, :free, or nil."
  @spec plan_for_cap(non_neg_integer() | nil) :: :studio | :pro | :free | nil
  def plan_for_cap(nil), do: nil
  def plan_for_cap(cap) when cap >= @cap_by_tier.studio, do: :studio
  def plan_for_cap(cap) when cap >= @cap_by_tier.pro, do: :pro
  def plan_for_cap(_), do: :free

  @doc "Human plan name for a cap value."
  @spec plan_label(non_neg_integer() | nil) :: String.t()
  def plan_label(nil), do: "Free"
  def plan_label(0), do: "Free"
  def plan_label(cap), do: plan_for_cap(cap) |> to_string() |> String.capitalize()

  @doc "Bytes formatted for display, e.g. \"1.2 GB\"."
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1) |> trim_float()} GB"
  end

  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_048_576,
    do: "#{div(bytes, 1_048_576)} MB"

  def format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"

  defp trim_float(float) do
    :erlang.float_to_binary(float, decimals: 1) |> String.replace_suffix(".0", "")
  end

  # -- Subscription state -----------------------------------------------------

  @doc """
  Whether a guild has an active subscription: an existing tenant row with a
  positive storage cap. A row with cap 0 (subscription deleted) or no row at
  all counts as unpaid. Rows that predate billing keep their default cap and
  therefore count as active — existing deployments are never locked out.
  """
  @spec subscription_active?(String.t() | term()) :: boolean()
  def subscription_active?(guild_id) do
    case Tenants.get_guild(guild_id) do
      %Guild{max_storage_bytes: bytes} -> is_integer(bytes) and bytes > 0
      nil -> false
    end
  end

  # -- Checkout / portal ------------------------------------------------------

  @doc """
  Creates a Stripe Checkout Session for `guild_id` at `price_id`.

  The session carries the guild id in `client_reference_id` (Stripe's
  reconciliation key) and in metadata (read back by the webhook). The price id
  is also mirrored into metadata because checkout session payloads do not
  include line items unless they are expanded.

  Returns `{:ok, %{id: id, url: url}}` or `{:error, :not_configured |
  :invalid_price | term()}`.
  """
  @spec create_checkout_session(String.t() | term(), String.t()) ::
          {:ok, %{id: String.t(), url: String.t() | nil}} | {:error, term()}
  def create_checkout_session(guild_id, price_id) do
    guild_id = to_string(guild_id)

    cond do
      not configured?() ->
        {:error, :not_configured}

      not valid_price?(price_id) ->
        {:error, :invalid_price}

      true ->
        base = base_url()

        case Stripe.Checkout.Session.create(%{
               mode: "subscription",
               client_reference_id: guild_id,
               success_url: base <> "/guilds",
               cancel_url: base <> "/guilds",
               line_items: [%{price: price_id, quantity: 1}],
               metadata: %{"guild_id" => guild_id, "price_id" => price_id},
               subscription_data: %{
                 metadata: %{"guild_id" => guild_id, "price_id" => price_id}
               }
             }) do
          {:ok, session} -> {:ok, %{id: session.id, url: session.url}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Creates a Stripe customer portal session for the guild's customer. Requires
  the guild to have a customer id already seen on a billing webhook event
  (kept in-memory; see the module doc).
  """
  @spec create_portal_session(String.t() | term()) ::
          {:ok, %{url: String.t()}} | {:error, :not_configured | :no_customer | term()}
  def create_portal_session(guild_id) do
    if configured?() do
      case customer_id_for_guild(guild_id) do
        nil ->
          {:error, :no_customer}

        customer_id ->
          case Stripe.BillingPortal.Session.create(%{
                 customer: customer_id,
                 return_url: base_url() <> "/guilds"
               }) do
            {:ok, session} -> {:ok, %{url: session.url}}
            {:error, reason} -> {:error, reason}
          end
      end
    else
      {:error, :not_configured}
    end
  end

  @doc "The Stripe customer id last seen for a guild, or nil."
  @spec customer_id_for_guild(String.t() | term()) :: String.t() | nil
  def customer_id_for_guild(guild_id) do
    ensure_ets(@customers_ets)

    case :ets.lookup(@customers_ets, to_string(guild_id)) do
      [{_guild_id, customer_id}] -> customer_id
      [] -> nil
    end
  end

  defp remember_customer(guild_id, customer_id)
       when is_binary(guild_id) and is_binary(customer_id) do
    ensure_ets(@customers_ets)
    :ets.insert(@customers_ets, {guild_id, customer_id})
  end

  defp remember_customer(_, _), do: :ok

  # -- Webhooks ---------------------------------------------------------------

  @doc """
  Verifies the Stripe signature header, then dispatches the event.

  Returns `{:ok, event_id | :duplicate}` on success (both ack the delivery),
  `{:error, :invalid_signature}` for tampered/foreign payloads, or
  `{:error, term()}` for malformed payloads / handler failures.
  """
  @spec handle_webhook(binary(), String.t() | nil) ::
          {:ok, String.t() | :duplicate} | {:error, term()}
  def handle_webhook(payload, signature_header) when is_binary(payload) do
    with :ok <- verify_webhook_signature(payload, signature_header),
         {:ok, event} <- Jason.decode(payload),
         :ok <- ensure_not_processed(event["id"]) do
      case handle_event(event) do
        :ok ->
          remember_event(event["id"])
          {:ok, event["id"]}

        {:error, reason} = error ->
          Logger.error("Billing webhook #{event["id"]} failed: #{inspect(reason)}")
          error
      end
    else
      {:error, :already_processed} ->
        {:ok, :duplicate}

      {:error, reason} = error ->
        Logger.warning("Billing webhook rejected: #{inspect(reason)}")
        error
    end
  end

  def handle_webhook(_, _), do: {:error, :invalid_payload}

  @doc """
  Verifies a Stripe webhook signature header (`t=...,v1=...`) against
  `payload` using HMAC-SHA256. Verified locally instead of via
  `Stripe.Webhook.construct_event/3` so the boundary is testable without
  network or Stripe SDK behavior drift.
  """
  @spec verify_webhook_signature(binary(), String.t() | nil, String.t() | nil, pos_integer()) ::
          :ok | {:error, :invalid_signature | :not_configured}
  def verify_webhook_signature(
        payload,
        signature_header,
        secret \\ nil,
        tolerance \\ @signature_tolerance_seconds
      )

  def verify_webhook_signature(payload, signature_header, nil, tolerance) do
    verify_webhook_signature(payload, signature_header, cfg(:webhook_secret), tolerance)
  end

  def verify_webhook_signature(payload, signature_header, secret, tolerance) do
    if not present?(secret) do
      {:error, :not_configured}
    else
      case parse_signature_header(signature_header) do
        {timestamp, v1_values} ->
          expected =
            :crypto.mac(:hmac, :sha256, secret, timestamp <> "." <> payload)
            |> Base.encode16(case: :lower)

          timestamp_fresh? = fresh_timestamp?(timestamp, tolerance)
          signature_match? = Enum.any?(v1_values, &secure_equals?(&1, expected))

          if timestamp_fresh? and signature_match?,
            do: :ok,
            else: {:error, :invalid_signature}

        :error ->
          {:error, :invalid_signature}
      end
    end
  end

  defp parse_signature_header(header) when is_binary(header) do
    parts =
      header
      |> String.split(",", trim: true)
      |> Enum.map(fn pair ->
        case String.split(pair, "=", parts: 2) do
          [k, v] -> {String.trim(k), String.trim(v)}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    timestamp = Enum.find_value(parts, fn {k, v} -> k == "t" && v end)
    v1_values = for {"v1", v} <- parts, do: v

    if is_binary(timestamp) and v1_values != [] do
      {timestamp, v1_values}
    else
      :error
    end
  end

  defp parse_signature_header(_), do: :error

  defp fresh_timestamp?(timestamp, tolerance) do
    case Integer.parse(timestamp) do
      {ts, ""} -> abs(System.system_time(:second) - ts) <= tolerance
      _ -> false
    end
  end

  defp secure_equals?(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_equals?(_, _), do: false

  # -- Event handling ---------------------------------------------------------

  @doc "Handles a decoded Stripe event map. Public for direct unit testing."
  @spec handle_event(map()) :: :ok | {:error, term()}
  def handle_event(%{"type" => type, "data" => %{"object" => object}}) do
    case type do
      "checkout.session.completed" -> handle_checkout_completed(object)
      "customer.subscription.updated" -> handle_subscription_updated(object)
      "customer.subscription.deleted" -> handle_subscription_deleted(object)
      _other -> :ok
    end
  end

  def handle_event(_), do: :ok

  # The webhook is the only hosted provisioning path: it creates the tenant
  # row (if the guild never switched) and writes the plan cap.
  defp handle_checkout_completed(session) do
    guild_id =
      get_in(session, ["metadata", "guild_id"]) ||
        get_in(session, ["subscription_data", "metadata", "guild_id"]) ||
        session["client_reference_id"]

    price_id = get_in(session, ["metadata", "price_id"])
    cap = plan_cap(price_id) || 0

    remember_customer(guild_id, session["customer"])
    apply_cap(guild_id, cap)
  end

  defp handle_subscription_updated(subscription) do
    guild_id = get_in(subscription, ["metadata", "guild_id"])
    price_id = subscription_price_id(subscription)
    cap = plan_cap(price_id)

    if is_binary(guild_id) and cap do
      apply_cap(guild_id, cap)
    else
      Logger.warning("customer.subscription.updated without guild/price metadata; ignored")
      :ok
    end
  end

  defp handle_subscription_deleted(subscription) do
    guild_id = get_in(subscription, ["metadata", "guild_id"])

    if is_binary(guild_id) do
      apply_cap(guild_id, 0)
    else
      Logger.warning("customer.subscription.deleted without guild metadata; ignored")
      :ok
    end
  end

  defp subscription_price_id(subscription) do
    get_in(subscription, ["items", "data"])
    |> List.wrap()
    |> List.first()
    |> case do
      %{"price" => %{"id" => price_id}} -> price_id
      _ -> nil
    end
  end

  # Idempotent by construction: writing the absolute cap (never an increment)
  # means replayed events converge to the same state even if the ETS set was
  # lost across a restart.
  defp apply_cap(guild_id, cap) when is_binary(guild_id) do
    case Tenants.get_or_create_guild(guild_id) do
      {:ok, %Guild{max_storage_bytes: ^cap}} ->
        :ok

      {:ok, guild} ->
        case guild |> Guild.changeset(%{max_storage_bytes: cap}) |> Repo.update() do
          {:ok, _guild} -> :ok
          {:error, changeset} -> {:error, {:cap_update_failed, inspect(changeset.errors)}}
        end

      {:error, reason} ->
        {:error, {:provision_failed, inspect(reason)}}
    end
  end

  defp apply_cap(_, _), do: :ok

  # -- ETS bookkeeping --------------------------------------------------------

  defp ensure_not_processed(event_id) when is_binary(event_id) do
    ensure_ets(@events_ets)

    if :ets.member(@events_ets, event_id) do
      {:error, :already_processed}
    else
      :ok
    end
  end

  defp ensure_not_processed(_), do: :ok

  defp remember_event(event_id) when is_binary(event_id) do
    ensure_ets(@events_ets)
    :ets.insert(@events_ets, {event_id, System.system_time(:second)})
  end

  defp remember_event(_), do: :ok

  defp ensure_ets(table) do
    if :ets.whereis(table) == :undefined do
      # Race-safe: another process may have created the table since the check.
      try do
        :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  @doc """
  Clears in-memory billing state (processed events, customer ids). Test and
  ops helper; production state is intentionally reconstructible (see the
  module doc on idempotency).
  """
  def reset_memory do
    for table <- [@events_ets, @customers_ets] do
      ensure_ets(table)
      :ets.delete_all_objects(table)
    end

    :ok
  end

  # -- Helpers ----------------------------------------------------------------

  defp base_url, do: SoundboardWeb.Endpoint.url()
end
