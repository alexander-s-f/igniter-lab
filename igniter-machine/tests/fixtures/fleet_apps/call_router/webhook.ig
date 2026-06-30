module CallRouterWebhook
import CallRouterTypes
import stdlib.collection.{ count }

-- ============================================================
-- CallRail webhook upsert (Calls::CallrailWebhook#update)
-- ============================================================
-- A single call evolves across several webhooks (pre_call →
-- call_routing_complete → post_call → call_modified). Each one appends
-- its type to the call's `webhooks` lifecycle list.
--
-- PRESSURE CR-P06: the webhook history is accumulated with `concat`; the
-- natural form is `fold(events, call0, (call, ev) -> AppendWebhook(...))`
-- — a fold-over-record (fold-to-struct), unavailable today.

pure contract AppendWebhook {
  input call : CallrailCall
  input webhook_type : String
  compute next = {
    id: call.id, call_id: call.call_id, callrail_company_id: call.callrail_company_id,
    customer_phone: call.customer_phone, tracking_phone: call.tracking_phone,
    answered: call.answered, started_at_min: call.started_at_min,
    webhooks: concat(call.webhooks, [webhook_type]), operator_id: call.operator_id
  }
  output next : CallrailCall
}

-- How many lifecycle webhooks have landed for this call.
pure contract WebhookCount {
  input call : CallrailCall
  compute n = count(call.webhooks)
  output n : Integer
}

-- The call has completed its lifecycle once post_call has landed.
pure contract LifecycleComplete {
  input call : CallrailCall
  input has_post_call : Integer
  compute done = if has_post_call == 1 { 1 } else { 0 }
  output done : Integer
}
