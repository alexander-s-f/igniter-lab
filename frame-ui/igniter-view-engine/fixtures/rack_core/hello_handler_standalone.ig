module Rack.P3.HelloHandler

-- Lab-only standalone HelloHandler contract.
-- CLOSED: lab-only, no canon claim, no stable API, no production surface.
-- Used in LAB-RACK-P3 as the baseline single-contract VM execution target.

pure contract HelloHandler {
  input  method : String
  input  path   : String
  compute status_code = 200
  output status_code  : Integer
}
