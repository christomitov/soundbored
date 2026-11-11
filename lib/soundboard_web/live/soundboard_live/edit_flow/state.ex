defmodule SoundboardWeb.Live.SoundboardLive.EditFlow.State do
  @moduledoc false

  alias Soundboard.Sound

  defstruct show_modal: false,
            current_sound: nil,
            tag_input: "",
            tag_suggestions: [],
            show_delete_confirm: false,
            edit_name_error: nil,
            current_user_id: nil

  @type t :: %__MODULE__{
          show_modal: boolean(),
          current_sound: Sound.t() | nil,
          tag_input: String.t(),
          tag_suggestions: list(),
          show_delete_confirm: boolean(),
          edit_name_error: String.t() | nil,
          current_user_id: integer() | nil
        }
end
