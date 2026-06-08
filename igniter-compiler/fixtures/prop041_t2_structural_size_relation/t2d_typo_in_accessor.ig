module T2D

size_relation DataList remaining

type DataList {
  remaining: DataList
  remainng: DataList
}

recursive contract TypoInAccessor {
  input data: DataList
  compute result = recur(data.remainng)
  output result: Integer
  decreases data.remainng
  max_steps 100
}
