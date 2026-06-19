module CallRouterTypes

type CallrailCall {
  id: String,
  call_id: String,
  customer_phone: String,
  tracking_phone: String,
  webhooks: Collection[String],
  operator_id: String
}
