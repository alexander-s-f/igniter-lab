module Entrypoint.P4.TypeTarget

entrypoint Invoice

type Invoice {
  id : Integer
}

pure contract BuildInvoice {
  input value : Integer
  compute result = value + 1
  output result : Integer
}
