module Lab.IoCapability

observed contract UnknownCapabilityIo {
  capability io_file_read: IO.Capability
  effect read_file using io_file_read

  -- Undeclared capability reference (io_file_write)
  compute result = stdlib.IO.read_text("test_dir/file.txt", io_file_write)
}
