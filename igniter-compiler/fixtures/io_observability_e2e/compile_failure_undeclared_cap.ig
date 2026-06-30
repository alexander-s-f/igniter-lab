module Lab.IoObservabilityE2e

observed contract CompileFailureUndeclaredCap {
  effect read_file using non_existent_cap
}
