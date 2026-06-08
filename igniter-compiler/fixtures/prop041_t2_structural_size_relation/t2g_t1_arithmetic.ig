module T2G
recursive contract T1Arithmetic {
  input n: Integer
  compute result = recur(n - 1)
  output result: Integer
  decreases n
  max_steps 100
}
