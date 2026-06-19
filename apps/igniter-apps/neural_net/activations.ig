module NeuralNetActivations
import NeuralNetTypes

-- ============================================================
-- Activation Functions (Fixed Point Arithmetic)
-- ============================================================

contract ReLU {
  input x : Integer

  -- ReLU: max(0, x)
  compute activated = if x > 0 { x } else { 0 }

  output activated : Integer
}

contract SigmoidApprox {
  input x : Integer

  -- Hard Sigmoid Approximation for Fixed-Point integer arithmetic
  -- If scale is 1000:
  -- x < -2500 => 0
  -- x > 2500  => 1000
  -- else => (x / 5) + 500
  
  compute activated = if x < (0 - 2500) {
    0
  } else {
    if x > 2500 {
      1000
    } else {
      (x / 5) + 500
    }
  }

  output activated : Integer
}
