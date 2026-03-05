defmodule SoundboardWeb.ChainsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive

  alias Soundboard.Chains

  @pubsub_topic "soundboard"

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, @pubsub_topic)
    end

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/chains")
      |> assign(:current_user, get_user_from_session(session))
      |> assign(:my_chains, [])
      |> assign(:public_chains, [])
      |> load_chains()

    {:ok, socket}
  end

  @impl true
  def handle_event("play_chain", %{"id" => _chain_id}, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to play chains")}
  end

  @impl true
  def handle_event("play_chain", %{"id" => chain_id}, socket) do
    user = socket.assigns.current_user

    case Chains.get_playable_chain(user.id, chain_id) do
      {:ok, chain} ->
        SoundboardWeb.AudioPlayer.play_chain(chain, user.username)
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Chain not found")}
    end
  end

  @impl true
  def handle_event(
        "delete_chain",
        %{"id" => _chain_id},
        %{assigns: %{current_user: nil}} = socket
      ) do
    {:noreply, put_flash(socket, :error, "You must be logged in to delete chains")}
  end

  @impl true
  def handle_event("delete_chain", %{"id" => chain_id}, socket) do
    user = socket.assigns.current_user

    case Chains.delete_chain(user.id, chain_id) do
      {:ok, _chain} ->
        {:noreply,
         socket
         |> load_chains()
         |> put_flash(:info, "Chain deleted")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Chain not found")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete chain")}
    end
  end

  @impl true
  def handle_info({:sound_played, %{filename: filename, played_by: username}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "#{username} played #{display_name(filename)}")
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info({:error, message}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8 space-y-8">
      <div class="flex items-center justify-between">
        <h1 class="text-3xl font-bold text-gray-800 dark:text-gray-100">Chains</h1>
      </div>

      <section class="space-y-4">
        <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100">My Chains</h2>
        <%= if @my_chains == [] do %>
          <p class="text-sm text-gray-500 dark:text-gray-400">
            No chains yet. Use "Add Chain" on the Sounds page to create one.
          </p>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for chain <- @my_chains do %>
              <article class="rounded-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-4 space-y-3">
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <h3 class="font-semibold text-gray-900 dark:text-gray-100">{chain.name}</h3>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      {if chain.is_public, do: "Public", else: "Private"} • {length(chain.chain_items)} sounds
                    </p>
                  </div>
                  <div class="flex gap-2">
                    <button
                      phx-click="play_chain"
                      phx-value-id={chain.id}
                      class="px-3 py-1.5 rounded-md text-sm font-medium border border-green-500/70 text-green-600 dark:text-green-300 hover:bg-green-500/10"
                    >
                      Play
                    </button>
                    <button
                      phx-click="delete_chain"
                      phx-value-id={chain.id}
                      class="px-3 py-1.5 rounded-md text-sm font-medium border border-red-500/70 text-red-600 dark:text-red-300 hover:bg-red-500/10"
                    >
                      Delete
                    </button>
                  </div>
                </div>

                <ol class="space-y-1 text-sm text-gray-700 dark:text-gray-300">
                  <%= for {label, index} <- Enum.with_index(chain_item_labels(chain)) do %>
                    <li>{index + 1}. {label}</li>
                  <% end %>
                </ol>
              </article>
            <% end %>
          </div>
        <% end %>
      </section>

      <section class="space-y-4">
        <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100">Public Chains</h2>
        <%= if @public_chains == [] do %>
          <p class="text-sm text-gray-500 dark:text-gray-400">
            No public chains available yet.
          </p>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for chain <- @public_chains do %>
              <article class="rounded-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-4 space-y-3">
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <h3 class="font-semibold text-gray-900 dark:text-gray-100">{chain.name}</h3>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      By {chain.user.username} • {length(chain.chain_items)} sounds
                    </p>
                  </div>
                  <button
                    phx-click="play_chain"
                    phx-value-id={chain.id}
                    class="px-3 py-1.5 rounded-md text-sm font-medium border border-green-500/70 text-green-600 dark:text-green-300 hover:bg-green-500/10"
                  >
                    Play
                  </button>
                </div>

                <ol class="space-y-1 text-sm text-gray-700 dark:text-gray-300">
                  <%= for {label, index} <- Enum.with_index(chain_item_labels(chain)) do %>
                    <li>{index + 1}. {label}</li>
                  <% end %>
                </ol>
              </article>
            <% end %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp load_chains(%{assigns: %{current_user: nil}} = socket) do
    socket
    |> assign(:my_chains, [])
    |> assign(:public_chains, [])
  end

  defp load_chains(%{assigns: %{current_user: user}} = socket) do
    socket
    |> assign(:my_chains, Chains.list_user_chains(user.id))
    |> assign(:public_chains, Chains.list_public_chains(user.id))
  end

  defp chain_item_labels(chain) do
    Enum.map(chain.chain_items, fn
      %{sound: %{filename: filename}} -> display_name(filename)
      _ -> "(missing sound)"
    end)
  end

  defp clear_flash_after_timeout(socket) do
    Process.send_after(self(), :clear_flash, 3000)
    socket
  end
end
