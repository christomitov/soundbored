defmodule SoundboardWeb.ErrorHTML do
  @moduledoc """
  Renders fallback HTML error messages.
  """
  use SoundboardWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
