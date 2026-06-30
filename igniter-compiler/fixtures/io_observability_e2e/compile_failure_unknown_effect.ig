module Lab.IoObservabilityE2e

observed contract CompileFailureUnknownEffect {
  capability io_cap: IO.Capability
  effect unrecognized_hack_effect using io_cap
}
