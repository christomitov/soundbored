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
  | Pro    | 1 GB   | $4      | $36    |
  | Studio | 5 GB   | $10     | $96    |

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

  defmodule SubscriptionSnapshot do
    @moduledoc """
    The guild's live Stripe subscription state cached in memory between
    webhooks: the subscription id, its line item id, and the price id.
    """

    defstruct [:id, :item_id, :price_id]

    @type t :: %__MODULE__{
            id: String.t(),
            item_id: String.t() | nil,
            price_id: String.t() | nil
          }
  end

  @events_ets :billing_processed_events
  @customers_ets :billing_stripe_customers
  @subscriptions_ets :billing_stripe_subscriptions
  @signature_tolerance_seconds 300

  @cap_by_tier %{pro: 1_073_741_824, studio: 5_368_709_120}

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
        tagline: "For one Discord server",
        features: [
          "1 GB of sound storage",
          "Unlimited sounds and uploads",
          "Join & leave sounds",
          "Shareable soundboard URL"
        ],
        cap_bytes: @cap_by_tier.pro,
        monthly_amount_cents: 399,
        yearly_amount_cents: 3599,
        price_ids: %{
          monthly: cfg(:price_pro_monthly),
          yearly: cfg(:price_pro_yearly)
        }
      },
      %{
        name: "Studio",
        tagline: "For one Discord server",
        features: [
          "5 GB of sound storage",
          "Everything in Pro",
          "Priority support",
          "Early access to new features"
        ],
        cap_bytes: @cap_by_tier.studio,
        monthly_amount_cents: 999,
        yearly_amount_cents: 9599,
        price_ids: %{
          monthly: cfg(:price_studio_monthly),
          yearly: cfg(:price_studio_yearly)
        }
      }
    ]
  end

  @doc "Cents to a display price like \"$3.99\"."
  @spec format_price(pos_integer()) :: String.t()
  def format_price(cents) when is_integer(cents) do
    "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  @doc "The plan a storage cap belongs to: :studio, :pro, or nil."
  @spec plan_for_cap(non_neg_integer() | nil) :: :studio | :pro | nil
  def plan_for_cap(nil), do: nil
  def plan_for_cap(cap) when cap == @cap_by_tier.studio, do: :studio
  def plan_for_cap(cap) when cap == @cap_by_tier.pro, do: :pro
  # Caps that don't match a plan exactly are legacy/self-hosted rows — the
  # webhook only ever writes exact plan caps.
  def plan_for_cap(_), do: nil

  @doc "Human plan name for a cap value."
  @spec plan_label(non_neg_integer() | nil) :: String.t()
  def plan_label(nil), do: "No plan"
  def plan_label(0), do: "No plan"

  def plan_label(cap) do
    case plan_for_cap(cap) do
      nil -> "No plan"
      tier -> tier |> to_string() |> String.capitalize()
    end
  end

  @doc "Bytes formatted for display: MB up to 1000 MB, then GB."
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 100 * 1_048_576,
    do: "#{Float.round(bytes / 1_073_741_824, 1) |> trim_float()} GB"

  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1) |> trim_float()} MB"

  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_024,
    do: "#{Float.round(bytes / 1_024, 1) |> trim_float()} KB"

  def format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"

  defp trim_float(float) do
    :erlang.float_to_binary(float, decimals: 1) |> String.replace_suffix(".0", "")
  end

  # -- Subscription state -----------------------------------------------------

  @doc """
  Whether a guild has an active subscription: a tenant row whose storage cap
  exactly matches a paid plan (the webhook only writes exact plan caps).
  Rows with cap 0, legacy/default caps, or no row at all count as unpaid —
  on hosted there is no free tier; self-hosted never reaches this check
  because the paywall gate short-circuits when billing is dormant.
  """
  @spec subscription_active?(String.t() | term()) :: boolean()
  def subscription_active?(guild_id) do
    case Tenants.get_guild(guild_id) do
      %Guild{max_storage_bytes: bytes} -> plan_for_cap(bytes) != nil
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
  @spec create_checkout_session(String.t() | term(), String.t(), term(), keyword()) ::
          {:ok, %{id: String.t(), url: String.t() | nil}} | {:error, term()}
  def create_checkout_session(guild_id, price_id, owner_discord_id \\ nil, opts \\ []) do
    guild_id = to_string(guild_id)

    cond do
      not configured?() ->
        {:error, :not_configured}

      not valid_price?(price_id) ->
        {:error, :invalid_price}

      true ->
        # Redirect back to the host the user actually came in on; a configured
        # PHX_HOST can differ (proxies, local test domains).
        base = Keyword.get(opts, :base_url) || base_url()

        case Stripe.Checkout.Session.create(
               %{
                 mode: :subscription,
                 client_reference_id: guild_id,
                 success_url: base <> "/guilds",
                 cancel_url: base <> "/guilds",
                 line_items: [%{price: price_id, quantity: 1}],
                 metadata: %{
                   "guild_id" => guild_id,
                   "price_id" => price_id,
                   "owner_discord_id" => owner_discord_id
                 },
                 subscription_data: %{
                   metadata: %{
                     "guild_id" => guild_id,
                     "price_id" => price_id,
                     "owner_discord_id" => owner_discord_id
                   }
                 }
               },
               api_key: cfg(:secret_key)
             ) do
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
  @spec create_portal_session(String.t() | term(), keyword()) ::
          {:ok, %{url: String.t()}} | {:error, :not_configured | :no_customer | term()}
  def create_portal_session(guild_id, opts \\ []) do
    with {:configured, true} <- {:configured, configured?()},
         customer_id when is_binary(customer_id) <- customer_id_for_guild(guild_id),
         {:ok, session} <-
           Stripe.BillingPortal.Session.create(
             %{
               customer: customer_id,
               return_url: (Keyword.get(opts, :base_url) || base_url()) <> "/guilds"
             },
             api_key: cfg(:secret_key)
           ) do
      {:ok, %{url: session.url}}
    else
      {:configured, false} -> {:error, :not_configured}
      nil -> {:error, :no_customer}
      {:error, reason} -> {:error, reason}
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

  @doc """
  Whether the guild has a Stripe subscription we can act on. Falls back to a
  Stripe lookup by remembered customer when in-memory state is missing (e.g.
  after a restart, or events processed by older code).
  """
  @spec known_subscription?(String.t() | term()) :: boolean()
  def known_subscription?(guild_id) do
    case subscription_state_for_guild(guild_id) do
      %{id: id} when is_binary(id) ->
        true

      _ ->
        configured?() and match?({:ok, _}, resolve_subscription(guild_id))
    end
  end

  @doc "The price id last seen on the guild's subscription, or nil."
  @spec current_price_id_for_guild(String.t() | term()) :: String.t() | nil
  def current_price_id_for_guild(guild_id) do
    ensure_ets(@subscriptions_ets)

    case :ets.lookup(@subscriptions_ets, to_string(guild_id)) do
      [{_guild_id, %{price_id: price_id}}] when is_binary(price_id) ->
        price_id

      _ ->
        resolve_current_price_id(guild_id)
    end
  end

  defp resolve_current_price_id(guild_id) do
    if known_subscription?(guild_id) do
      case subscription_state_for_guild(guild_id) do
        %{price_id: price_id} when is_binary(price_id) -> price_id
        _ -> nil
      end
    else
      nil
    end
  end

  @doc "Maps a known plan price id to its billing interval (:monthly/:yearly), or nil."
  @spec interval_for_price(String.t() | nil) :: :monthly | :yearly | nil
  def interval_for_price(nil), do: nil

  def interval_for_price(price_id) do
    Enum.find_value(tiers(), fn tier ->
      cond do
        tier.price_ids.monthly == price_id -> :monthly
        tier.price_ids.yearly == price_id -> :yearly
        true -> nil
      end
    end)
  end

  @doc "The Stripe subscription id last seen for a guild, or nil."
  @spec subscription_id_for_guild(String.t() | term()) :: String.t() | nil
  def subscription_id_for_guild(guild_id) do
    case subscription_state_for_guild(guild_id) do
      nil -> nil
      state -> state.id
    end
  end

  defp subscription_state_for_guild(guild_id) do
    ensure_ets(@subscriptions_ets)

    case :ets.lookup(@subscriptions_ets, to_string(guild_id)) do
      [{_guild_id, state}] -> state
      [] -> nil
    end
  end

  @doc "Caches the guild's subscription state (id, item, price) in memory."
  @spec remember_subscription(String.t() | term(), SubscriptionSnapshot.t()) :: :ok
  def remember_subscription(guild_id, %SubscriptionSnapshot{} = state) when is_binary(guild_id) do
    ensure_ets(@subscriptions_ets)
    :ets.insert(@subscriptions_ets, {guild_id, state})
  end

  def remember_subscription(_, _), do: :ok

  @doc """
  Moves the guild's live subscription to another price (tier or interval
  change). Stripe prorates automatically; the subscription.updated webhook
  applies the new cap.
  """
  @spec change_subscription_price(String.t() | term(), String.t()) ::
          {:ok, :updated} | {:error, :not_configured | :no_subscription | :invalid_price | term()}
  def change_subscription_price(guild_id, price_id) do
    with {:configured, true} <- {:configured, configured?()},
         {:valid, true} <- {:valid, valid_price?(price_id)},
         {:ok, %{id: _sub_id, item_id: item_id}} <- resolve_subscription(guild_id),
         true <- is_binary(item_id),
         {:ok, _updated} <-
           Stripe.SubscriptionItem.update(
             item_id,
             %{price: price_id, proration_behavior: :create_prorations},
             api_key: cfg(:secret_key)
           ) do
      {:ok, :updated}
    else
      {:configured, false} -> {:error, :not_configured}
      {:valid, false} -> {:error, :invalid_price}
      false -> {:error, :no_subscription}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Flags the guild's subscription to cancel at the end of the current billing
  period (Stripe keeps it active until then; customer.subscription.deleted
  later reverts the guild to no plan).
  """
  @spec cancel_subscription(String.t() | term()) ::
          {:ok, %{cancel_at: non_neg_integer() | nil}}
          | {:error, :not_configured | :no_subscription | term()}
  def cancel_subscription(guild_id) do
    with {:configured, true} <- {:configured, configured?()},
         {:ok, %{id: subscription_id}} <- resolve_subscription(guild_id),
         {:ok, subscription} <-
           Stripe.Subscription.update(subscription_id, %{cancel_at_period_end: true},
             api_key: cfg(:secret_key)
           ) do
      {:ok, %{cancel_at: subscription["current_period_end"]}}
    else
      {:configured, false} -> {:error, :not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  # In-memory subscription state can be lost across restarts; recover the
  # subscription (and its item id) from Stripe using the remembered customer.
  # API results arrive as structs; webhook payloads as raw maps — read both.
  defp resolve_subscription(guild_id) do
    case subscription_state_for_guild(guild_id) do
      %SubscriptionSnapshot{id: id, item_id: item_id} = snapshot
      when is_binary(id) and is_binary(item_id) ->
        {:ok, snapshot}

      _ ->
        case customer_id_for_guild(guild_id) do
          customer_id when is_binary(customer_id) ->
            list_subscription(%{customer: customer_id, status: :active}, guild_id)

          # No customer remembered: find the subscription by its guild metadata.
          _ ->
            list_subscription(%{status: :active, limit: 100}, guild_id)
        end
    end
  end

  defp subscription_items(sub) do
    case field(sub, :items) do
      %Stripe.List{data: data} -> data
      %{"data" => data} -> data
      data when is_list(data) -> data
      _ -> []
    end
  end

  defp list_subscription(params, guild_id) do
    case Stripe.Subscription.list(params, api_key: cfg(:secret_key)) do
      {:ok, %Stripe.List{data: subs}} ->
        sub =
          Enum.find(subs, fn sub ->
            field(sub, :metadata) |> field(:guild_id) == to_string(guild_id) or
              field(sub, :customer) == customer_id_for_guild(guild_id)
          end)

        case sub do
          %{} = sub ->
            item = subscription_items(sub) |> List.first()
            item_id = item && field(item, :id)
            price_id = item && item |> field(:price) |> field(:id)

            snapshot = %SubscriptionSnapshot{
              id: field(sub, :id),
              item_id: item_id,
              price_id: price_id
            }

            remember_subscription(guild_id, snapshot)

            {:ok, %SubscriptionSnapshot{id: snapshot.id, item_id: item_id}}

          _ ->
            {:error, :no_subscription}
        end

      _ ->
        {:error, :no_subscription}
    end
  end

  # Reads a field from either a struct (atom keys) or a raw JSON map (string keys).
  defp field(obj, key) do
    cond do
      is_struct(obj) -> Map.get(obj, key)
      is_map(obj) -> Map.get(obj, Atom.to_string(key))
      true -> nil
    end
  end

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
    with {:secret, true} <- {:secret, present?(secret)},
         {timestamp, v1_values} when is_binary(timestamp) <-
           parse_signature_header(signature_header) do
      expected =
        :crypto.mac(:hmac, :sha256, secret, timestamp <> "." <> payload)
        |> Base.encode16(case: :lower)

      timestamp_fresh? = fresh_timestamp?(timestamp, tolerance)
      signature_match? = Enum.any?(v1_values, &secure_equals?(&1, expected))

      if timestamp_fresh? and signature_match?,
        do: :ok,
        else: {:error, :invalid_signature}
    else
      {:secret, false} -> {:error, :not_configured}
      _ -> {:error, :invalid_signature}
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
    owner = get_in(session, ["metadata", "owner_discord_id"])
    cap = plan_cap(price_id) || 0

    remember_customer(guild_id, session["customer"])

    if is_binary(session["subscription"]) do
      remember_subscription(
        guild_id,
        %SubscriptionSnapshot{id: session["subscription"], item_id: nil, price_id: price_id}
      )
    end

    apply_cap(guild_id, cap, owner)
  end

  defp handle_subscription_updated(subscription) do
    guild_id = get_in(subscription, ["metadata", "guild_id"])
    price_id = subscription_price_id(subscription)
    cap = plan_cap(price_id)

    if is_binary(guild_id) do
      item_id =
        get_in(subscription, ["items", "data"])
        |> List.wrap()
        |> List.first()
        |> case do
          %{"id" => id} -> id
          _ -> nil
        end

      remember_subscription(
        guild_id,
        %SubscriptionSnapshot{
          id: subscription["id"],
          item_id: item_id,
          price_id: subscription_price_id(subscription)
        }
      )
    end

    if is_binary(guild_id) and cap do
      apply_cap(guild_id, cap, get_in(subscription, ["metadata", "owner_discord_id"]))
    else
      Logger.warning("customer.subscription.updated without guild/price metadata; ignored")
      :ok
    end
  end

  defp handle_subscription_deleted(subscription) do
    guild_id = get_in(subscription, ["metadata", "guild_id"])

    if is_binary(guild_id) do
      apply_cap(guild_id, 0, get_in(subscription, ["metadata", "owner_discord_id"]))
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
  defp apply_cap(guild_id, cap, owner_discord_id) when is_binary(guild_id) do
    owner_attrs =
      if is_binary(owner_discord_id) and owner_discord_id != "",
        do: %{owner_discord_id: owner_discord_id},
        else: %{}

    case Tenants.get_or_create_guild(guild_id, owner_attrs) do
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

  defp apply_cap(_, _, _), do: :ok

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
    for table <- [@events_ets, @customers_ets, @subscriptions_ets] do
      ensure_ets(table)
      :ets.delete_all_objects(table)
    end

    :ok
  end

  # -- Helpers ----------------------------------------------------------------

  defp base_url, do: SoundboardWeb.Endpoint.url()
end
