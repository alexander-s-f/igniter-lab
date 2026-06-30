module Lab.IoObservabilityE2e

observed contract ExecutionFailureAmbient {
  capability io_read_cap: IO.Capability
  effect read_file using io_read_cap

  compute first_result = stdlib.IO.read_text("sub/first.txt", io_read_cap)
  output first_result: Result
}
