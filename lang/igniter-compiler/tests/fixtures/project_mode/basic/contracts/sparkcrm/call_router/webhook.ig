module SparkCRM.CallRouter.Webhook
import SparkCRM.CallRouter.Types.{ CallrailCall }
import stdlib.collection.{ count }

pure contract AppendWebhook {
  input call : CallrailCall
  compute id : String = call.id
  output id : String
}
