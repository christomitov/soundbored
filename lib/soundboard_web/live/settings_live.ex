defmodule SoundboardWeb.SettingsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
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

    socket
    |> assign(:tokens, tokens)
    |> assign(:example_token, socket.assigns[:new_token])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl space-y-8 px-4 py-8">
      <h1 class="font-display text-3xl font-bold text-ink desk:uppercase desk:tracking-[0.14em] retro:italic">
        Settings
      </h1>

      <section aria-labelledby="appearance-heading" class="space-y-4">
        <header class="space-y-1">
          <h2 id="appearance-heading" class="font-display text-xl font-semibold text-ink">
            Appearance
          </h2>
          <p class="text-sm text-muted">Choose a theme. Your selection stays in this browser.</p>
        </header>

        <div class="grid gap-4 sm:grid-cols-3" id="theme-picker">
          <button
            type="button"
            data-theme-choice="classic"
            aria-pressed="false"
            class="group rounded-theme border border-line bg-surface p-4 text-left shadow-theme transition hover:-translate-y-0.5 classic:ring-2 classic:ring-accent"
          >
            <span class="mb-3 block h-16 rounded bg-gray-900 p-3 shadow-inner">
              <i class="block h-2 w-2/3 rounded bg-blue-500"></i>
              <i class="mt-2 block h-5 rounded bg-gray-700"></i>
            </span>
            <strong class="block text-ink">Classic</strong>
            <small class="text-muted">Clean, dark, and familiar</small>
          </button>

          <button
            type="button"
            data-theme-choice="desk"
            aria-pressed="false"
            class="group rounded-theme border border-line bg-surface p-4 text-left shadow-theme transition hover:-translate-y-0.5 desk:ring-2 desk:ring-accent"
          >
            <span class="mb-3 block h-16 rounded-sm border border-stone-500 bg-stone-300 p-3 shadow-inner">
              <i class="block h-2 w-2/3 bg-orange-600"></i>
              <i class="mt-2 block h-5 border border-stone-500 bg-stone-200"></i>
            </span>
            <strong class="block text-ink">Studio Desk</strong>
            <small class="text-muted">Warm hardware and signal orange</small>
          </button>

          <button
            type="button"
            data-theme-choice="retro"
            aria-pressed="false"
            class="group rounded-theme border border-line bg-surface p-4 text-left shadow-theme transition hover:-translate-y-0.5 retro:ring-2 retro:ring-accent"
          >
            <span class="mb-3 block h-16 border-2 border-slate-900 bg-amber-50 p-3 shadow-[3px_3px_0_#25202a]">
              <i class="block h-2 w-2/3 bg-blue-700"></i>
              <i class="mt-2 block h-5 border-2 border-slate-900 bg-red-500"></i>
            </span>
            <strong class="block text-ink">Retro Riso</strong>
            <small class="text-muted">Paper, ink, and punchy print color</small>
          </button>
        </div>
      </section>

      <section aria-labelledby="api-tokens-heading" class="space-y-6">
        <header class="space-y-2">
          <h2 id="api-tokens-heading" class="font-display text-xl font-semibold text-ink">
            API Tokens
          </h2>
          <p class="text-sm text-muted">
            Create a personal token to play sounds remotely. Requests authenticated with a token
            are attributed to your account and update your stats.
          </p>
        </header>

        <div class="bg-surface rounded-theme border border-line shadow-theme p-5 space-y-4">
          <form phx-submit="create_token" class="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div class="flex-1">
              <label class="block text-sm font-medium text-ink">Label</label>
              <input
                name="label"
                type="text"
                placeholder="e.g., CI Bot"
                class="mt-1 block w-full rounded-theme border-line bg-surface-muted text-ink shadow-sm placeholder:text-muted focus:border-accent focus:ring-accent"
              />
            </div>
            <button
              type="submit"
              class="w-full sm:w-auto justify-center px-4 py-2 bg-accent text-accent-contrast rounded-md font-medium hover:brightness-110 transition-colors focus:outline-none focus:ring-2 focus:ring-accent focus:ring-offset-2 dark:focus:ring-offset-gray-900 flex items-center"
            >
              Create
            </button>
          </form>
        </div>

        <div class="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700 rounded-lg px-4 py-3 text-sm text-amber-800 dark:text-amber-300">
          Token values are shown <strong>once</strong> at creation and cannot be retrieved afterwards.
          If you did not copy a token, revoke it and create a new one.
        </div>

        <%= if @new_token do %>
          <div class="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-700 rounded-lg p-4 space-y-2">
            <p class="text-sm font-medium text-green-800 dark:text-green-300">
              New token created — copy it now, it won't be shown again:
            </p>
            <div class="relative">
              <button
                id="copy-new-token"
                type="button"
                phx-hook="CopyButton"
                data-copy-text={@new_token}
                class="absolute right-2 top-1/2 -translate-y-1/2 text-xs px-2 py-1 bg-green-200 dark:bg-green-700 text-green-900 dark:text-green-100 rounded"
              >
                Copy
              </button>
              <pre class="overflow-x-auto whitespace-nowrap rounded-theme border border-line bg-surface-muted p-2 pr-20 text-xs"><code class="font-mono text-ink">{@new_token}</code></pre>
            </div>
          </div>
        <% end %>

        <div class="bg-surface rounded-theme border border-line shadow-theme overflow-hidden">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-line text-sm">
              <thead class="bg-surface-muted">
                <tr>
                  <th class="px-4 py-2 text-left text-xs font-medium uppercase tracking-wider text-muted">
                    Label
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium uppercase tracking-wider text-muted">
                    Created
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium uppercase tracking-wider text-muted">
                    Last Used
                  </th>
                  <th class="px-4 py-2"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-line">
                <%= for token <- @tokens do %>
                  <tr class="text-sm">
                    <td class="px-4 py-2 text-ink whitespace-nowrap">
                      {token.label || "(no label)"}
                    </td>
                    <td class="px-4 py-2 text-muted whitespace-nowrap">
                      {format_dt(token.inserted_at)}
                    </td>
                    <td class="px-4 py-2 text-muted whitespace-nowrap">
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

        <div class="bg-surface rounded-theme border border-line shadow-theme p-5 space-y-4">
          <h3 class="text-lg font-semibold text-ink">How to call the API</h3>
          <p class="text-sm text-ink">
            Include your token in the Authorization header:
            <code class="rounded bg-surface-muted px-1 py-0.5 font-mono text-ink">
              Authorization: Bearer {@example_token || "<token>"}
            </code>
          </p>
          <div class="space-y-4">
            <div>
              <div class="text-sm font-medium text-ink">List sounds</div>
              <div class="relative">
                <button
                  id="copy-list-sounds"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-surface-muted hover:bg-surface-raised text-ink rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-surface-muted border border-line rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-ink font-mono">curl -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds</code></pre>
              </div>
            </div>
            <div class="text-xs text-muted">
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
              <div class="text-sm font-medium text-ink">
                Upload local file (multipart/form-data)
              </div>
              <div class="relative">
                <button
                  id="copy-upload-local"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" -F \"source_type=local\" -F \"name=<NAME>\" -F \"file=@/path/to/sound.mp3\" -F \"tags[]=meme\" -F \"tags[]=alert\" -F \"volume=90\" -F \"is_join_sound=true\" #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-surface-muted hover:bg-surface-raised text-ink rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-surface-muted border border-line rounded text-xs overflow-x-auto min-h-[120px]"><code class="text-ink font-mono">curl -X POST \
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
              <div class="text-sm font-medium text-ink">
                Upload from URL (JSON)
              </div>
              <div class="relative">
                <button
                  id="copy-upload-url"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" -H \"Content-Type: application/json\" -d '{\"source_type\":\"url\",\"name\":\"wow\",\"url\":\"https://example.com/wow.mp3\",\"tags\":[\"meme\",\"reaction\"],\"volume\":90,\"is_leave_sound\":true}' #{@base_url}/api/sounds"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-surface-muted hover:bg-surface-raised text-ink rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-surface-muted border border-line rounded text-xs overflow-x-auto min-h-[110px]"><code class="text-ink font-mono">curl -X POST \
    -H "Authorization: Bearer {(@example_token || "<TOKEN>")}" \
    -H "Content-Type: application/json" \
    -d '&#123;"source_type":"url","name":"wow","url":"https://example.com/wow.mp3","tags":["meme","reaction"],"volume":90,"is_leave_sound":true&#125;' \
    {@base_url}/api/sounds</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-ink">
                Play a sound by ID
              </div>
              <div class="relative">
                <button
                  id="copy-play-sound"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds/<SOUND_ID>/play"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-surface-muted hover:bg-surface-raised text-ink rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-surface-muted border border-line rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-ink font-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds/&lt;SOUND_ID&gt;/play</code></pre>
              </div>
            </div>
            <div>
              <div class="text-sm font-medium text-ink">Stop all sounds</div>
              <div class="relative">
                <button
                  id="copy-stop-sounds"
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-text={"curl -X POST -H \"Authorization: Bearer #{(@example_token || "<TOKEN>")}\" #{@base_url}/api/sounds/stop"}
                  class="absolute right-2 top-2 text-xs px-2 py-1 bg-surface-muted hover:bg-surface-raised text-ink rounded"
                >
                  Copy
                </button>
                <pre class="mt-1 p-2 pr-16 bg-surface-muted border border-line rounded text-xs overflow-x-auto whitespace-nowrap min-h-[56px]"><code class="text-ink font-mono">curl -X POST -H \"Authorization: Bearer {(@example_token || "<TOKEN>")}\" {@base_url}/api/sounds/stop</code></pre>
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
