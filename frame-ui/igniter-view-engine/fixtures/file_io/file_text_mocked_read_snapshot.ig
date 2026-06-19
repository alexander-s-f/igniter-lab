module Lab.FileIO.MockedReadSnapshot

-- LAB-FILE-IO-P1: File/Text capability shape and mocked read snapshot proof.
-- Track: file-text-io-capability-and-mocked-read-snapshot-boundary-v0
--
-- This fixture is type-shape evidence only. The read semantics are proved by
-- verify_lab_file_io_p1.rb using explicit in-memory mocked file snapshots.
--
-- Core distinction:
--   FileCapability is path/root/encoding/size/traversal authority data.
--   FileReadRequest is requested intent data.
--   MockFileRegistry is explicit fixture data, not host filesystem authority.
--   FileReadReceipt records evidence and never authorizes a later read.
--
-- Authority: LAB-ONLY. No real filesystem reads/writes, directory listing,
-- symlink following, ambient cwd, public File API, parser/compiler/VM change,
-- or canon IO.FileCapability schema authority.

type FileCapability {
  capability_id:          String,
  root_id:                String,
  allowed_roots:          Collection[String],
  allowed_ops:            Collection[String],
  read_allowed:           Bool,
  write_allowed:          Bool,
  max_bytes:              Integer,
  allowed_encodings:      Collection[String],
  allow_symlink:          Bool,
  allow_parent_traversal: Bool,
  deny_reason:            String,
  metadata:               Map[String, String]
}

type FileReadRequest {
  request_id: String,
  path:       String,
  op:         String,
  encoding:   String,
  root_id:    String,
  metadata:   Map[String, String]
}

type MockFileSnapshot {
  snapshot_id:    String,
  root_id:        String,
  path:           String,
  content:        String,
  encoding:       String,
  byte_length:    Integer,
  is_symlink:     Bool,
  target_path:    String,
  target_root_id: String,
  exists:         Bool,
  decode_valid:   Bool,
  metadata:       Map[String, String]
}

type MockFileRegistry {
  registry_id:        String,
  fixture_digest:     String,
  snapshots:          Collection[MockFileSnapshot],
  ambient_state_used: Bool,
  metadata:           Map[String, String]
}

type FileReadResult {
  kind:           String,
  request_id:     String,
  content:        String,
  byte_length:    Integer,
  encoding:       String,
  reason:         String,
  content_digest: String,
  metadata:       Map[String, String]
}

type FileReadReceipt {
  request_id:                 String,
  capability_id:              String,
  root_id:                    String,
  requested_path:             String,
  normalized_path:            String,
  op_requested:               String,
  cap_checked:                Bool,
  cap_granted:                Bool,
  denial_gate:                String,
  deny_reason:                String,
  encoding_requested:         String,
  encoding_observed:          String,
  bytes_read:                 Integer,
  max_bytes:                  Integer,
  content_digest:             String,
  snapshot_id:                String,
  fixture_digest:             String,
  symlink_encountered:        Bool,
  parent_traversal_detected:  Bool,
  result_kind:                String,
  ambient_state_used:         Bool,
  metadata:                   Map[String, String]
}

pure contract BuildFileCapability {
  input capability_id:          String
  input root_id:                String
  input allowed_roots:          Collection[String]
  input allowed_ops:            Collection[String]
  input read_allowed:           Bool
  input write_allowed:          Bool
  input max_bytes:              Integer
  input allowed_encodings:      Collection[String]
  input allow_symlink:          Bool
  input allow_parent_traversal: Bool
  input deny_reason:            String
  input metadata:               Map[String, String]
  compute cap = {
    capability_id:          capability_id,
    root_id:                root_id,
    allowed_roots:          allowed_roots,
    allowed_ops:            allowed_ops,
    read_allowed:           read_allowed,
    write_allowed:          write_allowed,
    max_bytes:              max_bytes,
    allowed_encodings:      allowed_encodings,
    allow_symlink:          allow_symlink,
    allow_parent_traversal: allow_parent_traversal,
    deny_reason:            deny_reason,
    metadata:               metadata
  }
  output cap : FileCapability
}

pure contract BuildFileReadRequest {
  input request_id: String
  input path:       String
  input op:         String
  input encoding:   String
  input root_id:    String
  input metadata:   Map[String, String]
  compute req = {
    request_id: request_id,
    path:       path,
    op:         op,
    encoding:   encoding,
    root_id:    root_id,
    metadata:   metadata
  }
  output req : FileReadRequest
}

pure contract BuildMockFileSnapshot {
  input snapshot_id:    String
  input root_id:        String
  input path:           String
  input content:        String
  input encoding:       String
  input byte_length:    Integer
  input is_symlink:     Bool
  input target_path:    String
  input target_root_id: String
  input exists:         Bool
  input decode_valid:   Bool
  input metadata:       Map[String, String]
  compute mock_snapshot = {
    snapshot_id:    snapshot_id,
    root_id:        root_id,
    path:           path,
    content:        content,
    encoding:       encoding,
    byte_length:    byte_length,
    is_symlink:     is_symlink,
    target_path:    target_path,
    target_root_id: target_root_id,
    exists:         exists,
    decode_valid:   decode_valid,
    metadata:       metadata
  }
  output mock_snapshot : MockFileSnapshot
}

pure contract BuildMockFileRegistry {
  input registry_id:    String
  input fixture_digest: String
  input snapshots:      Collection[MockFileSnapshot]
  input metadata:       Map[String, String]
  compute registry = {
    registry_id:        registry_id,
    fixture_digest:     fixture_digest,
    snapshots:          snapshots,
    ambient_state_used: false,
    metadata:           metadata
  }
  output registry : MockFileRegistry
}

pure contract BuildFileReadResult {
  input kind:           String
  input request_id:     String
  input content:        String
  input byte_length:    Integer
  input encoding:       String
  input reason:         String
  input content_digest: String
  input metadata:       Map[String, String]
  compute result = {
    kind:           kind,
    request_id:     request_id,
    content:        content,
    byte_length:    byte_length,
    encoding:       encoding,
    reason:         reason,
    content_digest: content_digest,
    metadata:       metadata
  }
  output result : FileReadResult
}

pure contract BuildFileReadReceipt {
  input request_id:                String
  input capability_id:             String
  input root_id:                   String
  input requested_path:            String
  input normalized_path:           String
  input op_requested:              String
  input cap_granted:               Bool
  input denial_gate:               String
  input deny_reason:               String
  input encoding_requested:        String
  input encoding_observed:         String
  input bytes_read:                Integer
  input max_bytes:                 Integer
  input content_digest:            String
  input snapshot_id:               String
  input fixture_digest:            String
  input symlink_encountered:       Bool
  input parent_traversal_detected: Bool
  input result_kind:               String
  input metadata:                  Map[String, String]
  compute receipt = {
    request_id:                request_id,
    capability_id:             capability_id,
    root_id:                   root_id,
    requested_path:            requested_path,
    normalized_path:           normalized_path,
    op_requested:              op_requested,
    cap_checked:               true,
    cap_granted:               cap_granted,
    denial_gate:               denial_gate,
    deny_reason:               deny_reason,
    encoding_requested:        encoding_requested,
    encoding_observed:         encoding_observed,
    bytes_read:                bytes_read,
    max_bytes:                 max_bytes,
    content_digest:            content_digest,
    snapshot_id:               snapshot_id,
    fixture_digest:            fixture_digest,
    symlink_encountered:       symlink_encountered,
    parent_traversal_detected: parent_traversal_detected,
    result_kind:               result_kind,
    ambient_state_used:        false,
    metadata:                  metadata
  }
  output receipt : FileReadReceipt
}

pure contract FileReadMetadataReader {
  input receipt: FileReadReceipt
  compute observed_kind = receipt.result_kind
  compute observed_bytes = receipt.bytes_read
  output observed_kind : String
  output observed_bytes : Integer
}
