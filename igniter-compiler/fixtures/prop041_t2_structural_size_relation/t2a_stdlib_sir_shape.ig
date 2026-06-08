module T2A
recursive contract StdlibSirShape {
  input xs: Collection[Integer]
  compute out = recur(xs.tail)
  output out: Integer
  decreases xs.tail
  max_steps 50
}
