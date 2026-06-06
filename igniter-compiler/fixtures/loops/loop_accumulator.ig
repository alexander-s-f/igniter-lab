module W1

contract LoopContract {
  input items: Array[Integer]

  compute total = 0

  loop Accumulate in items max_steps: 1000 {
    compute total = total + item
  }

  output total: Integer
}
