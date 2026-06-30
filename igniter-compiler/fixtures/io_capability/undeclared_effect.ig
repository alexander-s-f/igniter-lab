module Lab.IoCapability

observed contract UndeclaredEffectIo {
  capability io_file_read: IO.Capability
  -- Missing: effect read_file using io_file_read

  compute result = stdlib.IO.read_text("test_dir/file.txt", io_file_read)
}
