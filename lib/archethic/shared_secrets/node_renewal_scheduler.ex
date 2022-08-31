defmodule Archethic.SharedSecrets.NodeRenewalScheduler do
  @moduledoc """
  Schedule the renewal of node shared secrets

  At each `interval`, a new node shared secrets transaction is created with
  the new authorized nodes and is broadcasted to the validation nodes to include
  them as new authorized nodes and update the daily nonce seed.
  """

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Archethic

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  alias Archethic.SharedSecrets.NodeRenewal

  alias Archethic.Utils
  alias Archethic.Utils.DetectNodeResponsiveness

  require Logger

  use GenStateMachine, callback_mode: :handle_event_function

  @doc """
  Start the node renewal scheduler process without starting the scheduler

  Options:
  - interval: Cron like interval when the node renewal will occur
  """
  @spec start_link(
          args :: [interval: binary()],
          opts :: Keyword.t()
        ) ::
          {:ok, pid()}
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenStateMachine.start_link(__MODULE__, args, opts)
  end

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)
    PubSub.register_to_node_update()

    Logger.info("Starting Node Renewal Scheduler")

    case Crypto.first_node_public_key() |> P2P.get_node_info() |> elem(1) do
      %Node{authorized?: true, available?: true} ->
        PubSub.register_to_new_transaction_by_type(:node_shared_secrets)
        Logger.info("Node Renewal Scheduler: Scheduled during init")

        key_index = Crypto.number_of_node_shared_secrets_keys()

        {:ok, :idle, %{interval: interval, index: key_index},
         [{:next_event, :internal, :schedule}]}

      _ ->
        Logger.info("Node Renewal Scheduler: Scheduler waiting for Node Update Message")

        {:ok, :idle, %{interval: interval}}
    end
  end

  def handle_event(:internal, :schedule, _state, data = %{interval: interval, index: index}) do
    timer =
      case Map.get(data, :timer) do
        nil ->
          schedule_renewal_message(interval)

        timer ->
          Process.cancel_timer(timer)
          schedule_renewal_message(interval)
      end

    Logger.info(
      "Node shared secrets will be renewed in #{Utils.remaining_seconds_from_timer(timer)} seconds"
    )

    new_data =
      data
      |> Map.put(:timer, timer)
      |> Map.put(:next_address, NodeRenewal.next_address(index))

    {:next_state, :scheduled, new_data}
  end

  def handle_event(
        :info,
        {:node_update,
         %Node{first_public_key: first_public_key, authorized?: true, available?: true}},
        :idle,
        data
      ) do
    if first_public_key == Crypto.first_node_public_key() do
      key_index = Crypto.number_of_node_shared_secrets_keys()
      PubSub.register_to_new_transaction_by_type(:node_shared_secrets)
      Logger.info("Start node shared secrets scheduling - (index: #{key_index})")

      new_data =
        data
        |> Map.put(:index, key_index)

      {:keep_state, new_data, {:next_event, :internal, :schedule}}
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:node_update,
         %Node{first_public_key: first_public_key, authorized?: true, available?: false}},
        state,
        data
      )
      when state != nil do
    if first_public_key == Crypto.first_node_public_key() do
      PubSub.unregister_to_new_transaction_by_type(:node_shared_secrets)

      case Map.pop(data, :timer) do
        {nil, _} ->
          {:next_state, :idle, data}

        {timer, new_data} ->
          Process.cancel_timer(timer)
          {:next_state, :idle, new_data}
      end
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:node_update, %Node{first_public_key: first_public_key, authorized?: false}},
        state,
        data
      )
      when state != :idle do
    if first_public_key == Crypto.first_node_public_key() do
      PubSub.unregister_to_new_transaction_by_type(:node_shared_secrets)

      case Map.pop(data, :timer) do
        {nil, _} ->
          {:next_state, :idle, data}

        {timer, new_data} ->
          Process.cancel_timer(timer)
          {:next_state, :idle, new_data}
      end
    else
      :keep_state_and_data
    end
  end

  def handle_event(:info, {:node_update, _}, _, _), do: :keep_state_and_data

  def handle_event(:info, :make_renewal, :scheduled, data) do
    {:next_state, :triggered, data, {:next_event, :internal, :make_renewal}}
  end

  def handle_event(:internal, :make_renewal, :triggered, data = %{index: index}) do
    Logger.debug("Node shared secrets renewal at - #{index}")

    tx =
      NodeRenewal.next_authorized_node_public_keys()
      |> NodeRenewal.new_node_shared_secrets_transaction(
        :crypto.strong_rand_bytes(32),
        :crypto.strong_rand_bytes(32),
        index
      )

    if NodeRenewal.initiator?(tx.address) do
      Logger.info("Node shared secrets renewal creation...")
      make_renewal(tx)
      {:keep_state, data}
    else
      {:ok, pid} =
        DetectNodeResponsiveness.start_link(tx.address, fn count ->
          if NodeRenewal.initiator?(tx.address, count) do
            Logger.info("Node shared secret renewal creation...attempt #{count}")
            make_renewal(tx)
          end
        end)

      Process.monitor(pid)

      {:keep_state, Map.put(data, :node_detection, pid)}
    end
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _reason},
        :triggered,
        data = %{node_detection: watcher_pid}
      )
      when pid == watcher_pid do
    {:keep_state, Map.delete(data, :node_detection), {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, _pid, _reason},
        :scheduled,
        data
      ) do
    {:keep_state, Map.delete(data, :node_detection)}
  end

  #

  def handle_event(
        :info,
        {:new_transaction, address, :node_shared_secrets, _timestamp},
        :triggered,
        data = %{next_address: next_address}
      )
      when next_address == address do
    case Map.get(data, :watcher) do
      nil ->
        :ignore

      pid ->
        Process.exit(pid, :normal)
    end

    new_data = Map.update!(data, :index, &(&1 + 1))
    {:next_state, :confirmed, new_data, {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:new_transaction, address, :node_shared_secrets, _timestamp},
        :scheduled,
        data = %{next_address: next_address}
      ) do
    # We prevent non scheduled transactions to change
    new_data =
      if next_address == address do
        Map.update!(data, :index, &(&1 + 1))
      else
        data
      end

    Logger.debug(
      "Reschedule renewal after reception of node shared secrets transaction in scheduled state instead of triggered state - (index: #{new_data.index})"
    )

    {:keep_state, new_data, {:next_event, :internal, :schedule}}
  end

  def handle_event(:cast, {:new_conf, conf}, _state, data) do
    case Keyword.get(conf, :interval) do
      nil ->
        :keep_state_and_data

      new_interval ->
        {:keep_state, Map.put(data, :interval, new_interval)}
    end
  end

  defp make_renewal(tx) do
    Archethic.send_new_transaction(tx)

    Logger.info(
      "Node shared secrets renewal transaction sent (#{Crypto.number_of_node_shared_secrets_keys()})"
    )
  end

  defp schedule_renewal_message(interval) do
    Process.send_after(self(), :make_renewal, Utils.time_offset(interval) * 1000)
  end

  def config_change(nil), do: :ok

  def config_change(changed_config) do
    GenStateMachine.cast(__MODULE__, {:new_conf, changed_config})
  end

  @doc """
  Get the next shared secrets application date from a given date
  """
  @spec next_application_date(DateTime.t()) :: DateTime.t()
  def next_application_date(date_from = %DateTime{}) do
    get_application_date_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp get_application_date_interval do
    Application.get_env(:archethic, __MODULE__)
    |> Keyword.fetch!(:application_interval)
  end
end
