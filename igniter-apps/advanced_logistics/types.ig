module AdvancedLogisticsTypes

type Location {
  x : Integer
  y : Integer
}

type Warehouse {
  id : String
  loc : Location
}

type Package {
  mass : Integer
  volume : Integer
}

type Transport {
  id : String
  loc : Location
  max_mass : Integer
  max_vol : Integer
  cur_mass : Integer
  cur_vol : Integer
}

type Order {
  id : String
  client_loc : Location
  pkg : Package
}

type RoutePlan {
  transport_id : String
  order_ids : Collection[String]
}

