# Advanced Logistics

This is a complex logistics application built to test the Igniter compiler and language design under multi-file, domain-driven pressure.

## Architecture

The application is split into four modules:
1. **AdvancedLogisticsTypes (`types.ig`)**: Defines structural records representing the logistics domain (`Warehouse`, `Transport`, `Order`, `Package`, `Location`, `RoutePlan`).
2. **AdvancedLogisticsSpatial (`spatial.ig`)**: Handles spatial math. Currently computes squared Euclidean distance to avoid requiring a `sqrt` function which is absent from the standard library.
3. **AdvancedLogisticsRouter (`router.ig`)**: Contains the core logic for filtering and verifying constraints. `FindFeasibleOrders` ensures that a transport's mass and volume capacities are strictly enforced using the `if` expression syntax.
4. **AdvancedLogisticsApi (`api.ig`)**: The outer layer containing the system's entry points (`PlanDailyRoutes` and `CreateOrder`). 

## Compilation

To compile the application, all files must be passed to the compiler together. However, due to missing actual standard library implementations (`stdlib.collection`), the compiler will halt at the `multifile_resolve` stage. A mock `stdlib_collection.ig` can be provided to advance the compilation to `typecheck`.

```bash
cargo run -- compile types.ig spatial.ig router.ig api.ig
```

See [report.md](./report.md) for the current compiler boundary findings. For the compact routing table, see [PRESSURE_REGISTRY.md](./PRESSURE_REGISTRY.md).
