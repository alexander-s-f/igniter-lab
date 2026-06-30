module Lab.IoPassportBridge

observed contract WrongMode {
  capability io_child_read: IO.Capability
  effect read_file using io_child_read

  compute result = stdlib.IO.write_text("test.txt", "hello", io_child_read)
}
