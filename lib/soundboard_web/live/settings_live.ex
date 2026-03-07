defmodule SoundboardWeb.SettingsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  alias Soundboard.Accounts.ApiTokens
  alias Soundboard.PublicURL

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/settings")
      |> assign(:current_user, get_user_from_session(session))
      |> assign(:tokens, [])
      |> assign(:new_token, nil)
      |> assign(:base_url, PublicURL.current())

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
                  data-copy-text={"curl -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds</code></pre>
              </div>
            </div>
            <div class="text-xs text-gray-600 dark:text-gray-400">
              Upload endpoint: <code class="font-mono">POST /api/sounds</code>. Required fields:
              <code class="font-mono">name</code>
              plus either <code class="font-mono">file</code>
              (local multipart)
              or <code class="font-mono">url</code>
              (<code class="font-mono">source_type=url</code>). Optional: <code class="font-mono">tags</code>,
              <code class="font-mono">volume</code>
              (0-150), <code class="font-mono">is_join_sound</code>, <code class="font-mono">is_leave_sound</code>.
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">
                Upload local file (multipart/form-data)
              </div>
              <div class="relative">
                <button
                  id="copy-upload-local"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" -F \"source_type=local\" -F \"name=<NAME>\" -F \"file=@/path/to/sound.mp3\" -F \"tags[]=meme\" -F \"tags[]=alert\" -F \"volume=90\" -F \"is_join_sound=true\" #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto min-h-[120px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST \
    -H "Authorization: Bearer {(@example_token || "<TOKEN>")}" \
    -F "source_type=local" \
    -F "name=&lt;NAME&gt;" \
    -F "file=@/path/to/sound.mp3" \
    -F "tags[]=meme" \
    -F "tags[]=alert" \
    -F "volume=90" \
    -F "is_join_sound=true" \
    {@base_url}/api/sounds</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">
                Upload from URL (JSON)
              </div>
              <div class="relative">
                <button
                  id="copy-upload-url"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" -H \"Content-Type: application/json\" -d '{\"source_type\":\"url\",\"name\":\"wow\",\"url\":\"https://example.com/wow.mp3\",\"tags\":[\"meme\",\"reaction\"],\"volume\":90,\"is_leave_sound\":true}' #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto min-h-[110px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST \
    -H "Authorization: Bearer {(@example_token || "<TOKEN>")}" \
    -H "Content-Type: application/json" \
    -d '&#123;"source_type":"url","name":"wow","url":"https://example.com/wow.mp3","tags":["meme","reaction"],"volume":90,"is_leave_sound":true&#125;' \
    {@base_url}/api/sounds</code></pre>
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
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds/<SOUND_ID>/play"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds/&lt;SOUND_ID&gt;/play</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300">Stop all sounds</div>
              <div class="relative">
                <button
                  id="copy-stop-sounds"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds/stop"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-100 rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-gray-800 dark:text-gray-100 font-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds/stop</code></pre>
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
end
