defmodule Archethic.SelfRepair.Sync.TransactionHandlerTest do
  use ArchethicCase

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.Subset, as: BeaconSubset

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Sync.TransactionHandler
  alias Archethic.SharedSecrets.MemTables.NetworkLookup

  alias Archethic.TransactionFactory

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionSummary

  doctest TransactionHandler

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))

    welcome_node = %Node{
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB",
      reward_address: :crypto.strong_rand_bytes(32),
      enrollment_date: DateTime.utc_now()
    }

    coordinator_node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: :crypto.strong_rand_bytes(32),
      enrollment_date: DateTime.utc_now()
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        reward_address: :crypto.strong_rand_bytes(32),
        authorization_date: DateTime.utc_now()
      }
    ]

    Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    {:ok,
     %{
       welcome_node: welcome_node,
       coordinator_node: coordinator_node,
       storage_nodes: storage_nodes
     }}
  end

  test "download_transaction?/1 should return true when the node is a chain storage node" do
    assert true =
             TransactionHandler.download_transaction?(%TransactionSummary{
               address: "@Alice2"
             })
  end

  test "download_transaction/2 should download the transaction" do
    inputs = [
      %TransactionInput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
    ]

    tx = TransactionFactory.create_valid_transaction(inputs)

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, tx}
    end)

    tx_summary = %TransactionSummary{address: "@Alice2", timestamp: DateTime.utc_now()}
    assert ^tx = TransactionHandler.download_transaction(tx_summary, "AAA")
  end

  test "process_transaction/1 should handle the transaction and replicate it" do
    me = self()

    inputs = [
      %TransactionInput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
    ]

    tx = TransactionFactory.create_valid_transaction(inputs)
    tx_address = tx.address

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{address: ^tx_address}, _ ->
        {:ok, tx}

      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionInputs{}, _ ->
        {:ok, %TransactionInputList{inputs: inputs}}

      _, %GetUnspentOutputs{}, _ ->
        {:ok, %UnspentOutputList{unspent_outputs: inputs}}

      _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: []}}
    end)

    MockDB
    |> stub(:write_transaction, fn ^tx ->
      send(me, :transaction_replicated)
      :ok
    end)

    assert :ok = TransactionHandler.process_transaction(tx)

    assert_received :transaction_replicated
  end
end