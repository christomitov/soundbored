defmodule Soundboard.Boundary do
  @moduledoc """
  The exception types that can realistically escape across a process or API
  boundary here: the Discord gateway (EDA), voice, HTTP, the file system and
  SQLite. Code rescues `e in @boundary_exceptions` rather than everything;
  exits and throws are caught separately.
  """

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
