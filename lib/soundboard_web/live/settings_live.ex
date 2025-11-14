defmodule SoundboardWeb.SettingsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  alias Soundboard.Accounts
  alias Soundboard.Accounts.{ApiTokens, Tenants}
  alias SoundboardWeb.Live.TenantHelpers

  @impl true
  def mount(_params, session, socket) do
    current_user = get_user_from_session(session)
    tenant_id = TenantHelpers.tenant_id_from_session(session, current_user)
    tenant = Tenants.get_tenant!(tenant_id)

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/settings")
      |> assign(:current_user, current_user)
      |> assign(:current_tenant, tenant)
      |> assign(:edition, Accounts.edition())
      |> assign(:plan_usage, Accounts.plan_usage(tenant))
      |> assign(:tokens, [])
      |> assign(:new_token, nil)
      |> assign(:base_url, nil)

    {:ok, load_tokens(socket)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    base_url = base_url_from_uri(uri)
    {:noreply, assign(socket, :base_url, base_url)}
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

  defp plan_resource_list(%{sounds: sounds, users: users, guilds: guilds}) do
    [
      {"Sounds", sounds},
      {"Members", users},
      {"Discord Guilds", guilds}
    ]
  end

  defp plan_name(nil), do: "Community"
  defp plan_name(plan) when is_atom(plan), do: plan |> Atom.to_string() |> String.capitalize()
  defp plan_name(plan), do: to_string(plan)

  defp usage_display(%{limit: nil, count: count}), do: "#{count} used · Unlimited"

  defp usage_display(%{limit: limit, count: count}) when is_integer(limit) do
    "#{count} / #{limit} used"
  end

  defp usage_display(%{count: count}), do: "#{count} used"

  defp usage_percent(%{limit: nil}), do: 0
  defp usage_percent(%{limit: limit}) when not is_integer(limit) or limit <= 0, do: 100

  defp usage_percent(%{limit: limit, count: count}) do
    percent = count / limit * 100
    percent |> min(100.0) |> Float.round(2)
  end

  defp usage_remaining_text(%{limit: nil}), do: nil
  defp usage_remaining_text(%{remaining: nil}), do: nil
  defp usage_remaining_text(%{remaining: remaining}) when remaining <= 0, do: "No remaining slots"
  defp usage_remaining_text(%{remaining: remaining}), do: "#{remaining} remaining"

  defp load_tokens(%{assigns: %{current_user: nil}} = socket), do: socket

  defp load_tokens(%{assigns: %{current_user: user}} = socket) do
    tokens = ApiTokens.list_tokens(user)

    example =
      socket.assigns[:new_token] ||
        case tokens do
          [%{token: tok} | _] when is_binary(tok) -> tok
          _ -> nil
        end

    socket
    |> assign(:tokens, tokens)
    |> assign(:example_token, example)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <h1 class="text-2xl font-bold text-gray-800 dark:text-gray-100">Settings</h1>

      <%= if @edition == :pro do %>
        <section aria-labelledby="plan-heading" class="space-y-4">
          <header class="space-y-2">
            <h2 id="plan-heading" class="text-xl font-semibold text-gray-800 dark:text-gray-100">
              Plan &amp; Billing
            </h2>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              Monitor usage limits and quickly jump to your billing portal when running the Pro edition.
            </p>
          </header>

          <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-6">
            <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <div class="text-sm text-gray-500 dark:text-gray-400">Current plan</div>
                <div class="text-2xl font-semibold text-gray-900 dark:text-gray-100">
                  {plan_name(@current_tenant.plan)}
                </div>
                <%= if @current_tenant.subscription_ends_at do %>
                  <div class="text-sm text-gray-500 dark:text-gray-400">
                    Renews {format_dt(@current_tenant.subscription_ends_at)}
                  </div>
                <% end %>
              </div>

              <div class="flex flex-wrap gap-3">
                <%= if upgrade_url = Accounts.upgrade_url() do %>
                  <.link
                    href={upgrade_url}
                    target="_blank"
                    class="inline-flex items-center px-4 py-2 rounded-md border border-blue-600 text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-950"
                  >
                    Upgrade Plan
                  </.link>
                <% end %>

                <%= if manage_url = Accounts.manage_subscription_url(@current_tenant) do %>
                  <.link
                    href={manage_url}
                    target="_blank"
                    class="inline-flex items-center px-4 py-2 rounded-md bg-blue-600 text-white hover:bg-blue-700"
                  >
                    Manage Subscription
                  </.link>
                <% end %>
              </div>
            </div>

            <dl class="grid gap-4 md:grid-cols-3">
              <%= for {label, usage} <- plan_resource_list(@plan_usage) do %>
                <div class="space-y-2">
                  <dt class="text-sm text-gray-600 dark:text-gray-400">{label}</dt>
                  <dd class="text-lg font-medium text-gray-900 dark:text-gray-100">
                    {usage_display(usage)}
                  </dd>
                  <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                    <div
                      class="h-2 rounded-full bg-blue-600"
                      style={"width: #{usage_percent(usage)}%;"}
                    >
                    </div>
                  </div>
                  <%= if remaining = usage_remaining_text(usage) do %>
                    <p class="text-xs text-gray-500 dark:text-gray-400">{remaining}</p>
                  <% end %>
                </div>
              <% end %>
            </dl>
          </div>
        </section>
      <% end %>

      <section aria-labelledby="api-tokens-heading" class="space-y-6">
        <header class="space-y-2">
          <h2 id="api-tokens-heading" class="text-xl font-semibold text-gray-800 dark:text-gray-100">
            API Tokens
          </h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Create a personal token to play sounds remotely. Requests authenticated with a token
            are attributed to your account and update your stats.
          </p>
        </header>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-4">
          <form phx-submit="create_token" class="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div class="flex-1">
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">Label</label>
              <input
                name="label"
                type="text"
                placeholder="e.g., CI Bot"
                class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-700 shadow-sm dark:bg-gray-900 dark:text-gray-100 focus:border-blue-500 focus:ring-blue-500"
              />
            </div>
            <button
              type="submit"
              class="w-full sm:w-auto justify-center px-4 py-2 bg-blue-600 text-white rounded-md font-medium hover:bg-blue-700 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900 flex items-center"
            >
              Create
            </button>
          </form>
        </div>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow overflow-hidden">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700 text-sm">
              <thead class="bg-gray-50 dark:bg-gray-900">
                <tr>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Label
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Token
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Created
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Last Used
                  </th>
                  <th class="px-4 py-2"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <%= for token <- @tokens do %>
                  <tr class="text-sm">
                    <td class="px-4 py-2 text-gray-900 dark:text-gray-100 whitespace-nowrap">
                      {token.label || "(no label)"}
                    </td>
                    <td class="px-4 py-2 align-top">
                      <div class="relative">
                        <button
                          id={"copy-token-#{token.id}"}
                          type="button"
                          phx-hook="CopyButton"
                          data-copy-text={token.token}
                          class="absolute right-2 top-1/2 -translate-y-1/2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                        >
                          Copy
                        </button>
                        <pre class="p-2 pr-20 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap"><code class="text-gray-800 dark:text-gray-100 font-mono">{token.token}</code></pre>
                      </div>
                    </td>
                    <td class="px-4 py-2 text-gray-500 dark:text-gray-400 whitespace-nowrap">
                      {format_dt(token.inserted_at)}
                    </td>
                    <td class="px-4 py-2 text-gray-500 dark:text-gray-400 whitespace-nowrap">
                      {format_dt(token.last_used_at) || "—"}
                    </td>
                    <td class="px-4 py-2 text-right align-top">
                      <button
                        phx-click="revoke_token"
                        phx-value-id={token.id}
                        class="px-3 py-1 bg-red-600 text-white rounded hover:bg-red-700 transition-colors focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
                      >
                        Revoke
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-5 space-y-4">
          <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-100">How to call the API</h3>
          <p class="text-sm text-gray-700 dark:text-gray-300">
            Include your token in the Authorization header:
            <code class="px-1 py-0.5 rounded bg-gray-100 dark:bg-gray-800 text-gray-800 dark:text-gray-100 font-mono">
              Authorization: Bearer {@example_token || "<token>"}
            </code>
          </p>
          <div class="space-y-4">
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">List sounds</div>
              <div class="relative">
                <button
                  id="copy-list-sounds"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">
                Play a sound by ID
              </div>
              <div class="relative">
                <button
                  id="copy-play-sound"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds/<SOUND_ID>/play"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds/&lt;SOUND_ID&gt;/play</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">Stop all sounds</div>
              <div class="relative">
                <button
                  id="copy-stop-sounds"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds/stop"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds/stop</code></pre>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp format_dt(nil), do: nil
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp base_url_from_uri(nil), do: SoundboardWeb.Endpoint.url()

  defp base_url_from_uri(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host, port: port} when is_binary(host) ->
        port_part =
          case {scheme, port} do
            {"http", 80} -> ""
            {"https", 443} -> ""
            {_, nil} -> ""
            {_, p} -> ":#{p}"
          end

        scheme <> "://" <> host <> port_part

      _ ->
        SoundboardWeb.Endpoint.url()
    end
  end
end
