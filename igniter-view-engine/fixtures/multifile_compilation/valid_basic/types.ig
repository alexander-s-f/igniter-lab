module Lab.Multifile.Basic.Types

type QueryResult {
  kind: String,
  count: Integer,
  reason: String,
  metadata: Map[String, String]
}

type FilterPredicate {
  field: String,
  op: String,
  value: String
}
