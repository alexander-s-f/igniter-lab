module Emergence.LocalMultinodeKuramoto

type Oscillator { theta : Float omega : Float }
type NeighborPhase { theta : Float weight : Float }

pure contract NodeTick {
  input self : Oscillator
  input neighbors : Collection[NeighborPhase]
  input k : Float
  input dt : Float
  compute coupling : Float = sum(map(neighbors, n -> n.weight * det_sin(n.theta - self.theta)))
  compute next_theta : Float = self.theta + (dt * (self.omega + (k * coupling)))
  output next_theta : Float
}
