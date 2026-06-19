module RecordMapBridge

-- LAB-RECORD-MAP-P1: Record / Map[String,V] Bridge
--
-- Proves the lab-only bridge between typed Records and the proof-local
-- Map[String,V] model: records with map-typed fields, map field access
-- preserving type metadata, and fail-closed behavior for unresolved
-- or ill-typed map access.
--
-- Pressure families:
--   Rack  — FullRackResponse { headers: Map[String,String], ... }
--   Sidekiq — JobEnvelope { meta: Map[String,String], ... }
--
-- Key finding: one-layer gap at map lookup.
--   Rust compiler: correctly parses Map[String,String] record fields;
--                  SIR preserves Map params through field access;
--                  map_get/or_else not yet implemented (P4/P5 scope).
--   MapPipeline:   @type_shapes strips Map params (C1 caveat from P043-P3);
--                  field access returns Map (no params); map_get → Option[Unknown].
--   VM:            accepts Map inputs as JSON objects; stores/retrieves correctly;
--                  map_get bytecode opcode deferred to P5+.
--
-- Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim.
-- No canon grammar change. No JSON/JsonValue authority. No mutable map.
-- call_contract is lab-only.

-- ── Rack pressure types ───────────────────────────────────────────────────────

type FullRackResponse {
  body    : String,
  headers : Map[String, String],
  status  : Integer
}

-- ── Sidekiq pressure types ────────────────────────────────────────────────────

type JobEnvelope {
  job_id : String,
  meta   : Map[String, String]
}

-- ── Rack contracts ────────────────────────────────────────────────────────────

-- Constructs a FullRackResponse with a Map[String,String] headers field.
-- Verifies that the production compiler correctly handles Map-typed record fields.
pure contract WithHeaders {
  input  req_status   : Integer
  input  req_body     : String
  input  resp_headers : Map[String, String]
  compute response = {
    body:    req_body,
    headers: resp_headers,
    status:  req_status
  }
  output response : FullRackResponse
}

-- Reads response.headers via Tier 1 dispatch (call_contract literal callee).
-- Verifies that field access on a Map-typed record field:
--   (a) compiles correctly (no OOF-P1)
--   (b) produces Map[String,String] type in the SIR (params preserved by Rust compiler)
--   (c) executes in the VM — returns the map value as a JSON object
pure contract HeadersAccessor {
  input  req_status   : Integer
  input  req_body     : String
  input  resp_headers : Map[String, String]
  compute response = call_contract("WithHeaders", req_status, req_body, resp_headers)
  compute hdrs     = response.headers
  output hdrs : Map[String, String]
}

-- ── Sidekiq contracts ─────────────────────────────────────────────────────────

-- Constructs a JobEnvelope with a Map[String,String] meta field.
pure contract JobEnvelopeBuilder {
  input  job_id   : String
  input  job_meta : Map[String, String]
  compute envelope = {
    job_id: job_id,
    meta:   job_meta
  }
  output envelope : JobEnvelope
}

-- Reads envelope.meta via Tier 1 dispatch.
-- Parallel to HeadersAccessor — confirms the Sidekiq pressure case.
pure contract MetaAccessor {
  input  job_id   : String
  input  job_meta : Map[String, String]
  compute envelope = call_contract("JobEnvelopeBuilder", job_id, job_meta)
  compute meta     = envelope.meta
  output meta : Map[String, String]
}
