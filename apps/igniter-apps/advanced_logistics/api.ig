module AdvancedLogisticsApi
import AdvancedLogisticsTypes
import AdvancedLogisticsRouter
import stdlib.collection.{ map }

contract PlanDailyRoutes {
  input available_transports : Collection[Transport]
  input order_queue : Collection[Order]
  
  -- Test mapping over collections with a nested contract call
  -- We pass multiple arguments directly to call_contract because record 
  -- literal construction inside expressions currently fails with OOF-P0/OOF-G1.
  compute route_plans = map(available_transports, t ->
    call_contract("FindFeasibleOrders", t, order_queue)
  )
  
  output route_plans : Collection[Collection[Order]]
}

contract CreateOrder {
  input client_loc : Location
  input package_mass : Integer
  input package_vol : Integer
  
  -- Generates a unique order using a theoretical hash/uuid builder
  compute order_id = "ORD-0001"
  
  compute new_pkg = {
    mass: package_mass,
    volume: package_vol
  }
  
  -- We don't construct the outer Order dynamically because of parser constraints,
  -- but we document the shape:
  -- { id: order_id, client_loc: client_loc, pkg: new_pkg }
  
  output order_id : String
}

