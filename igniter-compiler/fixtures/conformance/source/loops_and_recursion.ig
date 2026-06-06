-- loops_and_recursion.ig
-- Parser and Typechecker verification for loops and recursion

module Lang.Examples.LoopsAndRecursion

def factorial(n: Integer, acc: Integer) -> Integer decreases fuel {
  if n == 0 {
    acc
  } else {
    factorial(n - 1, acc * n)
  }
}

contract LoopTester {
  input pending_leads: Array[Integer]
  
  compute sum = 0
  
  loop ProcessLeads in pending_leads max_steps: 100 {
    compute sum = sum + item
  }
  
  loop tick in clock.every(5.seconds) {
    compute tick_time = tick.time
  }

  output sum: Integer
}
