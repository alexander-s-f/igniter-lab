module Entrypoint.P4.EffectTarget

entrypoint FetchRemote

effect contract FetchRemote {
  input request_id : String
  compute result = request_id
  output result : String
}
