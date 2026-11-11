defmodule SoundboardWeb.Live.SoundboardLive.UploadFlow.State do
  @moduledoc false

  defstruct show_upload_modal: false,
            guild_id: nil,
            source_type: "local",
            upload_name: "",
            url: "",
            upload_tags: [],
            upload_tag_input: "",
            upload_tag_suggestions: [],
            is_join_sound: false,
            is_leave_sound: false,
            upload_error: nil,
            upload_volume: 100,
            current_user: nil,
            audio_entries: [],
            current_upload: nil

  @type t :: %__MODULE__{
          show_upload_modal: boolean(),
          source_type: String.t(),
          upload_name: String.t(),
          url: String.t(),
          upload_tags: list(),
          upload_tag_input: String.t(),
          upload_tag_suggestions: list(),
          is_join_sound: boolean(),
          is_leave_sound: boolean(),
          upload_error: String.t() | nil,
          upload_volume: number(),
          current_user: term(),
          audio_entries: list(),
          current_upload: map() | nil
        }
end
