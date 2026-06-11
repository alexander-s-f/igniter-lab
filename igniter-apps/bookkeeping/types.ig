module BookkeepingTypes

type Posting {
  account_id : Text,
  amount     : Decimal[2],
  direction  : Text
}

type Transaction {
  id       : Text,
  date     : Text,
  postings : Collection[Posting]
}

type Account {
  id   : Text,
  name : Text,
  type : Text
}
