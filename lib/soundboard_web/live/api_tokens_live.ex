defmodule SoundboardWeb.ApiTokensLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  alias Soundboard.Accounts.ApiTokens

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/settings/api")
      |> assign(:current_user, get_user_from_session(session))
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
    <div class="max-w-3xl mx-auto p-6">
      <h1 class="text-2xl font-bold text-gray-800 dark:text-gray-100 mb-4">API Tokens</h1>

      <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4 mb-6">
        <p class="text-sm text-gray-600 dark:text-gray-400 mb-3">
          Create a personal API token to play sounds via HTTP. Requests authenticated with a token
          are attributed to your account and will increment your stats.
        </p>
        <form phx-submit="create_token" class="flex gap-2 items-end">
          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">Label</label>
            <input
              name="label"
              type="text"
              placeholder="e.g., CI Bot"
              class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-700 shadow-sm dark:bg-gray-800 dark:text-gray-100"
            />
          </div>
          <button type="submit" class="px-4 py-2 bg-blue-600 text-white rounded-md">Create</button>
        </form>
      </div>

      <div class="bg-white dark:bg-gray-800 rounded-lg shadow">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead>
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
              <tr>
                <td class="px-4 py-2 text-sm text-gray-900 dark:text-gray-100">
                  {token.label || "(no label)"}
                </td>
                <td class="px-4 py-2">
                  <div class="relative">
                    <button
                      id={"copy-token-#{token.id}"}
                      type="button"
                      phx-hook="CopyButton"
                      data-copy-text={token.token}
                      class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                    >
                      Copy
                    </button>
                    <pre class="p-2 pr-16 bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded text-xs whitespace-pre-wrap"><code class="text-gray-800 dark:text-gray-100 font-mono break-all">{token.token}</code></pre>
                  </div>
                </td>
                <td class="px-4 py-2 text-sm text-gray-500 dark:text-gray-400">
                  {format_dt(token.inserted_at)}
                </td>
                <td class="px-4 py-2 text-sm text-gray-500 dark:text-gray-400">
                  {format_dt(token.last_used_at) || "—"}
                </td>
                <td class="px-4 py-2 text-right">
                  <button
                    phx-click="revoke_token"
                    phx-value-id={token.id}
                    class="px-3 py-1 bg-red-600 text-white rounded"
                  >
                    Revoke
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4 mb-6 mt-6">
        <h2 class="text-lg font-semibold text-gray-800 dark:text-gray-100 mb-2">
          How to call the API
        </h2>
        <p class="text-sm text-gray-700 dark:text-gray-300 mb-2">
          Include your token in the Authorization header:
          <code class="px-1 py-0.5 rounded bg-gray-100 dark:bg-gray-800 text-gray-800 dark:text-gray-100 font-mono">
            Authorization: Bearer {@example_token || "<token>"}
          </code>
        </p>
        <div class="space-y-3">
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
              <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-y-auto overflow-x-hidden whitespace-pre-wrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono break-words">curl -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds</code></pre>
            </div>
          </div>
          <div>
            <div class="text-sm font-medium text-gray-700 dark:text-gray-300">Play a sound by ID</div>
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
              <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-y-auto overflow-x-hidden whitespace-pre-wrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono break-words">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds/&lt;SOUND_ID&gt;/play</code></pre>
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
              <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-y-auto overflow-x-hidden whitespace-pre-wrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono break-words">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {(@base_url || SoundboardWeb.Endpoint.url())}/api/sounds/stop</code></pre>
            </div>
          </div>
        </div>
        <p class="text-xs text-gray-600 dark:text-gray-300 mt-3">
          Plays are recorded under your user and appear in stats and recent plays. Revoked tokens are immediately invalid and are hidden from the list below.
        </p>
      </div>
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
