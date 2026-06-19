module Lab.IoCapability

observed contract PositiveIo {
  capability io_file_read: IO.Capability
  effect read_file using io_file_read

  compute result = stdlib.IO.read_text("test_dir/file.txt", io_file_read)
}
