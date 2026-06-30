module Lab.IoCapability

observed contract WrongModeIo {
  capability io_file_read: IO.Capability
  effect read_file using io_file_read

  -- Write operation using read capability
  compute result = stdlib.IO.write_text("test_dir/file.txt", "hello", io_file_read)
}
