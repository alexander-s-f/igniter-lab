module Lab.StorageAdapter.MockedContract

-- LAB-STORAGE-ADAPTER-P1: mocked Storage IO adapter contract hardening.
-- Track: storage-io-mocked-adapter-contract-hardening-v0
--
-- This fixture is type-shape evidence only. The adapter execution semantics are
-- proved by verify_lab_storage_adapter_p1.rb using explicit in-memory fixture
-- rows. No real database, SQL, ORM, file storage, or host storage is opened.
--
-- Core distinction:
--   QueryPlanUnified is typed intent data.
--   StorageCapability is an authority descriptor record.
--   MockStorageSource is explicit fixture data.
--   QueryExecutionReceipt is evidence, not authority.
--   StorageAdapterReceipt adds adapter/substrate boundary facts only.

type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

type QuerySource {
  table:  String,
  schema: String
}

type Projection {
  fields:      String,
  include_all: Bool
}

type OrderBy {
  field:     String,
  direction: String
}

type QueryPlanUnified {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      Collection[OrderBy],
  limit:      Integer,
  metadata:   Map[String, String]
}

type StorageCapability {
  cap_id:            String,
  allowed_sources:   Collection[String],
  allowed_ops:       Collection[String],
  row_limit:         Integer,
  allow_include_all: Bool,
  read_allowed:      Bool,
  write_allowed:     Bool,
  deny_reason:       String
}

type MockTable {
  table:     String,
  row_count: Integer,
  columns:   String
}

type MockStorageSource {
  adapter_id:       String,
  mocked_source_id: String,
  fixture_digest:   String,
  tables:           Collection[MockTable],
  ambient_state:    Bool
}

type StorageAdapterRequest {
  plan:         QueryPlanUnified,
  capability:   StorageCapability,
  source:       MockStorageSource,
  request_id:   String,
  execution_id: String
}

type QueryResult {
  kind:     String,
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}

type QueryExecutionReceipt {
  cap_id:            String,
  plan_kind:         String,
  source_table:      String,
  op_requested:      String,
  cap_checked:       Bool,
  cap_granted:       Bool,
  denial_gate:       String,
  deny_reason:       String,
  plan_limit:        Integer,
  row_limit_cap:     Integer,
  effective_limit:   Integer,
  row_limit_clamped: Bool,
  rows_returned:     Integer,
  result_kind:       String,
  metadata:          Map[String, String]
}

type StorageAdapterReceipt {
  adapter_id:         String,
  mocked_source_id:   String,
  request_id:         String,
  execution_id:       String,
  substrate_kind:     String,
  fixture_digest:     String,
  source_table:       String,
  result_kind:        String,
  ambient_state_used: Bool
}

pure contract BuildAdapterPlan {
  input source:     QuerySource
  input projection: Projection
  input limit:      Integer
  input metadata:   Map[String, String]
  compute filters = [
    { field: "status", op: "eq", value: "active" }
  ]
  compute order_list = [
    { field: "dept", direction: "asc" },
    { field: "name", direction: "asc" }
  ]
  compute plan = {
    kind:       "select",
    source:     source,
    projection: projection,
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanUnified
}

pure contract BuildStorageCapability {
  input cap_id:            String
  input allowed_sources:   Collection[String]
  input allowed_ops:       Collection[String]
  input row_limit:         Integer
  input allow_include_all: Bool
  input read_allowed:      Bool
  input write_allowed:     Bool
  input deny_reason:       String
  compute cap = {
    cap_id:            cap_id,
    allowed_sources:   allowed_sources,
    allowed_ops:       allowed_ops,
    row_limit:         row_limit,
    allow_include_all: allow_include_all,
    read_allowed:      read_allowed,
    write_allowed:     write_allowed,
    deny_reason:       deny_reason
  }
  output cap : StorageCapability
}

pure contract BuildMockTable {
  input table:     String
  input row_count: Integer
  input columns:   String
  compute mock_table = { table: table, row_count: row_count, columns: columns }
  output mock_table : MockTable
}

pure contract BuildMockStorageSource {
  input adapter_id:       String
  input mocked_source_id: String
  input fixture_digest:   String
  input tables:           Collection[MockTable]
  compute source = {
    adapter_id:       adapter_id,
    mocked_source_id: mocked_source_id,
    fixture_digest:   fixture_digest,
    tables:           tables,
    ambient_state:    false
  }
  output source : MockStorageSource
}

pure contract BuildAdapterRequest {
  input plan:         QueryPlanUnified
  input capability:   StorageCapability
  input source:       MockStorageSource
  input request_id:   String
  input execution_id: String
  compute req = {
    plan:         plan,
    capability:   capability,
    source:       source,
    request_id:   request_id,
    execution_id: execution_id
  }
  output req : StorageAdapterRequest
}

pure contract BuildQueryResult {
  input kind:     String
  input count:    Integer
  input reason:   String
  input metadata: Map[String, String]
  compute result = { kind: kind, count: count, message: reason, metadata: metadata }
  output result : QueryResult
}

pure contract BuildQueryExecutionReceipt {
  input cap_id:            String
  input source_table:      String
  input plan_limit:        Integer
  input row_limit_cap:     Integer
  input effective_limit:   Integer
  input row_limit_clamped: Bool
  input rows_returned:     Integer
  input result_kind:       String
  input metadata:          Map[String, String]
  compute receipt = {
    cap_id:            cap_id,
    plan_kind:         "select",
    source_table:      source_table,
    op_requested:      "read",
    cap_checked:       true,
    cap_granted:       true,
    denial_gate:       "",
    deny_reason:       "",
    plan_limit:        plan_limit,
    row_limit_cap:     row_limit_cap,
    effective_limit:   effective_limit,
    row_limit_clamped: row_limit_clamped,
    rows_returned:     rows_returned,
    result_kind:       result_kind,
    metadata:          metadata
  }
  output receipt : QueryExecutionReceipt
}

pure contract BuildStorageAdapterReceipt {
  input adapter_id:       String
  input mocked_source_id: String
  input request_id:       String
  input execution_id:     String
  input fixture_digest:   String
  input source_table:     String
  input result_kind:      String
  compute receipt = {
    adapter_id:         adapter_id,
    mocked_source_id:   mocked_source_id,
    request_id:         request_id,
    execution_id:       execution_id,
    substrate_kind:     "mocked_storage",
    fixture_digest:     fixture_digest,
    source_table:       source_table,
    result_kind:        result_kind,
    ambient_state_used: false
  }
  output receipt : StorageAdapterReceipt
}

pure contract AdapterMetadataReader {
  input metadata:  Map[String, String]
  input query_key: String
  compute value = map_get(metadata, query_key)
  compute fallback = or_else(value, "missing")
  output fallback : String
}
