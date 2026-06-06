module Lab.IoCapability

pure contract AmbientBlockedIo {
  -- calling IO from a pure contract
  compute result = stdlib.IO.read_text("test_dir/file.txt", io_file_read)
}
