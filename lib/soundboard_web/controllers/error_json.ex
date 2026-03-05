defmodule SoundboardWeb.ErrorJSON do
  @moduledoc """
  Renders fallback JSON error payloads.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
