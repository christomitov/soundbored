[
  # Ignore warnings from external dependencies if needed
  # The Discord handler warning is a false positive from the Nostrum library behavior
  {"lib/soundboard_web/discord_handler.ex", :pattern_match},
  # Ecto.Multi is an opaque type; Dialyzer flags Multi.update as call_without_opaque here
  {"lib/soundboard_web/live/file_handler.ex", :call_without_opaque}
]
