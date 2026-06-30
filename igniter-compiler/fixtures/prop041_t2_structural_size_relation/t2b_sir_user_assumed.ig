module T2B
size_relation PageList items_left

type PageList {
  items_left: PageList
}

recursive contract SirUserAssumed {
  input pages: PageList
  compute out = recur(pages.items_left)
  output out: Integer
  decreases pages.items_left
  max_steps 100
}
