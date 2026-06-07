# frozen_string_literal: true
# NetworkFFIStub — Ruby simulation of Rust C ABI network library
# Card: LAB-STDLIB-NET-P3
# Lane: standard
# No real TCP sockets. In-memory stub only.
# Forbidden: TCPSocket, UDPSocket, Socket, Net::HTTP, require 'socket', require 'net/http'

require 'json'
require 'set'
require 'securerandom'

# ═══════════════════════════════════════════════════════════════════════════════
# Part A — P2 Modules (copied verbatim from network_capability_proof.rb)
# ═══════════════════════════════════════════════════════════════════════════════

module NetworkCapabilityValidator
  REQUIRED_FIELDS = %w[
    capability_id resource_type protocol direction
    allowed_hosts allowed_port_ranges
    loopback_only connect_allowed listen_allowed send_allowed receive_allowed
  ].freeze

  VALID_PROTOCOLS  = %w[tcp udp tcp_udp].freeze
  VALID_DIRECTIONS = %w[connect listen both].freeze

  LOOPBACK_ADDRESSES = Set.new(%w[127.0.0.1 localhost ::1]).freeze

  def self.loopback_address?(host)
    return true if LOOPBACK_ADDRESSES.include?(host)
    host.start_with?('127.')
  end

  # validate_schema(cap) → {valid: Bool, errors: [String]}
  def self.validate_schema(cap)
    errors = []

    unless cap.is_a?(Hash)
      return { valid: false, errors: ['capability must be a JSON object'] }
    end

    # resource_type must be "network"
    if cap['resource_type'] != 'network'
      errors << "resource_type must be \"network\", got #{cap['resource_type'].inspect}"
    end

    # Required fields present
    REQUIRED_FIELDS.each do |field|
      errors << "missing required field: #{field}" unless cap.key?(field)
    end

    return { valid: false, errors: errors } unless errors.empty?

    # Type checks
    unless cap['capability_id'].is_a?(String) && !cap['capability_id'].empty?
      errors << 'capability_id must be a non-empty string'
    end

    unless VALID_PROTOCOLS.include?(cap['protocol'])
      errors << "protocol must be one of #{VALID_PROTOCOLS.join(', ')}, got #{cap['protocol'].inspect}"
    end

    unless VALID_DIRECTIONS.include?(cap['direction'])
      errors << "direction must be one of #{VALID_DIRECTIONS.join(', ')}, got #{cap['direction'].inspect}"
    end

    unless cap['allowed_hosts'].is_a?(Array)
      errors << 'allowed_hosts must be an array'
    end

    unless cap['allowed_port_ranges'].is_a?(Array)
      errors << 'allowed_port_ranges must be an array'
    else
      cap['allowed_port_ranges'].each_with_index do |r, i|
        unless r.is_a?(Hash) && r.key?('min') && r.key?('max') &&
               r['min'].is_a?(Integer) && r['max'].is_a?(Integer) &&
               r['min'] <= r['max']
          errors << "allowed_port_ranges[#{i}] must be {min: Integer, max: Integer} with min <= max"
        end
      end
    end

    %w[loopback_only connect_allowed listen_allowed send_allowed receive_allowed].each do |bool_field|
      unless [true, false].include?(cap[bool_field])
        errors << "#{bool_field} must be a boolean"
      end
    end

    # bind_address: nil or string
    unless cap['bind_address'].nil? || cap['bind_address'].is_a?(String)
      errors << 'bind_address must be null or a string'
    end

    { valid: errors.empty?, errors: errors }
  end

  # check_policy_net1(cap, target_host) — Loopback Bound
  def self.check_policy_net1(cap, target_host)
    return { ok: true, code: nil } unless cap['loopback_only']

    if loopback_address?(target_host)
      { ok: true, code: nil }
    else
      { ok: false, code: 'E-NET-LOOPBACK-VIOLATION' }
    end
  end

  # check_policy_net2(cap, target_host) — Host Allowlist Check
  def self.check_policy_net2(cap, target_host)
    allowed = cap['allowed_hosts'] || []
    return { ok: false, code: 'E-NET-HOST-BLOCKED' } if allowed.empty?
    return { ok: true, code: nil } if allowed.include?('*')

    if allowed.include?(target_host)
      { ok: true, code: nil }
    else
      { ok: false, code: 'E-NET-HOST-BLOCKED' }
    end
  end

  # check_policy_net3(cap, target_port) — Port Range Check
  def self.check_policy_net3(cap, target_port)
    ranges = cap['allowed_port_ranges'] || []
    return { ok: false, code: 'E-NET-PORT-BLOCKED' } if ranges.empty?

    in_range = ranges.any? { |r| target_port >= r['min'] && target_port <= r['max'] }
    if in_range
      { ok: true, code: nil }
    else
      { ok: false, code: 'E-NET-PORT-BLOCKED' }
    end
  end

  # check_policy_net4(cap, operation) — Explicit Direction Check
  # operation: :connect | :listen | :send | :receive
  def self.check_policy_net4(cap, operation)
    field = "#{operation}_allowed"
    if cap[field]
      { ok: true, code: nil }
    else
      { ok: false, code: 'E-NET-DIRECTION-BLOCKED' }
    end
  end

  # check_policy_net5(cap, tls_used) — TLS Enforcement
  def self.check_policy_net5(cap, tls_used)
    if cap['tls_required'] && !tls_used
      { ok: false, code: 'E-NET-TLS-REQUIRED' }
    else
      { ok: true, code: nil }
    end
  end

  # check_policy_net6(cap, protocol_used) — Protocol Constraint
  def self.check_policy_net6(cap, protocol_used)
    cap_proto = cap['protocol']
    ok = if cap_proto == 'tcp_udp'
           %w[tcp udp tcp_udp].include?(protocol_used)
         else
           cap_proto == protocol_used
         end
    if ok
      { ok: true, code: nil }
    else
      { ok: false, code: 'E-NET-PROTOCOL-MISMATCH' }
    end
  end
end

module NetworkDelegationAlgebra
  # protocol_subset?(child_proto, parent_proto) — protocol ordering relation
  def self.protocol_subset?(child_proto, parent_proto)
    return true if child_proto == parent_proto
    return true if parent_proto == 'tcp_udp' && %w[tcp udp].include?(child_proto)
    false
  end

  # range_subset?(child_ranges, parent_ranges) — port range inclusion
  # For each child range, at least one parent range must fully contain it.
  def self.range_subset?(child_ranges, parent_ranges)
    child_ranges.all? do |cr|
      parent_ranges.any? do |pr|
        pr['min'] <= cr['min'] && cr['max'] <= pr['max']
      end
    end
  end

  # host_subset?(child_hosts, parent_hosts) — host set inclusion
  def self.host_subset?(child_hosts, parent_hosts)
    return true if parent_hosts.include?('*')
    child_hosts.all? { |h| parent_hosts.include?(h) }
  end

  # valid_delegation?(parent, child) → {valid: Bool, violations: [String]}
  def self.valid_delegation?(parent, child)
    violations = []

    # Condition 1 — Type Identity
    if parent['resource_type'] != 'network' || child['resource_type'] != 'network'
      violations << 'E-NET-DELEGATION-TYPE-MISMATCH'
    end

    # Condition 2 — Protocol Non-Escalation
    unless protocol_subset?(child['protocol'], parent['protocol'])
      violations << 'E-NET-DELEGATION-PROTOCOL-ESCALATION'
    end

    # Condition 3 — Direction Non-Escalation
    %w[connect listen send receive].each do |dir|
      field = "#{dir}_allowed"
      if child[field] && !parent[field]
        violations << 'E-NET-DELEGATION-PERMISSION-ESCALATION'
        break
      end
    end

    # Condition 4 — Loopback Non-Escalation
    if parent['loopback_only'] && !child['loopback_only']
      violations << 'E-NET-DELEGATION-LOOPBACK-ESCAPE'
    end

    # Condition 5 — Host Scope Inclusion
    unless host_subset?(child['allowed_hosts'], parent['allowed_hosts'])
      violations << 'E-NET-DELEGATION-HOST-ESCAPE'
    end

    # Condition 6 — Port Range Inclusion
    unless range_subset?(child['allowed_port_ranges'], parent['allowed_port_ranges'])
      violations << 'E-NET-DELEGATION-PORT-ESCAPE'
    end

    # Condition 7 — TLS Non-Downgrade
    if parent['tls_required'] && !child['tls_required']
      violations << 'E-NET-DELEGATION-TLS-DOWNGRADE'
    end

    # Condition 8 — Bind Address Non-Escalation
    if !parent['bind_address'].nil? &&
       !child['bind_address'].nil? &&
       child['bind_address'] != parent['bind_address']
      violations << 'E-NET-DELEGATION-BIND-ESCALATION'
    end

    { valid: violations.empty?, violations: violations }
  end

  # Compose helper: most restrictive protocol
  def self.most_restrictive_protocol(p1, p2)
    return p1 if p1 == p2
    # one is tcp_udp, the other is tcp or udp → return the more specific
    if p1 == 'tcp_udp'
      return p2
    elsif p2 == 'tcp_udp'
      return p1
    end
    # conflicting (e.g., tcp vs udp)
    'none'
  end

  # intersect_hosts
  def self.intersect_hosts(h1, h2)
    return h2 if h1.include?('*')
    return h1 if h2.include?('*')
    (h1 & h2)
  end

  # intersect_port_ranges: pairwise overlap of each pair
  def self.intersect_port_ranges(r1, r2)
    result = []
    r1.each do |a|
      r2.each do |b|
        lo = [a['min'], b['min']].max
        hi = [a['max'], b['max']].min
        result << { 'min' => lo, 'max' => hi } if lo <= hi
      end
    end
    result
  end

  # compose(g1, g2) → Hash
  def self.compose(g1, g2)
    {
      'resource_type'       => 'network',
      'protocol'            => most_restrictive_protocol(g1['protocol'], g2['protocol']),
      'allowed_hosts'       => intersect_hosts(g1['allowed_hosts'], g2['allowed_hosts']),
      'allowed_port_ranges' => intersect_port_ranges(g1['allowed_port_ranges'], g2['allowed_port_ranges']),
      'connect_allowed'     => g1['connect_allowed']  && g2['connect_allowed'],
      'listen_allowed'      => g1['listen_allowed']   && g2['listen_allowed'],
      'send_allowed'        => g1['send_allowed']     && g2['send_allowed'],
      'receive_allowed'     => g1['receive_allowed']  && g2['receive_allowed'],
      'loopback_only'       => g1['loopback_only']    || g2['loopback_only'],
      'tls_required'        => g1['tls_required']     || g2['tls_required']
    }
  end
end

module PassportValidator
  REQUIRED_TOP_LEVEL = %w[
    runtime_implementation_id backend_implementation_id
    consumer_surface_id surface_dimension artifact_kind artifact_digest
    capability_bindings required_capabilities
  ].freeze

  FILE_REQUIRED_FIELDS = %w[
    capability_id resource_type sandbox_dir allowed_absolute_paths
    read_allowed write_allowed
  ].freeze

  def self.validate_file_capability(cap)
    errors = []
    FILE_REQUIRED_FIELDS.each do |f|
      errors << "file cap missing field: #{f}" unless cap.key?(f)
    end
    if cap['resource_type'] != 'file'
      errors << "file cap resource_type must be \"file\", got #{cap['resource_type'].inspect}"
    end
    errors
  end

  def self.validate_passport(passport)
    errors = []

    unless passport.is_a?(Hash)
      return { valid: false, errors: ['passport must be a JSON object'] }
    end

    # Required top-level fields
    REQUIRED_TOP_LEVEL.each do |f|
      errors << "missing top-level field: #{f}" unless passport.key?(f)
    end

    return { valid: false, errors: errors } unless errors.empty?

    bindings = passport['capability_bindings']
    caps     = passport['required_capabilities']

    unless bindings.is_a?(Hash)
      errors << 'capability_bindings must be an object'
    end
    unless caps.is_a?(Hash)
      errors << 'required_capabilities must be an object'
    end

    return { valid: false, errors: errors } unless errors.empty?

    # capability_bindings keys must match required_capabilities keys
    binding_keys = Set.new(bindings.keys)
    cap_keys     = Set.new(caps.keys)
    unless binding_keys == cap_keys
      extra_bindings = binding_keys - cap_keys
      missing_bindings = cap_keys - binding_keys
      errors << "capability_bindings keys do not match required_capabilities keys: extra=#{extra_bindings.to_a.inspect} missing=#{missing_bindings.to_a.inspect}" unless extra_bindings.empty? && missing_bindings.empty?
    end

    # Dispatch each capability to the correct validator
    caps.each do |key, cap|
      unless cap.is_a?(Hash)
        errors << "required_capabilities.#{key} must be an object"
        next
      end

      case cap['resource_type']
      when 'network'
        result = NetworkCapabilityValidator.validate_schema(cap)
        unless result[:valid]
          result[:errors].each { |e| errors << "required_capabilities.#{key}: #{e}" }
        end
      when 'file'
        file_errors = validate_file_capability(cap)
        file_errors.each { |e| errors << "required_capabilities.#{key}: #{e}" }
      else
        errors << "required_capabilities.#{key}: unknown resource_type #{cap['resource_type'].inspect}"
      end
    end

    { valid: errors.empty?, errors: errors }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Part B — C ABI FFI Surface Spec (Rust source — not yet implemented)
# ═══════════════════════════════════════════════════════════════════════════════
#
# extern "C" fn stdlib_io_network_connect(host: *const c_char, port: *const c_char, cap_json: *const c_char) -> *mut c_char
# extern "C" fn stdlib_io_network_listen(bind_addr: *const c_char, port: *const c_char, cap_json: *const c_char) -> *mut c_char
# extern "C" fn stdlib_io_network_accept(listener_id: *const c_char, cap_json: *const c_char) -> *mut c_char
# extern "C" fn stdlib_io_network_send(conn_id: *const c_char, data: *const c_char, cap_json: *const c_char) -> *mut c_char
# extern "C" fn stdlib_io_network_receive(conn_id: *const c_char, max_bytes: *const c_char, cap_json: *const c_char) -> *mut c_char
# extern "C" fn stdlib_io_network_close(conn_id: *const c_char, cap_json: *const c_char) -> *mut c_char
# extern "C" fn stdlib_io_network_free_string(ptr: *mut c_char)

# ═══════════════════════════════════════════════════════════════════════════════
# Part C — Return Taxonomy Types
# ═══════════════════════════════════════════════════════════════════════════════
#
# ConnectReceipt (ok value for connect):
#   { "connection_id": String, "host": String, "port": Integer, "protocol": String,
#     "timestamp": Integer, "capability_id": String, "stub_mode": true }
#
# ListenReceipt (ok value for listen):
#   { "listener_id": String, "bind_address": String|null, "port": Integer, "protocol": String,
#     "timestamp": Integer, "capability_id": String, "stub_mode": true }
#
# AcceptReceipt (ok value for accept):
#   { "connection_id": String, "listener_id": String, "peer_address": String, "peer_port": Integer,
#     "timestamp": Integer, "capability_id": String, "stub_mode": true }
#
# SendReceipt (ok value for send):
#   { "bytes_sent": Integer, "connection_id": String, "timestamp": Integer,
#     "capability_id": String, "stub_mode": true }
#
# ReceiveObservation (ok value for receive):
#   { "data": String, "bytes_received": Integer, "connection_id": String,
#     "timestamp": Integer, "capability_id": String, "stub_mode": true }
#
# CloseReceipt (ok value for close):
#   { "connection_id": String, "timestamp": Integer,
#     "capability_id": String, "stub_mode": true }
#
# NetworkError (err value for all):
#   { "error_type": String, "message": String, "code": String, "capability_id": String|null }
#
# Error types:
#   "CapabilityError"     — NET policy violation (E-NET-* code in "code" field)
#   "ConnectionNotFound"  — conn_id not in registry
#   "ListenerNotFound"    — listener_id not in registry
#   "InvalidJson"         — malformed JSON argument
#   "StubModeError"       — operation refused because stub cannot perform real I/O
#   "ProtocolError"       — operation incompatible with connection protocol

# ═══════════════════════════════════════════════════════════════════════════════
# Part D — In-memory Connection Registry
# ═══════════════════════════════════════════════════════════════════════════════

module NetworkFFIStub
  # Thread-unsafe proof-local registry — not for production use
  CONNECTIONS = {}   # conn_id → { "host" => ..., "port" => ..., "protocol" => ..., "capability_id" => ..., "open" => true }
  LISTENERS   = {}   # listener_id → { "bind_address" => ..., "port" => ..., "protocol" => ..., "capability_id" => ..., "open" => true }

  def self.reset!
    CONNECTIONS.clear
    LISTENERS.clear
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  def self.ok(value)
    JSON.generate({ 'ok' => value })
  end

  def self.err(error_type, message, code: nil, cap_id: nil)
    payload = {
      'error_type'    => error_type,
      'message'       => message,
      'capability_id' => cap_id
    }
    payload['code'] = code if code
    JSON.generate({ 'err' => payload })
  end

  def self.parse_cap(cap_json)
    cap = JSON.parse(cap_json)
    [cap, nil]
  rescue JSON::ParserError => e
    [nil, err('InvalidJson', "Malformed capability JSON: #{e.message}", code: 'E-INVALID-JSON')]
  end

  def self.validate_cap(cap)
    result = NetworkCapabilityValidator.validate_schema(cap)
    return nil if result[:valid]
    err('CapabilityError', "Capability schema invalid: #{result[:errors].join('; ')}",
        code: 'E-NET-SCHEMA-INVALID', cap_id: cap['capability_id'])
  end

  def self.check_policy(cap, check_result)
    return nil if check_result[:ok]
    err('CapabilityError', "Policy violation: #{check_result[:code]}",
        code: check_result[:code], cap_id: cap['capability_id'])
  end

  def self.now_ts
    Time.now.to_i
  end

  # ─── Part E: FFI Function Implementations ───────────────────────────────────

  # stdlib_io_network_connect(host, port_str, cap_json) → JSON string
  # Simulates: extern "C" fn stdlib_io_network_connect(...) -> *mut c_char
  def self.stdlib_io_network_connect(host, port_str, cap_json)
    cap, parse_err = parse_cap(cap_json)
    return parse_err if parse_err

    if (schema_err = validate_cap(cap))
      return schema_err
    end

    # NET-5: tls_required check — stub cannot establish TLS, must refuse
    if cap['tls_required']
      return err('StubModeError',
                 'tls_required: true — stub cannot verify or negotiate TLS; refusing connection to prevent silent plaintext',
                 code: 'E-STUB-TLS-UNVERIFIABLE', cap_id: cap['capability_id'])
    end

    port = port_str.to_i

    # NET-1: Loopback Bound
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net1(cap, host)))
      return policy_err
    end

    # NET-2: Host Allowlist
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net2(cap, host)))
      return policy_err
    end

    # NET-4: connect_allowed
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net4(cap, :connect)))
      return policy_err
    end

    # NET-3: Port Range
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net3(cap, port)))
      return policy_err
    end

    # NET-6: Protocol (stub uses tcp for all connections)
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net6(cap, 'tcp')))
      return policy_err
    end

    conn_id = "conn-#{SecureRandom.hex(8)}"
    CONNECTIONS[conn_id] = {
      'host'          => host,
      'port'          => port,
      'protocol'      => 'tcp',
      'capability_id' => cap['capability_id'],
      'open'          => true
    }

    ok({
      'connection_id' => conn_id,
      'host'          => host,
      'port'          => port,
      'protocol'      => 'tcp',
      'timestamp'     => now_ts,
      'capability_id' => cap['capability_id'],
      'stub_mode'     => true
    })
  end

  # stdlib_io_network_listen(bind_addr_str, port_str, cap_json) → JSON string
  # Simulates: extern "C" fn stdlib_io_network_listen(...) -> *mut c_char
  def self.stdlib_io_network_listen(bind_addr_str, port_str, cap_json)
    cap, parse_err = parse_cap(cap_json)
    return parse_err if parse_err

    if (schema_err = validate_cap(cap))
      return schema_err
    end

    bind_addr = (bind_addr_str == 'null' || bind_addr_str.nil? || bind_addr_str.empty?) ? nil : bind_addr_str
    port = port_str.to_i

    # NET-4: listen_allowed
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net4(cap, :listen)))
      return policy_err
    end

    # NET-3: Port Range
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net3(cap, port)))
      return policy_err
    end

    # NET-1: If bind_addr given and loopback_only: true, bind_addr must be loopback
    if bind_addr && (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net1(cap, bind_addr)))
      return policy_err
    end

    # NET-6: Protocol
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net6(cap, 'tcp')))
      return policy_err
    end

    listener_id = "lst-#{SecureRandom.hex(8)}"
    LISTENERS[listener_id] = {
      'bind_address'  => bind_addr,
      'port'          => port,
      'protocol'      => 'tcp',
      'capability_id' => cap['capability_id'],
      'open'          => true
    }

    ok({
      'listener_id'  => listener_id,
      'bind_address' => bind_addr,
      'port'         => port,
      'protocol'     => 'tcp',
      'timestamp'    => now_ts,
      'capability_id' => cap['capability_id'],
      'stub_mode'    => true
    })
  end

  # stdlib_io_network_accept(listener_id_str, cap_json) → JSON string
  # Simulates: extern "C" fn stdlib_io_network_accept(...) -> *mut c_char
  def self.stdlib_io_network_accept(listener_id_str, cap_json)
    cap, parse_err = parse_cap(cap_json)
    return parse_err if parse_err

    if (schema_err = validate_cap(cap))
      return schema_err
    end

    unless LISTENERS.key?(listener_id_str) && LISTENERS[listener_id_str]['open']
      return err('ListenerNotFound',
                 "Listener #{listener_id_str.inspect} not found or not open",
                 code: 'E-NET-LISTENER-NOT-FOUND', cap_id: cap['capability_id'])
    end

    # NET-4: listen_allowed AND receive_allowed
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net4(cap, :listen)))
      return policy_err
    end
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net4(cap, :receive)))
      return policy_err
    end

    conn_id = "conn-#{SecureRandom.hex(8)}"
    listener = LISTENERS[listener_id_str]
    CONNECTIONS[conn_id] = {
      'host'          => '127.0.0.1',
      'port'          => listener['port'],
      'protocol'      => listener['protocol'],
      'capability_id' => cap['capability_id'],
      'open'          => true
    }

    ok({
      'connection_id' => conn_id,
      'listener_id'   => listener_id_str,
      'peer_address'  => '127.0.0.1',
      'peer_port'     => 49152 + (SecureRandom.random_number(16383)),
      'timestamp'     => now_ts,
      'capability_id' => cap['capability_id'],
      'stub_mode'     => true
    })
  end

  # stdlib_io_network_send(conn_id_str, data_str, cap_json) → JSON string
  # Simulates: extern "C" fn stdlib_io_network_send(...) -> *mut c_char
  def self.stdlib_io_network_send(conn_id_str, data_str, cap_json)
    cap, parse_err = parse_cap(cap_json)
    return parse_err if parse_err

    if (schema_err = validate_cap(cap))
      return schema_err
    end

    unless CONNECTIONS.key?(conn_id_str) && CONNECTIONS[conn_id_str]['open']
      return err('ConnectionNotFound',
                 "Connection #{conn_id_str.inspect} not found or not open",
                 code: 'E-NET-CONNECTION-NOT-FOUND', cap_id: cap['capability_id'])
    end

    # NET-4: send_allowed
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net4(cap, :send)))
      return policy_err
    end

    # NET-6: Protocol matches connection's protocol
    conn_proto = CONNECTIONS[conn_id_str]['protocol']
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net6(cap, conn_proto)))
      return policy_err
    end

    ok({
      'bytes_sent'    => data_str.bytesize,
      'connection_id' => conn_id_str,
      'timestamp'     => now_ts,
      'capability_id' => cap['capability_id'],
      'stub_mode'     => true
    })
  end

  # stdlib_io_network_receive(conn_id_str, max_bytes_str, cap_json) → JSON string
  # Simulates: extern "C" fn stdlib_io_network_receive(...) -> *mut c_char
  def self.stdlib_io_network_receive(conn_id_str, max_bytes_str, cap_json)
    cap, parse_err = parse_cap(cap_json)
    return parse_err if parse_err

    if (schema_err = validate_cap(cap))
      return schema_err
    end

    unless CONNECTIONS.key?(conn_id_str) && CONNECTIONS[conn_id_str]['open']
      return err('ConnectionNotFound',
                 "Connection #{conn_id_str.inspect} not found or not open",
                 code: 'E-NET-CONNECTION-NOT-FOUND', cap_id: cap['capability_id'])
    end

    # NET-4: receive_allowed
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net4(cap, :receive)))
      return policy_err
    end

    # NET-6: Protocol matches connection's protocol
    conn_proto = CONNECTIONS[conn_id_str]['protocol']
    if (policy_err = check_policy(cap, NetworkCapabilityValidator.check_policy_net6(cap, conn_proto)))
      return policy_err
    end

    max_bytes = max_bytes_str.to_i
    stub_data = 'stub_receive_data'
    data = stub_data[0, max_bytes] || ''

    ok({
      'data'           => data,
      'bytes_received' => data.bytesize,
      'connection_id'  => conn_id_str,
      'timestamp'      => now_ts,
      'capability_id'  => cap['capability_id'],
      'stub_mode'      => true
    })
  end

  # stdlib_io_network_close(conn_id_str, cap_json) → JSON string
  # Simulates: extern "C" fn stdlib_io_network_close(...) -> *mut c_char
  def self.stdlib_io_network_close(conn_id_str, cap_json)
    cap, parse_err = parse_cap(cap_json)
    return parse_err if parse_err

    if (schema_err = validate_cap(cap))
      return schema_err
    end

    unless CONNECTIONS.key?(conn_id_str)
      return err('ConnectionNotFound',
                 "Connection #{conn_id_str.inspect} not found",
                 code: 'E-NET-CONNECTION-NOT-FOUND', cap_id: cap['capability_id'])
    end

    CONNECTIONS[conn_id_str]['open'] = false

    ok({
      'connection_id' => conn_id_str,
      'timestamp'     => now_ts,
      'capability_id' => cap['capability_id'],
      'stub_mode'     => true
    })
  end

  # stdlib_io_network_free_string — no-op in Ruby stub (GC handles memory)
  # Simulates: extern "C" fn stdlib_io_network_free_string(ptr: *mut c_char)
  def self.stdlib_io_network_free_string(_ptr)
    # No-op: Ruby GC manages memory. In Rust, this would call Box::from_raw / CString::from_raw.
    nil
  end
end
