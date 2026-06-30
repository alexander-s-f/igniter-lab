-- error_handling_extension.ig
-- Conformance fixture for Direction F: try_catch, propagate, validate

module SparkCRM.ErrorHandling

contract ErrorHandlingWorkflow {
  -- Inputs
  input res_ok:  Result[Integer, String]   -- e.g. {ok: 42}
  input res_err: Result[Integer, String]   -- e.g. {err: "oops"}
  input raw_val: Integer                   -- e.g. 7
  input threshold: Integer                 -- e.g. 5

  -- try_catch: recover from err branch with a constant fallback lambda
  compute recovered = try_catch(res_err, e -> 0)

  -- try_catch on ok: handler is never called, inner value passes through
  compute ok_passthrough = try_catch(res_ok, e -> 0)

  -- propagate: extract ok value from a successful result
  compute propagated = propagate(res_ok)

  -- validate: raw_val > threshold → ok(raw_val), else err("too_small")
  compute validated = validate(raw_val, v -> v > threshold, "too_small")

  -- validate a failing case: 3 > 5 is false → err("too_small")
  compute invalid = validate(3, v -> v > threshold, "too_small")

  output recovered:      Integer
  output ok_passthrough: Integer
  output propagated:     Integer
  output validated:      Result[Integer, String]
  output invalid:        Result[Integer, String]
}
