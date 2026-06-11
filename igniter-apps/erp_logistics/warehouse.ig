module ErpWarehouse
import ErpTypes

contract CheckCapacity {
  input shipment : Shipment

  compute is_valid = shipment.weight < 1000.0

  output is_valid : Bool
}
