module Lab.IoCapability

observed contract MissingCapabilityIo {
  capability io_file_read: IO.Capability
  effect read_file using io_file_read

  -- Missing capability argument (only path is provided)
  compute result = stdlib.IO.read_text("test_dir/file.txt")
}
