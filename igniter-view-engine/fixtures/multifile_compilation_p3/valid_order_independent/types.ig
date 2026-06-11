module Lab.Multifile.Order.Types

type HttpResult {
  kind: String,
  status: Integer,
  body: String,
  metadata: Map[String, String]
}
