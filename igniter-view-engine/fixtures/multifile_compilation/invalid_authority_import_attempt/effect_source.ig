module Lab.Multifile.Invalid.Authority.EffectSource

effect contract RemoteFetch {
  capability net: IO.NetworkCapability
  effect fetch using net
  input url: String
  compute out = url
  output out : String
}
