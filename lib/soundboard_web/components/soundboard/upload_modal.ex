defmodule SoundboardWeb.Components.Soundboard.UploadModal do
  @moduledoc """
  The upload modal component.
  """
  use Phoenix.Component

  alias SoundboardWeb.Components.Soundboard.{TagComponents, VolumeControl}

  embed_templates "upload_modal/*"

  def upload_modal(assigns)

  defp source_input_ready?("local", entries, _url), do: entries != []
  defp source_input_ready?("url", _entries, url), do: String.trim(url || "") != ""
  defp source_input_ready?(_, _entries, _url), do: false

  defp form_ready?(source_type, entries, url, upload_error) do
    source_input_ready?(source_type, entries, url) and is_nil(upload_error)
  end

  defp local_upload_pending?(source_type, entries), do: source_type == "local" and entries == []

  defp url_upload_pending?(source_type, url),
    do: source_type == "url" and String.trim(url || "") == ""
end
