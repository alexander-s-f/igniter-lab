module T3F
recursive contract T1Simple {
  input n: Integer
  compute result = recur(n - 1)
  output result: Integer
  decreases n
  max_steps 100
}
