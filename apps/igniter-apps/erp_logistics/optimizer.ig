module ErpOptimizer
import ErpTypes

contract CalculateBestRoute {
  input shipment : Shipment
  input routes : Collection[Route]

  compute matching_routes = filter(routes, r -> 
    if r.origin == shipment.origin {
      r.dest == shipment.dest
    } else {
      false
    }
  )

  -- Find the minimum cost. We'll use a fold with a high initial value.
  compute best_cost = fold(matching_routes, 999999.0, (acc, r) -> 
    if r.cost_per_kg < acc {
      r.cost_per_kg
    } else {
      acc
    }
  )

  compute total_cost = best_cost * shipment.weight

  output total_cost : Float
}
