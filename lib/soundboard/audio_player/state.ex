defmodule Soundboard.AudioPlayer.State do
  @moduledoc """
  The state of a per-guild audio player server.
  """

  defstruct [
    :guild_id,
    :voice_channel,
    :current_playback,
    :pending_request,
    :interrupting,
    :interrupt_watchdog_ref,
    :interrupt_watchdog_attempt,
    :idle_timeout_ref
  ]

  @type t :: %__MODULE__{
          guild_id: String.t(),
          voice_channel: {String.t(), String.t()} | nil,
          current_playback: map() | nil,
          pending_request: map() | nil,
          interrupting: boolean() | nil,
          interrupt_watchdog_ref: reference() | nil,
          interrupt_watchdog_attempt: non_neg_integer() | nil,
          idle_timeout_ref: {reference(), reference()} | nil
        }
end
