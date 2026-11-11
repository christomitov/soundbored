defmodule SoundboardWeb.Components.Soundboard.UploadModal do
  @moduledoc """
  The upload modal component.
  """
  use Phoenix.Component

  alias SoundboardWeb.Components.Soundboard.{TagComponents, VolumeControl}

  embed_templates "upload_modal/*"

  def upload_modal(assigns)

  defp source_input_ready?("local", entries, _url),
    do: entries != [] and Enum.all?(entries, & &1.valid?)

  defp source_input_ready?("url", _entries, url), do: String.trim(url || "") != ""
  defp source_input_ready?(_, _entries, _url), do: false

  defp form_ready?(source_type, entries, url, upload_error) do
    source_input_ready?(source_type, entries, url) and is_nil(upload_error)
  end

  defp upload_error_messages(upload) do
    entry_errors = Enum.flat_map(upload.entries, &upload_errors(upload, &1))

    Enum.map(upload_errors(upload) ++ entry_errors, &upload_error_message(&1, upload))
  end

  defp upload_error_message(:too_large, upload),
    do: "File is too large (max #{max(div(upload.max_file_size, 1_000_000), 1)}MB)"

  defp upload_error_message(:not_accepted, _upload),
    do: "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."

  defp upload_error_message(:too_many_files, _upload), do: "Choose one file at a time"
  defp upload_error_message(_error, _upload), do: "The file could not be uploaded"

  defp local_upload_pending?(source_type, entries), do: source_type == "local" and entries == []

  defp url_upload_pending?(source_type, url),
    do: source_type == "url" and String.trim(url || "") == ""
end
