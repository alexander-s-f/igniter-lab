module Lab.IoObservabilityE2e

observed contract PositiveDelegated {
  capability io_read_cap: IO.Capability
  effect read_file using io_read_cap

  capability io_write_cap: IO.Capability
  effect write_file using io_write_cap

  compute first_result = stdlib.IO.read_text("sub/first.txt", io_read_cap)
  compute second_result = stdlib.IO.write_text("sub/second.txt", "observability payload", io_write_cap)
  output first_result: Result
  output second_result: Result
}
