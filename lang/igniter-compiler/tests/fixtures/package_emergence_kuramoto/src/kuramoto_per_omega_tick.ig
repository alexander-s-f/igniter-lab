module Emergence.KuramotoPerOmega

-- Per-oscillator natural frequency ω_i — REQUIRED for a real phase transition (distributed ω means coupling
-- competes with frequency spread, so the order parameter r is nontrivial). Input is Collection[Oscillator]
-- (records carry θ AND ω); record-field access (o.theta / o.omega / x.theta) inside the per-oscillator map
-- lambda AND the nested all-to-all coupling map+sum both EXECUTE — unblocked by
-- LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3.
--
-- One explicit-Euler step:  θ_i' = θ_i + dt·(ω_i + (K/N)·Σ_j sin(θ_j − θ_i)).
--
-- This package fixture deliberately keeps the tick output as Collection[Float] (new θ_i only). The external
-- driver owns constant ω_i and re-pairs {θ', ω} into the next `nodes` input, which keeps the packaged kernel
-- narrow and mirrors the public emergence reference flow.
type Oscillator { theta : Float  omega : Float }

pure contract Tick {
  input nodes : Collection[Oscillator]
  input k_over_n : Float
  input dt : Float
  compute next_theta : Collection[Float] = map(nodes, o -> o.theta + (dt * (o.omega + (k_over_n * sum(map(nodes, x -> sin(x.theta - o.theta)))))))
  output next_theta : Collection[Float]
}
