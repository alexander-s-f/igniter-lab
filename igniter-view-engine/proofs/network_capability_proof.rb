# frozen_string_literal: true
# Proof: IO.NetworkCapability — Delegation Algebra
# Card: LAB-STDLIB-NET-P2
# Surface: lab-only, proof-local evidence only.
# No canon claim, no public API, no stable schema.
# No real TCP sockets opened — in-memory schema validation only.

require 'json'
require 'pathname'
require 'set'

FIXTURE_DIR = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'network_capability'

# ═══════════════════════════════════════════════════════════════════════════════
# Module A: NetworkCapabilityValidator
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

# ═══════════════════════════════════════════════════════════════════════════════
# Module B: NetworkDelegationAlgebra
# ═══════════════════════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════════════════════
# Module C: PassportValidator
# ═══════════════════════════════════════════════════════════════════════════════

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
# Result tracking helpers
# ═══════════════════════════════════════════════════════════════════════════════

$results = []

def pass_check(group, check)
  $results << { status: 'PASS', group: group, check: check }
  print '.'
end

def fail_check(group, check, detail = nil)
  $results << { status: 'FAIL', group: group, check: check, detail: detail }
  print 'F'
end

def assert_pass(group, check, condition, detail = nil)
  if condition
    pass_check(group, check)
  else
    fail_check(group, check, detail || 'expected true, got false')
  end
end

def assert_fail(group, check, condition, expected_code, actual_code)
  if condition && actual_code == expected_code
    pass_check(group, check)
  elsif !condition
    fail_check(group, check, "expected failure but got success")
  else
    fail_check(group, check, "expected code #{expected_code}, got #{actual_code.inspect}")
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Load fixtures
# ═══════════════════════════════════════════════════════════════════════════════

var_a = JSON.parse((FIXTURE_DIR / 'variant_a_loopback_connect.json').read(encoding: 'UTF-8'))
var_b = JSON.parse((FIXTURE_DIR / 'variant_b_localhost_listen.json').read(encoding: 'UTF-8'))
var_c = JSON.parse((FIXTURE_DIR / 'variant_c_https_outbound.json').read(encoding: 'UTF-8'))
passport = JSON.parse((FIXTURE_DIR / 'mixed_passport.json').read(encoding: 'UTF-8'))

# ═══════════════════════════════════════════════════════════════════════════════
# SCHEMA VALIDATION CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

r = NetworkCapabilityValidator.validate_schema(var_a)
assert_pass('schema', 'NET-SCHEMA-1', r[:valid], r[:errors].inspect)

r = NetworkCapabilityValidator.validate_schema(var_b)
assert_pass('schema', 'NET-SCHEMA-2', r[:valid], r[:errors].inspect)

r = NetworkCapabilityValidator.validate_schema(var_c)
assert_pass('schema', 'NET-SCHEMA-3', r[:valid], r[:errors].inspect)

# ═══════════════════════════════════════════════════════════════════════════════
# SAFETY POLICY CHECKS — Variant A
# ═══════════════════════════════════════════════════════════════════════════════

r = NetworkCapabilityValidator.check_policy_net1(var_a, '127.0.0.1')
assert_pass('policy', 'NET-POLICY-A1', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net1(var_a, '10.0.0.1')
assert_fail('policy', 'NET-POLICY-A2', !r[:ok], 'E-NET-LOOPBACK-VIOLATION', r[:code])

r = NetworkCapabilityValidator.check_policy_net2(var_a, '127.0.0.1')
assert_pass('policy', 'NET-POLICY-A3', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net2(var_a, '192.168.1.1')
assert_fail('policy', 'NET-POLICY-A4', !r[:ok], 'E-NET-HOST-BLOCKED', r[:code])

r = NetworkCapabilityValidator.check_policy_net3(var_a, 8080)
assert_pass('policy', 'NET-POLICY-A5', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net3(var_a, 80)
assert_fail('policy', 'NET-POLICY-A6', !r[:ok], 'E-NET-PORT-BLOCKED', r[:code])

r = NetworkCapabilityValidator.check_policy_net4(var_a, :connect)
assert_pass('policy', 'NET-POLICY-A7', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net4(var_a, :listen)
assert_fail('policy', 'NET-POLICY-A8', !r[:ok], 'E-NET-DIRECTION-BLOCKED', r[:code])

r = NetworkCapabilityValidator.check_policy_net5(var_a, false)
assert_pass('policy', 'NET-POLICY-A9', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net6(var_a, 'tcp')
assert_pass('policy', 'NET-POLICY-A10', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net6(var_a, 'udp')
assert_fail('policy', 'NET-POLICY-A11', !r[:ok], 'E-NET-PROTOCOL-MISMATCH', r[:code])

# ═══════════════════════════════════════════════════════════════════════════════
# SAFETY POLICY CHECKS — Variant C
# ═══════════════════════════════════════════════════════════════════════════════

r = NetworkCapabilityValidator.check_policy_net5(var_c, true)
assert_pass('policy', 'NET-POLICY-C1', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net5(var_c, false)
assert_fail('policy', 'NET-POLICY-C2', !r[:ok], 'E-NET-TLS-REQUIRED', r[:code])

r = NetworkCapabilityValidator.check_policy_net2(var_c, 'api.example.com')
assert_pass('policy', 'NET-POLICY-C3', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net2(var_c, 'evil.com')
assert_fail('policy', 'NET-POLICY-C4', !r[:ok], 'E-NET-HOST-BLOCKED', r[:code])

r = NetworkCapabilityValidator.check_policy_net3(var_c, 443)
assert_pass('policy', 'NET-POLICY-C5', r[:ok], r[:code])

r = NetworkCapabilityValidator.check_policy_net3(var_c, 80)
assert_fail('policy', 'NET-POLICY-C6', !r[:ok], 'E-NET-PORT-BLOCKED', r[:code])

# ═══════════════════════════════════════════════════════════════════════════════
# DELEGATION ALGEBRA CHECKS — Valid delegations (PASS)
# ═══════════════════════════════════════════════════════════════════════════════

# NET-DELEG-1: A delegates to itself (identity)
r = NetworkDelegationAlgebra.valid_delegation?(var_a, var_a)
assert_pass('delegation', 'NET-DELEG-1', r[:valid], r[:violations].inspect)

# NET-DELEG-2: A → narrowed child (subset hosts, subset port range)
child2 = var_a.merge(
  'allowed_hosts'       => ['127.0.0.1'],
  'allowed_port_ranges' => [{ 'min' => 8080, 'max' => 8080 }]
)
r = NetworkDelegationAlgebra.valid_delegation?(var_a, child2)
assert_pass('delegation', 'NET-DELEG-2', r[:valid], r[:violations].inspect)

# NET-DELEG-3: tcp_udp parent → tcp child (protocol narrowing)
parent3 = var_a.merge('protocol' => 'tcp_udp')
child3  = var_a.merge('protocol' => 'tcp')
r = NetworkDelegationAlgebra.valid_delegation?(parent3, child3)
assert_pass('delegation', 'NET-DELEG-3', r[:valid], r[:violations].inspect)

# NET-DELEG-4: Non-loopback parent, loopback child (loopback strengthening)
parent4 = var_a.merge('loopback_only' => false)
child4  = var_a.merge('loopback_only' => true)
r = NetworkDelegationAlgebra.valid_delegation?(parent4, child4)
assert_pass('delegation', 'NET-DELEG-4', r[:valid], r[:violations].inspect)

# NET-DELEG-5: Non-TLS parent, TLS child (TLS strengthening)
parent5 = var_a.merge('tls_required' => false)
child5  = var_a.merge('tls_required' => true)
r = NetworkDelegationAlgebra.valid_delegation?(parent5, child5)
assert_pass('delegation', 'NET-DELEG-5', r[:valid], r[:violations].inspect)

# NET-DELEG-6: B delegates to itself (identity)
r = NetworkDelegationAlgebra.valid_delegation?(var_b, var_b)
assert_pass('delegation', 'NET-DELEG-6', r[:valid], r[:violations].inspect)

# NET-DELEG-7: Null bind_address parent → specific bind_address child
parent7 = var_c.merge('bind_address' => nil)
child7  = var_c.merge('bind_address' => '127.0.0.1')
r = NetworkDelegationAlgebra.valid_delegation?(parent7, child7)
assert_pass('delegation', 'NET-DELEG-7', r[:valid], r[:violations].inspect)

# ═══════════════════════════════════════════════════════════════════════════════
# DELEGATION ALGEBRA CHECKS — Violations (FAIL with correct error code)
# ═══════════════════════════════════════════════════════════════════════════════

# NET-DELEG-8: Protocol escalation: parent=tcp, child=tcp_udp
child8 = var_a.merge('protocol' => 'tcp_udp')
r = NetworkDelegationAlgebra.valid_delegation?(var_a, child8)
has_code = r[:violations].include?('E-NET-DELEGATION-PROTOCOL-ESCALATION')
assert_fail('delegation', 'NET-DELEG-8', !r[:valid], 'E-NET-DELEGATION-PROTOCOL-ESCALATION',
            has_code ? 'E-NET-DELEGATION-PROTOCOL-ESCALATION' : r[:violations].first)

# NET-DELEG-9: Protocol mismatch: parent=tcp, child=udp
child9 = var_a.merge('protocol' => 'udp')
r = NetworkDelegationAlgebra.valid_delegation?(var_a, child9)
has_code = r[:violations].include?('E-NET-DELEGATION-PROTOCOL-ESCALATION')
assert_fail('delegation', 'NET-DELEG-9', !r[:valid], 'E-NET-DELEGATION-PROTOCOL-ESCALATION',
            has_code ? 'E-NET-DELEGATION-PROTOCOL-ESCALATION' : r[:violations].first)

# NET-DELEG-10: Permission escalation: parent listen=false, child listen=true
child10 = var_a.merge('listen_allowed' => true)
r = NetworkDelegationAlgebra.valid_delegation?(var_a, child10)
has_code = r[:violations].include?('E-NET-DELEGATION-PERMISSION-ESCALATION')
assert_fail('delegation', 'NET-DELEG-10', !r[:valid], 'E-NET-DELEGATION-PERMISSION-ESCALATION',
            has_code ? 'E-NET-DELEGATION-PERMISSION-ESCALATION' : r[:violations].first)

# NET-DELEG-11: Loopback escape: parent=true, child=false
child11 = var_a.merge('loopback_only' => false)
r = NetworkDelegationAlgebra.valid_delegation?(var_a, child11)
has_code = r[:violations].include?('E-NET-DELEGATION-LOOPBACK-ESCAPE')
assert_fail('delegation', 'NET-DELEG-11', !r[:valid], 'E-NET-DELEGATION-LOOPBACK-ESCAPE',
            has_code ? 'E-NET-DELEGATION-LOOPBACK-ESCAPE' : r[:violations].first)

# NET-DELEG-12: Host escape: parent=["127.0.0.1"], child adds "10.0.0.1"
child12 = var_a.merge('allowed_hosts' => ['127.0.0.1', '10.0.0.1'])
r = NetworkDelegationAlgebra.valid_delegation?(var_a, child12)
has_code = r[:violations].include?('E-NET-DELEGATION-HOST-ESCAPE')
assert_fail('delegation', 'NET-DELEG-12', !r[:valid], 'E-NET-DELEGATION-HOST-ESCAPE',
            has_code ? 'E-NET-DELEGATION-HOST-ESCAPE' : r[:violations].first)

# NET-DELEG-13: Port escape: parent=[8000,9000], child=[8000,10000]
parent13 = var_a.merge('allowed_port_ranges' => [{ 'min' => 8000, 'max' => 9000 }])
child13  = var_a.merge('allowed_port_ranges' => [{ 'min' => 8000, 'max' => 10000 }])
r = NetworkDelegationAlgebra.valid_delegation?(parent13, child13)
has_code = r[:violations].include?('E-NET-DELEGATION-PORT-ESCAPE')
assert_fail('delegation', 'NET-DELEG-13', !r[:valid], 'E-NET-DELEGATION-PORT-ESCAPE',
            has_code ? 'E-NET-DELEGATION-PORT-ESCAPE' : r[:violations].first)

# NET-DELEG-14: TLS downgrade: parent=true, child=false
parent14 = var_a.merge('tls_required' => true)
child14  = var_a.merge('tls_required' => false)
r = NetworkDelegationAlgebra.valid_delegation?(parent14, child14)
has_code = r[:violations].include?('E-NET-DELEGATION-TLS-DOWNGRADE')
assert_fail('delegation', 'NET-DELEG-14', !r[:valid], 'E-NET-DELEGATION-TLS-DOWNGRADE',
            has_code ? 'E-NET-DELEGATION-TLS-DOWNGRADE' : r[:violations].first)

# NET-DELEG-15: Bind escalation: parent=127.0.0.1, child=0.0.0.0
parent15 = var_a.merge('bind_address' => '127.0.0.1')
child15  = var_a.merge('bind_address' => '0.0.0.0')
r = NetworkDelegationAlgebra.valid_delegation?(parent15, child15)
has_code = r[:violations].include?('E-NET-DELEGATION-BIND-ESCALATION')
assert_fail('delegation', 'NET-DELEG-15', !r[:valid], 'E-NET-DELEGATION-BIND-ESCALATION',
            has_code ? 'E-NET-DELEGATION-BIND-ESCALATION' : r[:violations].first)

# ═══════════════════════════════════════════════════════════════════════════════
# COMPOSE OPERATOR CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

# NET-COMPOSE-1: A ∧ A = A (identity)
composed1 = NetworkDelegationAlgebra.compose(var_a, var_a)
ok1 = composed1['connect_allowed'] == true &&
      composed1['listen_allowed']  == false &&
      composed1['send_allowed']    == true &&
      composed1['receive_allowed'] == true &&
      composed1['loopback_only']   == true &&
      composed1['tls_required']    == false
assert_pass('compose', 'NET-COMPOSE-1', ok1, composed1.inspect)

# NET-COMPOSE-2: loopback=false ∧ loopback=true → loopback_only:true
g2a = var_a.merge('loopback_only' => false)
g2b = var_a.merge('loopback_only' => true)
composed2 = NetworkDelegationAlgebra.compose(g2a, g2b)
assert_pass('compose', 'NET-COMPOSE-2', composed2['loopback_only'] == true,
            "expected loopback_only=true, got #{composed2['loopback_only']}")

# NET-COMPOSE-3: tls=false ∧ tls=true → tls_required:true
g3a = var_a.merge('tls_required' => false)
g3b = var_a.merge('tls_required' => true)
composed3 = NetworkDelegationAlgebra.compose(g3a, g3b)
assert_pass('compose', 'NET-COMPOSE-3', composed3['tls_required'] == true,
            "expected tls_required=true, got #{composed3['tls_required']}")

# NET-COMPOSE-4: connect-only ∧ listen-only → neither
g4a = var_a.merge('connect_allowed' => true,  'listen_allowed' => false)
g4b = var_a.merge('connect_allowed' => false, 'listen_allowed' => true)
composed4 = NetworkDelegationAlgebra.compose(g4a, g4b)
ok4 = composed4['connect_allowed'] == false && composed4['listen_allowed'] == false
assert_pass('compose', 'NET-COMPOSE-4', ok4,
            "expected connect=false,listen=false got connect=#{composed4['connect_allowed']},listen=#{composed4['listen_allowed']}")

# NET-COMPOSE-5: Port range intersection: [1000,5000] ∧ [3000,8000] = [3000,5000]
g5a = var_a.merge('allowed_port_ranges' => [{ 'min' => 1000, 'max' => 5000 }])
g5b = var_a.merge('allowed_port_ranges' => [{ 'min' => 3000, 'max' => 8000 }])
composed5 = NetworkDelegationAlgebra.compose(g5a, g5b)
expected_ranges5 = [{ 'min' => 3000, 'max' => 5000 }]
assert_pass('compose', 'NET-COMPOSE-5', composed5['allowed_port_ranges'] == expected_ranges5,
            "expected #{expected_ranges5.inspect}, got #{composed5['allowed_port_ranges'].inspect}")

# NET-COMPOSE-6: Host intersection: ["a","b"] ∧ ["b","c"] = ["b"]
g6a = var_a.merge('allowed_hosts' => %w[a b])
g6b = var_a.merge('allowed_hosts' => %w[b c])
composed6 = NetworkDelegationAlgebra.compose(g6a, g6b)
assert_pass('compose', 'NET-COMPOSE-6', composed6['allowed_hosts'] == ['b'],
            "expected [\"b\"], got #{composed6['allowed_hosts'].inspect}")

# NET-COMPOSE-7: Protocol: tcp ∧ tcp_udp → tcp
g7a = var_a.merge('protocol' => 'tcp')
g7b = var_a.merge('protocol' => 'tcp_udp')
composed7 = NetworkDelegationAlgebra.compose(g7a, g7b)
assert_pass('compose', 'NET-COMPOSE-7', composed7['protocol'] == 'tcp',
            "expected \"tcp\", got #{composed7['protocol'].inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# PASSPORT VALIDATION CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

# NET-PASSPORT-1: mixed_passport.json is valid
r = PassportValidator.validate_passport(passport)
assert_pass('passport', 'NET-PASSPORT-1', r[:valid], r[:errors].inspect)

# NET-PASSPORT-2: capability_bindings keys match required_capabilities keys
bindings_keys = Set.new(passport['capability_bindings'].keys)
caps_keys     = Set.new(passport['required_capabilities'].keys)
assert_pass('passport', 'NET-PASSPORT-2', bindings_keys == caps_keys,
            "bindings=#{bindings_keys.to_a.sort.inspect} caps=#{caps_keys.to_a.sort.inspect}")

# NET-PASSPORT-3: resource_type dispatches correctly
# network cap should pass network schema; file cap should pass file schema
net_cap  = passport['required_capabilities']['net_outbound']
file_cap = passport['required_capabilities']['io_file_read']
net_schema_r  = NetworkCapabilityValidator.validate_schema(net_cap)
file_schema_r = NetworkCapabilityValidator.validate_schema(file_cap)  # should FAIL (wrong resource_type)
assert_pass('passport', 'NET-PASSPORT-3',
            net_schema_r[:valid] && !file_schema_r[:valid],
            "net_valid=#{net_schema_r[:valid]} file_as_net_valid=#{file_schema_r[:valid]}")

# NET-PASSPORT-4: Invalid passport (missing required field) → validation fails
invalid_passport = passport.reject { |k, _| k == 'artifact_digest' }
r = PassportValidator.validate_passport(invalid_passport)
assert_pass('passport', 'NET-PASSPORT-4', !r[:valid] && r[:errors].any? { |e| e.include?('artifact_digest') },
            "expected invalid, errors=#{r[:errors].inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# EDGE CASE CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

# NET-EDGE-1: Empty allowed_hosts → all hosts blocked
cap_empty_hosts = var_a.merge('allowed_hosts' => [])
r = NetworkCapabilityValidator.check_policy_net2(cap_empty_hosts, 'any.host.com')
assert_fail('edge', 'NET-EDGE-1', !r[:ok], 'E-NET-HOST-BLOCKED', r[:code])

# NET-EDGE-2: Empty allowed_port_ranges → all ports blocked
cap_empty_ports = var_a.merge('allowed_port_ranges' => [])
r = NetworkCapabilityValidator.check_policy_net3(cap_empty_ports, 8080)
assert_fail('edge', 'NET-EDGE-2', !r[:ok], 'E-NET-PORT-BLOCKED', r[:code])

# NET-EDGE-3: Wildcard host "*" matches any host
r = NetworkCapabilityValidator.check_policy_net2(var_b, 'totally.random.host.example')
assert_pass('edge', 'NET-EDGE-3', r[:ok], r[:code])

# NET-EDGE-4: Port boundary: port at exactly min of range → allowed
# Variant B range [3000,9999]
r = NetworkCapabilityValidator.check_policy_net3(var_b, 3000)
assert_pass('edge', 'NET-EDGE-4', r[:ok], r[:code])

# NET-EDGE-5: Port boundary: port at exactly max of range → allowed
r = NetworkCapabilityValidator.check_policy_net3(var_b, 9999)
assert_pass('edge', 'NET-EDGE-5', r[:ok], r[:code])

# NET-EDGE-6: Port boundary: port at min-1 → blocked
r = NetworkCapabilityValidator.check_policy_net3(var_b, 2999)
assert_fail('edge', 'NET-EDGE-6', !r[:ok], 'E-NET-PORT-BLOCKED', r[:code])

# NET-EDGE-7: resource_type mismatch: file capability validated as network → schema error
r = NetworkCapabilityValidator.validate_schema(file_cap)
assert_pass('edge', 'NET-EDGE-7', !r[:valid] && r[:errors].any? { |e| e.include?('resource_type') },
            "expected schema invalid due to resource_type, errors=#{r[:errors].inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# PRINT RESULTS MATRIX
# ═══════════════════════════════════════════════════════════════════════════════

puts "\n"
puts '=' * 72
puts 'NetworkCapability Proof — Results Matrix'
puts '=' * 72

col_group  = 12
col_check  = 24
col_status = 6

header = "  #{'GROUP'.ljust(col_group)} #{'CHECK'.ljust(col_check)} STATUS"
puts header
puts '-' * 72

current_group = nil
$results.each do |r|
  if r[:group] != current_group
    puts '' if current_group
    current_group = r[:group]
  end
  status_str = r[:status]
  line = "  #{r[:group].to_s.ljust(col_group)} #{r[:check].to_s.ljust(col_check)} #{status_str}"
  puts line
  puts "    Detail: #{r[:detail]}" if r[:detail] && r[:status] == 'FAIL'
end

puts '-' * 72

total   = $results.size
passing = $results.count { |r| r[:status] == 'PASS' }
failing = $results.count { |r| r[:status] == 'FAIL' }

puts "Total: #{total}  |  PASS: #{passing}  |  FAIL: #{failing}"
puts '=' * 72

if failing.zero?
  puts 'Result: ALL CHECKS PASSED'
  exit 0
else
  puts "Result: #{failing} CHECK(S) FAILED"
  exit 1
end
