module Lab.Multifile.Order.Consumer
import Lab.Multifile.Order.Types
import Lab.Multifile.Order.Mapper.{ BuildHttpResult }

pure contract StatusReader {
  input status: Integer
  input body: String
  input metadata: Map[String, String]
  compute result = call_contract("BuildHttpResult", status, body, metadata)
  compute code = result.status
  output code : Integer
}
