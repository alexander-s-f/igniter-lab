module Lab.StorageAdapter.ReplayHardening

-- LAB-STORAGE-ADAPTER-P2: adapter receipt replay and tamper hardening.
-- This fixture is type-shape evidence for replay results and digest bundles.
-- Replay verification is proof-local Ruby code in verify_lab_storage_adapter_p2.rb.
-- No real database, SQL, ORM, file storage, host storage, or public API opens.

type StorageAdapterReplayResult {
  kind:         String,
  reason:       String,
  request_id:   String,
  execution_id: String,
  verified:     Bool,
  metadata:     Map[String, String]
}

type StorageAdapterDigestBundle {
  request_digest:                 String,
  plan_digest:                    String,
  capability_digest:              String,
  fixture_digest:                 String,
  query_result_digest:            String,
  query_execution_receipt_digest: String,
  adapter_receipt_digest:         String,
  replay_bundle_digest:           String
}

type StorageAdapterReplayContext {
  schema_version:       String,
  adapter_code_version: String,
  replay_id:            String,
  metadata:             Map[String, String]
}

pure contract BuildReplayResult {
  input kind:         String
  input reason:       String
  input request_id:   String
  input execution_id: String
  input verified:     Bool
  input metadata:     Map[String, String]
  compute result = {
    kind:         kind,
    reason:       reason,
    request_id:   request_id,
    execution_id: execution_id,
    verified:     verified,
    metadata:     metadata
  }
  output result : StorageAdapterReplayResult
}

pure contract BuildDigestBundle {
  input request_digest:                 String
  input plan_digest:                    String
  input capability_digest:              String
  input fixture_digest:                 String
  input query_result_digest:            String
  input query_execution_receipt_digest: String
  input adapter_receipt_digest:         String
  input replay_bundle_digest:           String
  compute bundle = {
    request_digest:                 request_digest,
    plan_digest:                    plan_digest,
    capability_digest:              capability_digest,
    fixture_digest:                 fixture_digest,
    query_result_digest:            query_result_digest,
    query_execution_receipt_digest: query_execution_receipt_digest,
    adapter_receipt_digest:         adapter_receipt_digest,
    replay_bundle_digest:           replay_bundle_digest
  }
  output bundle : StorageAdapterDigestBundle
}

pure contract BuildReplayContext {
  input schema_id:            String
  input adapter_code_version: String
  input replay_id:            String
  input metadata:             Map[String, String]
  compute context = {
    schema_version:       schema_id,
    adapter_code_version: adapter_code_version,
    replay_id:            replay_id,
    metadata:             metadata
  }
  output context : StorageAdapterReplayContext
}

pure contract ReplayMetadataReader {
  input result:    StorageAdapterReplayResult
  input query_key: String
  compute value = map_get(result.metadata, query_key)
  compute fallback = or_else(value, "missing")
  output fallback : String
}
