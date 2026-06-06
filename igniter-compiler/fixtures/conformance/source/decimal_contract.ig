-- decimal_contract.ig
-- Parser acceptance fixture: Decimal[N] type annotations.
-- Grammar version: decimal-v0
-- Note: stdlib.decimal.* qualified calls are expression-level; this fixture
-- proves Decimal[N] type annotation parsing only. Operator resolution is
-- a classifier-level concern (decimal-classifier-v0).

module SparkCRM.Finance

contract BidSummary {
  input  base_bid:  Decimal[2]
  input  tax_rate:  Decimal[4]

  compute gross_bid = mul(base_bid, tax_rate)

  output gross_bid: Decimal[2]
}
