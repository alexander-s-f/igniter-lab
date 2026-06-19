module T2G
fuel_bounded contract T1FuelBounded {
  input n: Integer
  compute result = recur(n)
  output result: Integer
  max_steps 100
}
