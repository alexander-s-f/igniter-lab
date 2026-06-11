module Lab.Multifile.Invalid.Authority.Consumer
import Lab.Multifile.Invalid.Authority.EffectSource.{ RemoteFetch }

pure contract IllicitCaller {
  input url: String
  compute out = call_contract("RemoteFetch", url)
  output out : String
}
