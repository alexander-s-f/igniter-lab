module T3E
size_relation Collection sub
recursive contract UserRelation {
  input items: Collection[Integer]
  compute result = recur(items.sub)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
