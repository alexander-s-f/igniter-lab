module Lab.IoCapabilitySchemaGeneralization

observed contract TwoCapabilities {
  capability io_first_read: IO.Capability
  effect read_file using io_first_read

  capability io_second_read: IO.Capability
  effect read_json using io_second_read

  compute first_result = stdlib.IO.read_text("sub/first.txt", io_first_read)
  compute second_result = stdlib.IO.read_text("sub/second.txt", io_second_read)
}
