module T2H
recursive contract WrongVariantArg {
  input n: Integer
  input m: Integer
  compute result = recur(m - 1, n)
  output result: Integer
  decreases n
  max_steps 100
}
