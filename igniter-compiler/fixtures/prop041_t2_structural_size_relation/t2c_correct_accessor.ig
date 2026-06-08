module T2C

size_relation ChainList tail_ref

type ChainList {
  tail_ref: ChainList
}

recursive contract CorrectAccessor {
  input chain: ChainList
  compute result = recur(chain.tail_ref)
  output result: Integer
  decreases chain.tail_ref
  max_steps 100
}
