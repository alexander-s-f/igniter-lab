module AdvancedLogisticsSpatial
import AdvancedLogisticsTypes

contract CalculateDistance {
  input a : Location
  input b : Location
  
  -- Squared Euclidean distance to avoid sqrt
  compute dx = a.x - b.x
  compute dy = a.y - b.y
  compute sq_dist = (dx * dx) + (dy * dy)
  
  output sq_dist : Integer
}

