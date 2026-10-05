defmodule Soundboard.Boundary do
  @moduledoc false

  # Exception types that can realistically escape across process/API boundaries
  # in this app (Discord gateway via EDA, voice, HTTP, file system, SQLite).
  # Used with `rescue e in @boundary_exceptions` instead of bare `rescue`;
  # exits and throws are handled separately with `catch`.
  @exceptions [
    RuntimeError,
    ArgumentError,
    KeyError,
    MatchError,
    CaseClauseError,
    WithClauseError,
    TryClauseError,
    FunctionClauseError,
    UndefinedFunctionError,
    BadMapError,
    BadBooleanError,
    Protocol.UndefinedError,
    ArithmeticError,
    ErlangError,
    File.Error,
    File.CopyError,
    Exqlite.Error,
    HTTPoison.Error
  ]

  def exceptions, do: @exceptions
end
