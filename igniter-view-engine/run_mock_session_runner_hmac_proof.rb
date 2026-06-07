# igniter-lab/igniter-view-engine/run_mock_session_runner_hmac_proof.rb

require 'json'
require 'openssl'
require 'fileutils'

# 1. Parse Arguments
session_token = ARGV[0]
transaction_id = ARGV[1]
status = ARGV[2] || 'applied'
oversized = ARGV[3] == 'true'

if session_token.nil? || transaction_id.nil?
  puts "Usage: ruby run_mock_session_runner_hmac_proof.rb <session_token> <transaction_id> [status] [oversized_flag]"
  exit(1)
end

ENGINE_DIR = File.expand_path(__dir__)
OUT_DIR = File.join(ENGINE_DIR, 'out')
# Suffix filename with transaction_id to prevent concurrency race conditions in tests
INGRESS_ENVELOPE_PATH = File.join(OUT_DIR, "ruby_session_ingress_envelope_#{transaction_id}.json")

# 2. Build Outputs / Diagnostics
outputs_data = { "result" => "mock-session-runner-output" }
if oversized
  # Make payload exceed 65536 bytes limit
  outputs_data["large_field"] = "a" * 70000
end

payload_hash = {
  "transaction_id" => transaction_id,
  "contract_name" => "test_contract",
  "status" => status,
  "timestamp" => "2026-06-06T12:00:00Z",
  "producer_id" => "ruby-vm-runner-v1.0",
  "target_views" => ["test_view"],
  "outputs" => outputs_data,
  "diagnostics" => { "warnings" => ["mock-session-warning"] },
  "slot_values" => { "key_a" => "value_a" }
}

# 3. Canonicalize Helper to sort keys recursively for deterministic hashing
def canonicalize(val)
  if val.is_a?(Hash)
    sorted = val.sort.map { |k, v| [k, canonicalize(v)] }
    Hash[sorted]
  elsif val.is_a?(Array)
    val.map { |v| canonicalize(v) }
  else
    val
  end
end

canonical_payload = canonicalize(payload_hash)
canonical_json = JSON.generate(canonical_payload)

# 4. Sign Payload (unless unsigned requested)
if status == 'unsigned'
  puts "Creating unsigned payload."
elsif status == 'wrong_sig'
  payload_hash["passport_signature"] = "invalid-hmac-signature-value"
else
  digest = OpenSSL::Digest.new('sha256')
  signature = OpenSSL::HMAC.hexdigest(digest, session_token, canonical_json)
  payload_hash["passport_signature"] = signature
  puts "Calculated HMAC-SHA256 signature: #{signature}"
end

# 5. Output JSON Envelope
FileUtils.mkdir_p(OUT_DIR)
File.write(INGRESS_ENVELOPE_PATH, JSON.pretty_generate(payload_hash))
puts "Saved signed envelope to: #{INGRESS_ENVELOPE_PATH}"
