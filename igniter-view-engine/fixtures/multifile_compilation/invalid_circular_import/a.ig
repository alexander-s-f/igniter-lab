module Lab.Multifile.Invalid.Cycle.A
import Lab.Multifile.Invalid.Cycle.B.{ FromB }

type FromA {
  value: String
}
