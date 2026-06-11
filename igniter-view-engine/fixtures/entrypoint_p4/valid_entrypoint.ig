module Entrypoint.P4.Valid

entrypoint RunInvoice

pure contract RunInvoice {
  input invoice_id : Integer
  compute result = invoice_id + 1
  output result : Integer
}

pure contract Helper {
  input value : Integer
  compute result = value + 2
  output result : Integer
}
