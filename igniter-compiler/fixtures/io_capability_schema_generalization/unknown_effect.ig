module Lab.IoCapabilitySchemaGeneralization

observed contract UnknownEffect {
  capability io_child_read: IO.Capability
  effect hack_system using io_child_read

  compute result = stdlib.IO.read_text("test.txt", io_child_read)
}
