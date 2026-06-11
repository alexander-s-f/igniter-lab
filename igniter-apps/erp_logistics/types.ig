module ErpTypes

type Warehouse {
  id : Text
  capacity : Float
  current_load : Float
}

type Route {
  origin : Text
  dest : Text
  cost_per_kg : Float
}

type Shipment {
  id : Text
  origin : Text
  dest : Text
  weight : Float
}
