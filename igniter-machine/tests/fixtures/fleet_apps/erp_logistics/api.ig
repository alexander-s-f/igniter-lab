module ErpApi
import ErpTypes
import ErpWarehouse

contract DispatchShipment {
  input warehouse : Warehouse
  input shipment : Shipment

  -- Test cross-file contract resolution (CheckCapacity is in ErpWarehouse)
  compute capacity_ok = call_contract("CheckCapacity", shipment)

  output capacity_ok : Bool
}
