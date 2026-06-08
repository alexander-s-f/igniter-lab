module T2F
type ItemBatch {
  count: Integer
}

recursive contract CountAccessor {
  input batch: ItemBatch
  compute result = recur(batch)
  output result: Integer
  decreases batch.count
  max_steps 100
}
