-- datetime_extension.ig
-- Conformance fixture verifying DateTime operations.

module SparkCRM.DateTimeExtensions

contract DateTimeWorkflow {
  input dt1: DateTime
  input dt2: DateTime
  input dt_add: DateTime
  input sec_add: Integer
  input str_parse: String
  input fmt_parse: String
  input fmt_format: String

  compute diff = diff_seconds(dt1, dt2)
  compute added = add_seconds(dt_add, sec_add)
  compute parsed = parse_datetime(str_parse, fmt_parse)
  compute formatted = format_datetime(dt1, fmt_format)
  compute before = is_before(dt1, dt2)
  compute after = is_after(dt1, dt2)

  output diff: Integer
  output added: DateTime
  output parsed: Option[DateTime]
  output formatted: String
  output before: Bool
  output after: Bool
}
