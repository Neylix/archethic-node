defmodule UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput do
  @enforce_keys [:amount, :from]
  defstruct [:amount, :from]

  @type t :: %__MODULE__{
          amount: float(),
          from: binary()
        }

  alias UnirisCore.Crypto

  @doc """
  Serialize unspent output into binary format

  ## Examples

        iex> UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput.serialize(
        ...>  %UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput{
        ...>    from: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
        ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        ...>    amount: 10.5
        ...>  }
        ...> )
        <<
        # From
        0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
        159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
        # Amount
        64, 37, 0, 0, 0, 0, 0, 0
        >>
  """
  @spec serialize(__MODULE__.t()) :: <<_::64, _::_*8>>
  def serialize(%__MODULE__{from: from, amount: amount}) do
    <<from::binary, amount::float>>
  end

  @doc """
  Deserialize an encoded unspent output

  ## Examples

    iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    ...> 64, 37, 0, 0, 0, 0, 0, 0
    ...> >>
    ...> |> UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput.deserialize()
    {
      %UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput{
        from: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
          159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 10.5
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
        from: <<hash_id::8>> <> address,
        amount: amount
      },
      rest
    }
  end
end
