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

  -- Decimal money path: seed and accumulate with the explicit Decimal constructor
  -- (LAB-NUMERIC-DECIMAL-CONSTRUCT-P1) so the fold stays entirely in Decimal[2] and
  -- never touches Float. decimal(0, 2) is zero in exact minor units at scale two.
  -- (Accumulator shape is the original placeholder fold; not a balance-logic rewrite.)
  compute total = fold(txs, decimal(0, 2), (acc, tx) -> acc + decimal(0, 2))

  output total : Decimal[2]
}
