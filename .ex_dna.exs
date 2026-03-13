%{
  min_mass: 25,
  ignore: ["lib/soundboard_web/templates/**"],
  excluded_macros: [:@, :schema, :pipe_through, :plug],
  normalize_pipes: true
}
