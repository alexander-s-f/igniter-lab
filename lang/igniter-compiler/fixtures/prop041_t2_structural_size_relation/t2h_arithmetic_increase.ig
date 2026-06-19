module T2H
recursive contract ArithmeticIncrease {
  input n: Integer
  compute result = recur(n + 5)
  output result: Integer
  decreases n
  max_steps 100
}
