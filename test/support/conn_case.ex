defmodule SoundboardWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate
  require Phoenix.LiveViewTest
  @endpoint SoundboardWeb.Endpoint

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import SoundboardWeb.ConnCase
      import Soundboard.TestHelpers

      alias SoundboardWeb.Router.Helpers, as: Routes

      @endpoint SoundboardWeb.Endpoint

      use SoundboardWeb, :verified_routes
    end
  end

  setup tags do
    Soundboard.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @stripe_env [
    secret_key: "sk_test_key",
    webhook_secret: "whsec_test",
    price_pro_monthly: "price_pro_m",
    price_pro_yearly: "price_pro_y",
    price_studio_monthly: "price_studio_m",
    price_studio_yearly: "price_studio_y"
  ]

  @doc "Turns hosted billing on for the calling test, with fake Stripe keys and prices."
  def enable_billing do
    Soundboard.Billing.reset_memory()
    Application.put_env(:soundboard, Soundboard.Billing, @stripe_env)

    ExUnit.Callbacks.on_exit(fn ->
      Soundboard.Billing.reset_memory()
      Application.put_env(:soundboard, Soundboard.Billing, [])
    end)

    :ok
  end

  @doc "A Stripe-signed `stripe-signature` header for `payload`, timestamped `at` (unix seconds)."
  def stripe_signature(payload, at \\ System.system_time(:second)) do
    ts = Integer.to_string(at)
    signed = ts <> "." <> payload

    mac =
      Base.encode16(:crypto.mac(:hmac, :sha256, @stripe_env[:webhook_secret], signed),
        case: :lower
      )

    "t=#{ts},v1=#{mac}"
  end

  @doc "Delivers a Stripe event to the webhook through the endpoint, signed now."
  def deliver_stripe_event(event) do
    payload = Jason.encode!(event)

    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("stripe-signature", stripe_signature(payload))
    |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/billing/webhook", payload)
  end

  @doc "Inserts a user with a unique Discord id."
  def user_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %Soundboard.Accounts.User{}
    |> Soundboard.Accounts.User.changeset(
      Map.merge(%{discord_id: "#{n}", username: "user#{n}", avatar: nil}, attrs)
    )
    |> Soundboard.Repo.insert!()
  end

  @doc "A browser session signed in as `user`, with any extra session keys."
  def sign_in(conn, user, session \\ %{}) do
    Plug.Test.init_test_session(conn, Map.put(session, :user_id, user.id))
  end

  def file_upload(lv, field, entries) do
    {entries, _refs} =
      Enum.reduce(entries, {[], []}, fn entry, {entries, refs} ->
        ref = entry[:ref] || "phx-#{System.unique_integer()}"

        entry =
          Map.merge(
            %{
              name: "test.mp3",
              content: "test",
              size: 9999,
              type: "audio/mpeg",
              ref: ref,
              done?: true
            },
            entry
          )

        {[entry | entries], [ref | refs]}
      end)

    entries = Enum.reverse(entries)

    for entry <- entries do
      Phoenix.LiveViewTest.file_input(lv, field, entry, entry.ref)
    end
  end
end
