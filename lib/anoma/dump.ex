defmodule Anoma.Dump do
  @moduledoc """
  I dump current state of a supplied node and load the
  apporpriate file with info necessary to start a new node.

  We do not dump the clock so as to keep consistencies for the
  measuremenet of the future session.
  """

  alias Anoma.Mnesia
  alias Anoma.Node

  @doc """
  I dump the current state with storage. I accept a string as a name,
  so that the resulting file will be created as name.txt and then a
  node whose info presented as a tuple I dump as a binary.
  """
  def dump(name, node) do
    term = node |> get_all() |> :erlang.term_to_binary()

    File.open(name <> ".txt", [:write], fn file ->
      file |> IO.binwrite(term)
    end)
  end

  @doc """
  I read the given file which I assume contains binary info and convert
  it to an Elixir
  """
  def load(name) do
    {:ok, bin} = load_bin(name)
    :erlang.binary_to_term(bin)
  end

  @doc """
  I binread the given file which I assume contains binary info
  """
  def load_bin(name) do
    File.open(name, [:read], fn file ->
      file |> IO.binread(:all)
    end)
  end

  @doc """
  I get all the info on the node tables and engines in order:
  - logger
  - ordering
  - mempool
  - pinger
  - executor
  - qualified
  - order
  - block_storage

  And turn the info into a tuple
  """
  def get_all(node) do
    (get_state(node) ++ get_tables(node)) |> List.to_tuple()
  end

  @doc """
  I get the engine states in order:
  - router
  - logger
  - ordering
  - mempool
  - pinger
  - executor
  """
  def get_state(node) do
    state = node |> Node.state()
    router = state.router

    node =
      state
      |> Map.filter(fn {key, _value} ->
        key not in [
          :router,
          :mempool_topic,
          :executor_topic,
          :__struct__,
          :clock
        ]
      end)
      |> Map.to_list()

    list =
      node
      |> Enum.map(fn {atom, engine} ->
        {atom, module_match(atom).state(engine)}
      end)

    [{:router, router} | list]
  end

  @doc """
  I get the node tables in order:
  - storage (names)
  - qualified
  - order
  - block_storage

  via dirty dumping
  """
  def get_tables(node) do
    node = node |> Node.state()
    table = Anoma.Node.Storage.Ordering.state(node.ordering).table
    block = Anoma.Node.Mempool.state(node.mempool).block_storage
    qual = table.qualified
    ord = table.order

    {q, o, b} =
      [qual, ord, block]
      |> Enum.map(fn x ->
        unless Mnesia.dirty_dump(x) == [] do
          Mnesia.dirty_dump(x) |> two_car()
        else
          []
        end
      end)
      |> List.to_tuple()

    [storage: table, qualified: q, order: o, block_storage: b]
  end

  def module_match(address) do
    case address do
      :logger -> Anoma.Node.Logger
      :pinger -> Anoma.Node.Pinger
      :mempool -> Anoma.Node.Mempool
      :executor -> Anoma.Node.Executor
      :ordering -> Anoma.Node.Storage.Ordering
    end
  end

  def two_car(term) do
    term |> hd() |> hd()
  end
end