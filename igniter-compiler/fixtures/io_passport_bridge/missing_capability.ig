module Lab.IoPassportBridge

observed contract MissingCapability {
  capability io_child_read: IO.Capability
  effect read_file using io_child_read

  compute result = stdlib.IO.read_text("test.txt")
}
