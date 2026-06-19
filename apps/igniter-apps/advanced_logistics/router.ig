module AdvancedLogisticsRouter
import AdvancedLogisticsTypes
import AdvancedLogisticsSpatial
import stdlib.collection.{ filter }

contract FindFeasibleOrders {
  input transport : Transport
  input orders : Collection[Order]
  
  -- Filter orders to only those that can individually fit into the current transport capacity.
  -- We inline the capacity check to avoid lambda inline record parsing ambiguities.
  compute feasible = filter(orders, order -> 
    if (transport.cur_mass + order.pkg.mass) < transport.max_mass {
      (transport.cur_vol + order.pkg.volume) < transport.max_vol
    } else {
      false
    }
  )
  
  output feasible : Collection[Order]
}

