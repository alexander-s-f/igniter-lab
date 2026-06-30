module AdvancedLogisticsExample
import AdvancedLogisticsTypes
import AdvancedLogisticsApi

-- Program entry point - zero-input route planning demo.
-- This companion fixture builds typed sample records and feeds the
-- production-like PlanDailyRoutes contract without introducing external IO.
entrypoint RunDailyRoutesDemo

pure contract MakeLocation {
  input x : Integer
  input y : Integer

  compute loc = { x: x, y: y }
  output loc : Location
}

pure contract MakePackage {
  input mass : Integer
  input volume : Integer

  compute pkg = { mass: mass, volume: volume }
  output pkg : Package
}

pure contract MakeTransport {
  input id : String
  input loc : Location
  input max_mass : Integer
  input max_vol : Integer
  input cur_mass : Integer
  input cur_vol : Integer

  compute transport = {
    id: id,
    loc: loc,
    max_mass: max_mass,
    max_vol: max_vol,
    cur_mass: cur_mass,
    cur_vol: cur_vol
  }
  output transport : Transport
}

pure contract MakeOrder {
  input id : String
  input client_loc : Location
  input pkg : Package

  compute order = { id: id, client_loc: client_loc, pkg: pkg }
  output order : Order
}

contract RunDailyRoutesDemo {
  compute depot_a = call_contract("MakeLocation", 0, 0)
  compute depot_b = call_contract("MakeLocation", 10, 10)
  compute client_a = call_contract("MakeLocation", 5, 7)
  compute client_b = call_contract("MakeLocation", 25, 9)

  compute van_a = call_contract("MakeTransport", "van-a", depot_a, 1000, 500, 100, 75)
  compute van_b = call_contract("MakeTransport", "van-b", depot_b, 500, 250, 50, 50)

  compute pkg_a = call_contract("MakePackage", 120, 40)
  compute pkg_b = call_contract("MakePackage", 700, 300)

  compute order_a = call_contract("MakeOrder", "ord-a", client_a, pkg_a)
  compute order_b = call_contract("MakeOrder", "ord-b", client_b, pkg_b)

  compute route_plans = call_contract("PlanDailyRoutes", [van_a, van_b], [order_a, order_b])
  output route_plans : Collection[Collection[Order]]
}
