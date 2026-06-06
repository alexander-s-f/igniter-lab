module Lab.IoPassportBridge

pure contract PureAmbient {
  compute result = stdlib.IO.read_text("test.txt", io_child_read)
}
