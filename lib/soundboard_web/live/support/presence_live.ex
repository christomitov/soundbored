defmodule SoundboardWeb.Live.Support.PresenceLive do
  defmacro __using__(_opts) do
    quote do
      alias SoundboardWeb.Presence
      require Logger

      @presence_topic "soundboard:presence"

      def mount_presence(socket, session) do
        if connected?(socket) do
          user = get_user_from_session(session)

          Phoenix.PubSub.subscribe(Soundboard.PubSub, @presence_topic)
          Process.put(:connected_pid, self())
          Process.put(:socket_id, socket.id)
          Process.put(:current_user, user)

          if user do
            {:ok, _} =
              Presence.track(self(), @presence_topic, socket.id, %{
                user: %{
                  username: user.username,
                  avatar: user.avatar
                },
                online_at: System.system_time(:second)
              })
          end
        end

        assign(socket, :presences, Presence.list(@presence_topic))
      end

      defp get_user_from_session(%{"user_id" => user_id}),
        do: Soundboard.Repo.get(Soundboard.Accounts.User, user_id)

      defp get_user_from_session(_), do: nil

      @impl true
      def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
        {:noreply, assign(socket, :presences, Presence.list(@presence_topic))}
      end
    end
  end
end
