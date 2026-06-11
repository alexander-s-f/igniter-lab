# ERP Logistics Engine (Domain Pressure Test)

This directory contains a prototype multi-file Igniter application modeling an ERP Logistics and Transport optimization engine.

## Domain Model
The ERP system models common enterprise requirements:
- **Structural Entities:** `Warehouse`, `Shipment`, and `Route` records (`types.ig`).
- **Invariant Checking:** `CheckCapacity` ensures shipments fit into available warehouse limits (`warehouse.ig`).
- **Optimization:** `CalculateBestRoute` iterates over `Collection[Route]` to find the minimum transit cost (`optimizer.ig`).
- **Orchestration:** `DispatchShipment` links the contracts together.

## Execution
This prototype successfully proved that the Rust compiler **does** support `TypeEnv` and `contract` cross-file resolution when the source files are grouped into a single command invocation.

**Run the multi-file compilation:**
```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/erp_logistics/types.ig ../igniter-apps/erp_logistics/warehouse.ig ../igniter-apps/erp_logistics/api.ig --out /tmp/erp_logistics.igapp
```

See [REPORT.md](./REPORT.md) for the critical compiler boundary findings uncovered by this test.
