module BookkeepingApi
import BookkeepingTypes
import BookkeepingLedger

contract PostTransaction {
  input tx : Transaction

  compute is_balanced = call_contract("VerifyBalancing", tx)

  compute outcome = if is_balanced {
    ok(tx)
  } else {
    err("Transaction is not balanced")
  }

  output outcome : Result[Transaction, Text]
}
