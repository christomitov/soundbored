# Dialyzer false positives kept out of `mix ci`.
# Each entry: {file, warning_type}.
[
  # persistent_term.get(:soundboard_bot_ready, false) is inferred as always
  # `true` because the only put-site stores `true`; the `false` default is
  # reachable at runtime before READY.
  {"lib/soundboard/discord/handler/voice_commands.ex", :pattern_match}
]
