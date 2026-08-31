# `Soundboard.Volume`

Helpers for working with volume percentages and decimal ratios.

# `percent`

```elixir
@type percent() :: 0..150
```

# `clamp_percent`

```elixir
@spec clamp_percent(number()) :: percent()
```

# `decimal_to_percent`

```elixir
@spec decimal_to_percent(number() | nil) :: percent()
```

# `normalize_percent`

```elixir
@spec normalize_percent(String.t() | number() | nil, percent()) :: percent()
```

# `percent_to_decimal`

```elixir
@spec percent_to_decimal(String.t() | number() | nil) :: float()
```

# `percent_to_decimal`

```elixir
@spec percent_to_decimal(String.t() | number() | nil, percent()) :: float()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
