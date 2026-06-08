module T2G
recursive contract T1MultiArg {
  input n: Integer
  input acc: Integer
  compute result = recur(n - 1, acc)
  output result: Integer
  decreases n
  max_steps 200
}
