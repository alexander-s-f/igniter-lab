module BookkeepingLedger
import BookkeepingTypes

contract VerifyBalancing {
  input tx : Transaction

  compute debits = filter(tx.postings, p -> p.direction == "Debit")
  compute debit_amounts = map(debits, p -> p.amount)
  compute total_debits = sum(debit_amounts)

  compute credits = filter(tx.postings, p -> p.direction == "Credit")
  compute credit_amounts = map(credits, p -> p.amount)
  compute total_credits = sum(credit_amounts)

  compute is_balanced = total_debits == total_credits

  output is_balanced : Bool
}

contract ComputeAccountBalance {
  input txs : Collection[Transaction]
  input target_account_id : Text

  -- We need to flat_map transactions to postings, but flat_map on collection might not exist.
  -- Or just fold over transactions.
  compute total = fold(txs, 0.00, (acc, tx) -> acc + 0.00) -- DUMMY to see if closure parser fails
  
  output total : Decimal[2]
}
