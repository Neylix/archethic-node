defmodule UnirisCore.Transaction.ValidationStamp.LedgerOperations.TransactionMovement do
  @enforce_keys [:to, :amount]
  defstruct [:to, :amount]

  alias UnirisCore.Crypto

  @type t() :: %__MODULE__{
          to: binary(),
          amount: float()
        }

  @doc """
  Serialize a transaction movement into binary format

  ## Examples

        iex> UnirisCore.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.serialize(
        ...>  %UnirisCore.Transaction.ValidationStamp.LedgerOperations.TransactionMovement{
        ...>    to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
        ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        ...>    amount: 0.30
        ...>  }
        ...> )
        <<
        # Node public key
        0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
        159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
        # Amount
        63, 211, 51, 51, 51, 51, 51, 51
        >>
  """
  @spec serialize(__MODULE__.t()) :: <<_::64, _::_*8>>
  def serialize(%__MODULE__{to: to, amount: amount}) do
    <<to::binary, amount::float>>
  end

  @doc """
  Deserialize an encoded transaction movement

  ## Examples

    iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    ...> 63, 211, 51, 51, 51, 51, 51, 51
    ...> >>
    ...> |> UnirisCore.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.deserialize()
    {
      %UnirisCore.Transaction.ValidationStamp.LedgerOperations.TransactionMovement{
        to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
          159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 0.30
      },
      ""
    }
  """
  @spec deserialize(<<_::8, _::_*1>>) :: {__MODULE__.t(), bitstring}
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), amount::float, rest::bitstring>> = rest

    {
      %__MODULE__{
        to: <<hash_id::8>> <> address,
        amount: amount
      },
      rest
    }
  end
end
