-- monadic_extension.ig
-- Conformance fixture verifying Option[T] and Result[T, E] monadic operations.

module SparkCRM.Monadic

contract OptionWorkflow {
  input opt_in: Option[Integer]
  input fallback: Integer

  compute is_some_val = is_some(opt_in)
  compute is_none_val = is_none(opt_in)
  compute mapped = map(opt_in, x -> x * 2)
  compute flat_mapped = flat_map(opt_in, x -> some(x + 10))
  compute unwrapped = unwrap_or(opt_in, fallback)
  compute unwrapped_mapped = unwrap_or(map(opt_in, x -> x * 3), fallback)

  output is_some_val: Bool
  output is_none_val: Bool
  output mapped: Option[Integer]
  output flat_mapped: Option[Integer]
  output unwrapped: Integer
  output unwrapped_mapped: Integer
}

contract ResultWorkflow {
  input res_in: Result[Integer, String]
  input fallback: Integer

  compute is_ok_val = is_ok(res_in)
  compute is_err_val = is_err(res_in)
  compute mapped = map(res_in, x -> x * 5)
  compute flat_mapped = and_then(res_in, x -> ok(x + 100))
  compute unwrapped_or_val = unwrap_or(res_in, fallback)

  output is_ok_val: Bool
  output is_err_val: Bool
  output mapped: Result[Integer, String]
  output flat_mapped: Result[Integer, String]
  output unwrapped_or_val: Integer
}

contract ResultUnwrap {
  input res_in: Result[Integer, String]
  compute val = unwrap(res_in)
  output val: Integer
}
