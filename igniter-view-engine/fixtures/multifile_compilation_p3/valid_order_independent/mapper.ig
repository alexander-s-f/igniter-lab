module Lab.Multifile.Order.Mapper
import Lab.Multifile.Order.Types.{ HttpResult }

pure contract BuildHttpResult {
  input status: Integer
  input body: String
  input metadata: Map[String, String]
  compute result = {
    kind: "ok",
    status: status,
    body: body,
    metadata: metadata
  }
  output result : HttpResult
}
