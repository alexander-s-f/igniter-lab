-- stdlib_extension.ig
-- Conformance fixture verifying count, first, last, filter, sum, zip, and range.

module SparkCRM.Marketing

type Lead {
  lead_id: Integer,
  bid_amount: Integer,
  bid_decimal: Decimal[2]
}

type Pair {
  first: Integer,
  second: Integer
}

contract LeadConversionRate {
  input leads: Collection[Lead]
  input threshold: Integer

  compute total_high_value_bids =
    if count(leads) > 0 {
      if count(zip(range(0, count(leads)), range(0, count(leads)))) > 0 {
        if or_else(first(map(leads, l -> l.bid_amount)), 0) > 0 {
          if or_else(last(map(leads, l -> l.bid_amount)), 0) > 0 {
            sum(filter(leads, l -> l.bid_amount > threshold), :bid_decimal)
          } else {
            sum(leads, :bid_decimal)
          }
        } else {
          sum(leads, :bid_decimal)
        }
      } else {
        sum(leads, :bid_decimal)
      }
    } else {
      sum(leads, :bid_decimal)
    }

  output total_high_value_bids: Decimal[2]
}

contract AvgStandalone {
  input leads: Collection[Lead]
  compute val = avg(leads, :bid_decimal)
  output val: Option[Decimal[2]]
}

contract AvgOptimized {
  input leads: Collection[Lead]
  input threshold: Integer
  compute val = avg(filter(leads, l -> l.bid_amount > threshold), :bid_decimal)
  output val: Option[Decimal[2]]
}

contract MinStandalone {
  input leads: Collection[Lead]
  compute val = min(leads, :bid_decimal)
  output val: Option[Decimal[2]]
}

contract MinOptimized {
  input leads: Collection[Lead]
  input threshold: Integer
  compute val = min(filter(leads, l -> l.bid_amount > threshold), :bid_decimal)
  output val: Option[Decimal[2]]
}

contract MaxStandalone {
  input leads: Collection[Lead]
  compute val = max(leads, :bid_decimal)
  output val: Option[Decimal[2]]
}

contract MaxOptimized {
  input leads: Collection[Lead]
  input threshold: Integer
  compute val = max(filter(leads, l -> l.bid_amount > threshold), :bid_decimal)
  output val: Option[Decimal[2]]
}

contract TakeLeads {
  input leads: Collection[Lead]
  compute val = count(take(leads, 2))
  output val: Integer
}

contract FoldStandalone {
  input leads: Collection[Lead]
  compute val = fold(leads, 0, (acc, l) -> acc + l.bid_amount)
  output val: Integer
}

contract FoldOptimized {
  input leads: Collection[Lead]
  input threshold: Integer
  compute val = fold(filter(leads, l -> l.bid_amount > threshold), 0, (acc, l) -> acc + l.bid_amount)
  output val: Integer
}
