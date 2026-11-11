defmodule SoundboardWeb.Components.Layouts.Navbar do
  @moduledoc """
  The navbar component. A plain function component so it renders in both
  LiveViews and controller-rendered pages; the mobile menu toggles entirely
  client-side via JS.
  """

  use SoundboardWeb, :html

  alias Phoenix.LiveView.JS
  alias Soundboard.Billing

  embed_templates "navbar/*"

  attr :current_user, :map, default: nil
  attr :current_path, :string, default: nil
  attr :presences, :map, default: %{}
  attr :app_unlocked, :boolean, default: true

  def navbar(assigns)

  def nav_link(assigns)

  def mobile_nav_link(assigns)

  defp visible_users(presences) do
    presences
    |> Enum.flat_map(fn {_id, presence} ->
      Enum.map(presence.metas, & &1.user)
    end)
    |> Enum.uniq_by(& &1.username)
  end

  defp current_page?(current_path, path), do: current_path == path
end
