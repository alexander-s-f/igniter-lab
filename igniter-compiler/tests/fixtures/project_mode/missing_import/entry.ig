module Solo.Entry
import Missing.Types.{ Foo }

pure contract E {
  input x : Integer
  compute y : Integer = x
  output y : Integer
}
