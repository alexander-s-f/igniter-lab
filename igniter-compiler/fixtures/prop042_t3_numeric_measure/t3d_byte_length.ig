module T3D
recursive contract ByteLength {
  input text: Text
  compute result = recur(text)
  output result: Text
  decreases byte_length(text)
  max_steps 1000
}
