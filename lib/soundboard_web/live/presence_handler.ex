defmodule SoundboardWeb.Live.PresenceHandler do
  import Phoenix.LiveView, only: [connected?: 1]
  alias SoundboardWeb.Presence
  require Logger

  @presence_topic "soundboard:presence"

  @colors [
    "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
    "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
    "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200",
    "bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200",
    "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
    "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
    "bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200",
    "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
    "bg-teal-100 text-teal-800 dark:bg-teal-900 dark:text-teal-200",
    "bg-slate-100 text-slate-800 dark:bg-slate-900 dark:text-slate-200",
    "bg-zinc-100 text-zinc-800 dark:bg-zinc-900 dark:text-zinc-200",
    "bg-neutral-100 text-neutral-800 dark:bg-neutral-900 dark:text-neutral-200",
    "bg-stone-100 text-stone-800 dark:bg-stone-900 dark:text-stone-200",
    "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"
  ]

  @colors_key :user_colors

  def init do
    :persistent_term.put(@colors_key, %{})
  end

  def track_presence(socket, user) do
    if connected?(socket) do
      username = if user, do: user.username, else: "Anonymous #{socket.id |> String.slice(0..5)}"
      color = get_random_unique_color(username)

      Presence.track(self(), @presence_topic, socket.id, %{
        online_at: System.system_time(:second),
        user: %{
          username: username,
          avatar: if(user, do: user.avatar, else: nil),
          color: color
        }
      })
    end
  end

  @spec get_user_color(String.t()) :: String.t()
  def get_user_color(username) do
    colors = :persistent_term.get(@colors_key, %{})
    Map.get(colors, username) || get_random_unique_color(username)
  end

  defp get_random_unique_color(username) do
    colors = :persistent_term.get(@colors_key, %{})
    used_colors = Map.values(colors)

    available_colors = Enum.reject(@colors, &(&1 in used_colors))

    color =
      if Enum.empty?(available_colors) do
        # If all colors are used, pick a random one
        Enum.random(@colors)
      else
        # Pick a random available color
        Enum.random(available_colors)
      end

    # Store the color assignment
    :persistent_term.put(@colors_key, Map.put(colors, username, color))

    color
  end

  def get_presence_count do
    @presence_topic
    |> Presence.list()
    |> count_active_presences()
  end

  def handle_presence_diff(%{joins: joins, leaves: leaves}, current_count) do
    now = System.system_time(:second)

    active_joins = count_active_presences(joins, now)
    active_leaves = count_active_presences(leaves, now)

    max(current_count + (active_joins - active_leaves), 0)
  end

  defp count_active_presences(presences) do
    now = System.system_time(:second)
    count_active_presences(presences, now)
  end

  defp count_active_presences(presences, now) do
    Enum.count(presences, fn {_id, presence} ->
      metas = presence.metas || []

      Enum.any?(metas, fn %{online_at: online_at} ->
        now - online_at < 60
      end)
    end)
  end
end
