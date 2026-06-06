module Lab.IoObservabilityE2e

observed contract ExecutionFailureEscape {
  capability io_read_cap: IO.Capability
  effect read_file using io_read_cap

  compute first_result = stdlib.IO.read_text("sub/../../escaped.txt", io_read_cap)
  output first_result: Result
}
