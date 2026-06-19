module T2C

size_relation MessageList unread

type MessageList {
  unread: MessageList
}

recursive contract StdlibPlusUser {
  input msgs: MessageList
  compute result = recur(msgs.unread)
  output result: Integer
  decreases msgs.unread
  max_steps 100
}
