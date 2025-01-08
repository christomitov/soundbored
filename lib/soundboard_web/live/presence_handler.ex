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
    "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"
  ]

  @colors_key :user_colors
  @clicks_key :user_clicks

  def init do
    :persistent_term.put(@colors_key, %{})
    :persistent_term.put(@clicks_key, %{})
  end

  def track_presence(socket, user) do
    if connected?(socket) do
      username = if user, do: user.username, else: "Anonymous #{socket.id |> String.slice(0..5)}"

      Presence.track(self(), @presence_topic, socket.id, %{
        online_at: System.system_time(:second),
        color_updated_at: System.system_time(:second),
        user: %{
          username: username,
          avatar: if(user, do: user.avatar, else: nil)
        }
      })
    end
  end

  @spec get_user_color(any()) :: any()
  def get_user_color(username) do
    colors = :persistent_term.get(@colors_key, %{})
    index = Map.get(colors, username, :erlang.phash2(username, length(@colors)))
    Enum.at(@colors, index)
  end

  @spec cycle_user_color(any()) :: nil | {:error, any()} | {:ok, binary()}
  def cycle_user_color(username) do
    Logger.debug("Cycling color for #{username}")
    pid = Process.get(:connected_pid)
    user = Process.get(:current_user)
    socket_id = Process.get(:socket_id)

    Logger.debug("""
    Process info:
    PID: #{inspect(pid)}
    User: #{inspect(user)}
    Socket ID: #{inspect(socket_id)}
    """)

    if pid do
      current_user = Process.get(:current_user)
      Logger.debug("Current user: #{inspect(current_user)}")

      if current_user && current_user.username == username do
        # Get and increment click count
        clicks = :persistent_term.get(@clicks_key, %{})
        click_count = Map.get(clicks, username, 0) + 1
        Logger.debug("Click count for #{username}: #{click_count}")

        # Update clicks
        :persistent_term.put(@clicks_key, Map.put(clicks, username, click_count))

        # Only change color on third click
        if click_count >= 3 do
          Logger.debug("Changing color for #{username}")
          # Reset click count
          :persistent_term.put(@clicks_key, Map.put(clicks, username, 0))

          # Change color
          colors = :persistent_term.get(@colors_key, %{})
          current_index = Map.get(colors, username, :erlang.phash2(username, length(@colors)))
          new_index = rem(current_index + 1, length(@colors))
          Logger.debug("New color index for #{username}: #{new_index}")

          :persistent_term.put(@colors_key, Map.put(colors, username, new_index))

          # Update presence with new color and broadcast in one step
          Presence.update(pid, @presence_topic, socket_id, fn meta ->
            meta
            |> Map.put(:color_updated_at, System.system_time(:second))
            |> put_in([:user, :color], get_user_color(username))
          end)

          {:ok, "Color updated"}
        end
      else
        Logger.debug("User not authorized to change color: #{username}")
      end
    else
      Logger.debug("No connected process found for color change")
    end
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
