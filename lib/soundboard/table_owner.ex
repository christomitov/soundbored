defmodule Soundboard.TableOwner do
  @moduledoc """
  Owns the app's shared ETS tables (billing's processed events, Stripe
  customers and subscriptions, and the sound metadata cache).

  An ETS table dies with the process that created it. Webhooks and billing
  pages run in short-lived request processes, and audio players stop when
  idle, so tables are created by this supervised process instead and live as
  long as the application.
  """

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Makes sure every table in `tables` exists, owned by this process."
  @spec ensure_tables([atom()]) :: :ok
  def ensure_tables(tables) do
    if Enum.any?(tables, &(:ets.whereis(&1) == :undefined)) do
      GenServer.call(__MODULE__, {:ensure, tables})
    end

    :ok
  end

  @impl true
  def init(:ok), do: {:ok, :ok}

  @impl true
  def handle_call({:ensure, tables}, _from, state) do
    for table <- tables, :ets.whereis(table) == :undefined do
      :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
    end

    {:reply, :ok, state}
  end
end
