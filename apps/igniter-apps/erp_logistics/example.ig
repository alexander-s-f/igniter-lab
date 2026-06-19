module ErpExample
import ErpTypes
import ErpWarehouse
import ErpOptimizer
import ErpApi

-- Program entry point — the best-route optimization is the default run
-- target. This is a companion runtime fixture (zero external IO): it builds
-- typed sample records and feeds them to the production-like contracts so the
-- VM can exercise the app without external `warehouse` / `shipment` /
-- `routes` inputs. The production contracts (CheckCapacity,
-- CalculateBestRoute, DispatchShipment) are untouched.
--
-- RunBestRoute is the chosen entry because it runs end-to-end on the VM
-- (filter + fold + Float comparison/multiply). The capacity scenarios below
-- compile dual-clean but surface ERP-P11 (see registry): the VM's direct,
-- non-fold Float comparison opcode is still Integer-only, so `shipment.weight
-- < 1000.0` traps at runtime even though Float `*`/`+` and in-fold Float `<`
-- already work. That is a VM gap, not an app defect.
--
-- PRESSURE ERP-P09: only ONE bare `entrypoint` is expressible today;
-- RunBestRoute / RunCapacity / RunDispatchDemo each want to be a named
-- PROP-029 run-profile (panel preset with its own args/output/default).
entrypoint RunBestRoute

-- ── Factories ───────────────────────────────────────────────
-- PRESSURE ERP-P10: factories take typed inputs and build the record from
-- them. A String literal is accepted as a Text *argument* at a call site
-- (ch3 §3.x), but is NOT accepted in record-field position
-- (`field 'id' expects Text, got String`), so an inline literal record
-- cannot be built directly. A record-literal / entity surface (or extending
-- the String->Text coercion to field position) would remove these factories.

pure contract MakeWarehouse {
  input id : Text
  input capacity : Float
  input current_load : Float

  compute w = { id: id, capacity: capacity, current_load: current_load }
  output w : Warehouse
}

pure contract MakeShipment {
  input id : Text
  input origin : Text
  input dest : Text
  input weight : Float

  compute s = { id: id, origin: origin, dest: dest, weight: weight }
  output s : Shipment
}

pure contract MakeRoute {
  input origin : Text
  input dest : Text
  input cost_per_kg : Float

  compute r = { origin: origin, dest: dest, cost_per_kg: cost_per_kg }
  output r : Route
}

-- ── Scenario: orchestrator capacity check (ERP-P11 evidence) ─
-- Mirrors DispatchShipment: links a warehouse + shipment through the
-- cross-file CheckCapacity invariant (weight 750.0 < 1000.0 -> true).
-- Compiles dual-closure-clean but TRAPS at the VM on `shipment.weight <
-- 1000.0`: the direct (non-fold) Float comparison opcode is still
-- Integer-only. Kept as routed pressure evidence, not the run target.
contract RunDispatchDemo {
  compute warehouse = call_contract("MakeWarehouse", "WH-MIA", 5000.0, 1200.0)
  compute shipment = call_contract("MakeShipment", "SHP-1", "MIA", "JFK", 750.0)
  compute capacity_ok = call_contract("DispatchShipment", warehouse, shipment)
  output capacity_ok : Bool
}

-- ── Scenario: capacity invariant in isolation (ERP-P11) ─────
-- Same VM direct-Float-comparison trap as RunDispatchDemo.
contract RunCapacity {
  compute shipment = call_contract("MakeShipment", "SHP-1", "MIA", "JFK", 750.0)
  compute is_valid = call_contract("CheckCapacity", shipment)
  output is_valid : Bool
}

-- ── Scenario: best-route optimization ───────────────────────
-- Exercises filter + fold + Float comparison/multiplication: two MIA->JFK
-- routes (4.5, 3.25) and one off-lane MIA->LAX. matching_routes keeps the
-- two MIA->JFK lanes, best_cost folds to 3.25, total_cost = 3.25 * 750.0.
contract RunBestRoute {
  compute shipment = call_contract("MakeShipment", "SHP-1", "MIA", "JFK", 750.0)
  compute r1 = call_contract("MakeRoute", "MIA", "JFK", 4.5)
  compute r2 = call_contract("MakeRoute", "MIA", "JFK", 3.25)
  compute r3 = call_contract("MakeRoute", "MIA", "LAX", 2.0)
  compute routes = [r1, r2, r3]

  compute total_cost = call_contract("CalculateBestRoute", shipment, routes)
  output total_cost : Float
}
