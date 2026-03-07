defmodule SoundboardWeb.Live.TagForm do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias SoundboardWeb.Live.LiveTags

  @type config :: %{required(:input_key) => atom(), required(:suggestions_key) => atom()}

  def handle_key(socket, key, value, current_tags, apply_tag_fun, config)
      when is_function(apply_tag_fun, 3) and is_map(config) do
    if key == "Enter" and value != "" do
      select_tag(socket, value, current_tags, apply_tag_fun, config)
    else
      update_input(socket, value, config)
    end
  end

  def select_tag(socket, tag_name, current_tags, apply_tag_fun, config)
      when is_function(apply_tag_fun, 3) and is_map(config) do
    tag_name
    |> LiveTags.add_tag(current_tags, fn tag, tags -> apply_tag_fun.(socket, tag, tags) end)
    |> handle_result(socket, config)
  end

  def update_input(socket, value, %{input_key: input_key, suggestions_key: suggestions_key}) do
    suggestions = LiveTags.search(value)

    {:noreply,
     socket
     |> assign(input_key, value)
     |> assign(suggestions_key, suggestions)}
  end

  defp handle_result({:ok, updated_socket}, _socket, config) do
    {:noreply, reset(updated_socket, config)}
  end

  defp handle_result({:error, message}, socket, config) do
    {:noreply,
     socket
     |> reset(config)
     |> put_flash(:error, message)}
  end

  defp reset(socket, %{input_key: input_key, suggestions_key: suggestions_key}) do
    socket
    |> assign(input_key, "")
    |> assign(suggestions_key, [])
  end
end
