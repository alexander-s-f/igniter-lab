module Lab.Multifile.Basic.Consumer
import Lab.Multifile.Basic.Types.{ QueryResult, FilterPredicate }

pure contract BuildQueryResult {
  input kind: String
  input count: Integer
  input reason: String
  input metadata: Map[String, String]
  compute result = {
    kind: kind,
    count: count,
    reason: reason,
    metadata: metadata
  }
  output result : QueryResult
}

pure contract BuildFilterPredicate {
  input field: String
  input op: String
  input value: String
  compute pred = {
    field: field,
    op: op,
    value: value
  }
  output pred : FilterPredicate
}
