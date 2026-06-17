module CallRouterWebhook
import CallRouterTypes
import stdlib.collection.{ count }

pure contract AppendWebhook {
  input call : CallrailCall
  compute next = {
    id: call.id,
    call_id: call.call_id,
    customer_phone: call.customer_phone,
    tracking_phone: call.tracking_phone,
    webhooks: call.webhooks,
    operator_id: call.operator_id
  }
  output next : CallrailCall
}

pure contract WebhookCount {
  input call : CallrailCall
  compute n = count(call.webhooks)
  output n : Integer
}
