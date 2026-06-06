module Lab.IoPassportBridge

observed contract WriteEscalation {
  capability io_child_write: IO.Capability
  effect write_file using io_child_write

  compute result = stdlib.IO.write_text("sub/test.txt", "escalated content", io_child_write)
}
