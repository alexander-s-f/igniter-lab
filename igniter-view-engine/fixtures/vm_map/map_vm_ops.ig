module Lab.VM.MapOps

-- LAB-VM-MAP-P1: Prove VM runtime support for map_get, map_has_key, or_else
-- over Map[String,String] runtime values. Closes Rack P14 HeadersAwareHandler gap.
--
-- Option representation: None = Value::Nil, Some(v) = raw v (no wrapper).
-- Map runtime representation: Value::Record(BTreeMap<String, Value>).
--
-- Contracts:
--   MapGetHit      — map_get present key → Some path; or_else returns value
--   MapGetMiss     — map_get absent key  → None path; or_else returns sentinel
--   OrElseHit      — or_else(Some(v), default) → v (identity path)
--   OrElseMiss     — or_else(None, default)    → default (fallback path)
--   HasKeyHit      — map_has_key present key → true
--   HasKeyMiss     — map_has_key absent key  → false
--   HeaderChain    — resp_headers + map_get + or_else (mirrors Rack P14 gap)
--
-- Output type annotations: String and Bool only (no bare Option[String] output
-- annotations to ensure compatibility with the compiler's output parser).
-- The Option[String] type is proved via the intermediate `opt` compute node.
--
-- lab-only. No canon claim. No mutation. String keys only. No broad map API.

-- ── map_get contracts ─────────────────────────────────────────────────────────
-- Use sentinel "__absent__" in or_else to distinguish hit vs miss paths.

pure contract MapGetHit {
  input  m : Map[String, String]
  compute opt    = map_get(m, "name")
  compute result = or_else(opt, "__absent__")
  output  result : String
}

pure contract MapGetMiss {
  input  m : Map[String, String]
  compute opt    = map_get(m, "absent_key")
  compute result = or_else(opt, "__absent__")
  output  result : String
}

-- ── or_else contracts ──────────────────────────────────────────────────────────

pure contract OrElseHit {
  input  m : Map[String, String]
  compute opt    = map_get(m, "queue")
  compute result = or_else(opt, "default")
  output  result : String
}

pure contract OrElseMiss {
  input  m : Map[String, String]
  compute opt    = map_get(m, "absent_key")
  compute result = or_else(opt, "fallback")
  output  result : String
}

-- ── map_has_key contracts ──────────────────────────────────────────────────────

pure contract HasKeyHit {
  input  m : Map[String, String]
  compute result = map_has_key(m, "name")
  output  result : Bool
}

pure contract HasKeyMiss {
  input  m : Map[String, String]
  compute result = map_has_key(m, "absent_key")
  output  result : Bool
}

-- ── Header extraction chain (mirrors Rack P14 HeadersAwareHandler) ────────────
-- Proves the exact gap: resp_headers field access + map_get + or_else.

pure contract HeaderChain {
  input  resp_headers : Map[String, String]
  compute ct_opt  = map_get(resp_headers, "content-type")
  compute ct      = or_else(ct_opt, "text/plain")
  output  ct : String
}
