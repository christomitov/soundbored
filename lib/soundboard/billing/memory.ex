defmodule Soundboard.Billing.Memory do
  @moduledoc """
  Owns billing's in-memory ETS tables (processed event ids, Stripe customer
  ids, cached subscriptions).

  An ETS table dies with the process that created it, and webhooks and
  billing pages run in short-lived request processes, so the tables are
  created by this long-lived process instead. It is started on first use,
  unlinked from the caller, so a request ending never takes it down.
  """

  use GenServer

  @doc "Starts the owner (once) and makes sure every table in `tables` exists."
  @spec ensure_tables([atom()]) :: :ok
  def ensure_tables(tables) do
    if Enum.any?(tables, &(:ets.whereis(&1) == :undefined)) do
      GenServer.call(owner(), {:ensure, tables})
    end

    :ok
  end

  defp owner do
    case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
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
