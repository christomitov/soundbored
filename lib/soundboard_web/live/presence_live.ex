defmodule SoundboardWeb.Live.PresenceLive do
  defmacro __using__(_opts) do
    quote do
      alias SoundboardWeb.{Presence, Live.PresenceHandler}
      require Logger

      @presence_topic "soundboard:presence"

      def mount_presence(socket, session) do
        if connected?(socket) do
          user = get_user_from_session(session)

          # Store process info BEFORE any presence tracking
          Process.put(:connected_pid, self())
          Process.put(:socket_id, socket.id)
          Process.put(:current_user, user)
          Logger.debug("Stored process info: pid=#{inspect(self())}, user=#{inspect(user)}")

          if user do
            # Track presence AFTER storing process info
            {:ok, _} =
              Presence.track(self(), @presence_topic, socket.id, %{
                user: %{
                  username: user.username,
                  avatar: user.avatar
                },
                online_at: System.system_time(:second),
                color_updated_at: System.system_time(:second)
              })
          end
        end

        socket
        |> assign(:presences, Presence.list(@presence_topic))
        |> assign(:presence_count, map_size(Presence.list(@presence_topic)))
      end

      defp get_user_from_session(%{"user_id" => user_id}),
        do: Soundboard.Repo.get(Soundboard.Accounts.User, user_id)

      defp get_user_from_session(_), do: nil

      @impl true
      def handle_info({:user_color_changed, username}, socket) do
        Logger.debug("Received color change broadcast for #{username}")
        new_presences = Presence.list(@presence_topic)

        # Just broadcast a presence update event
        Phoenix.PubSub.broadcast(
          Soundboard.PubSub,
          @presence_topic,
          {:presence_update, new_presences}
        )

        {:noreply, assign(socket, :presences, new_presences)}
      end

      @impl true
      def handle_info({:presence_update, presences}, socket) do
        {:noreply, assign(socket, :presences, presences)}
      end

      @impl true
      def handle_info({:presence_diff, diff}, socket) do
        {:noreply,
         assign(socket,
           presence_count:
             SoundboardWeb.Live.PresenceHandler.handle_presence_diff(
               diff,
               socket.assigns.presence_count
             )
         )}
      end
    end
  end
end
