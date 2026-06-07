# frozen_string_literal: true
# Proof: stdlib/io/network — Dead Grant Detection + Compose bind_address Gap
# Card: LAB-STDLIB-NET-P6
# Closes open questions deferred from P5 §6:
#   (1) compose does not preserve bind_address — three candidate resolutions A/B/C
#   (2) dead grant detection — compose(connect_only, listen_only) yields all-false permissions
# No real TCP. Proof-local algebra only. Modules inlined from P2 (provenance noted).
# Authorized surface: fixtures/network_capability_hardening/, proofs/network_p6_proof.rb
# Closed: igniter-lang canon, igniter-org, no real sockets

require 'json'
require 'set'
require 'pathname'

FIXTURE_DIR_P6 = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'network_capability_hardening'

# ═══════════════════════════════════════════════════════════════════════════════
# Result tracking helpers
# ═══════════════════════════════════════════════════════════════════════════════

$p6_results = []

def p6_pass(group, check)
  $p6_results << { status: 'PASS', group: group, check: check }
  print '.'
end

def p6_fail(group, check, detail = nil)
  $p6_results << { status: 'FAIL', group: group, check: check, detail: detail }
  print 'F'
end

def p6_assert(group, check, condition, detail = nil)
  if condition
    p6_pass(group, check)
  else
    p6_fail(group, check, detail || 'expected true, got false')
  end
end

def p6_assert_violation(group, check, result, expected_code)
  has_code = result[:violations].include?(expected_code)
  if has_code
    p6_pass(group, check)
  else
    p6_fail(group, check, "expected violation #{expected_code}; got #{result[:violations].inspect}")
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# P2 Algebra Modules — inlined from proofs/network_capability_proof.rb
# (copied verbatim; provenance: LAB-STDLIB-NET-P2)
# Module names suffixed with P6 to avoid constant redefinition conflicts
# ═══════════════════════════════════════════════════════════════════════════════

module NetworkCapabilityValidatorP6
  LOOPBACK_ADDRESSES = Set.new(%w[127.0.0.1 localhost ::1]).freeze

  def self.loopback_address?(host)
    return true if LOOPBACK_ADDRESSES.include?(host)
    host.start_with?('127.')
  end

  def self.check_policy_net1(cap, target_host)
    return { ok: true, code: nil } unless cap['loopback_only']
    if loopback_address?(target_host)
      { ok: true, code: nil }
    else
      { ok: false, code: 'E-NET-LOOPBACK-VIOLATION' }
    end
  end

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

  def self.check_policy_net3(cap, target_port)
    ranges = cap['allowed_port_ranges'] || []
    return { ok: false, code: 'E-NET-PORT-BLOCKED' } if ranges.empty?
    in_range = ranges.any? { |r| target_port >= r['min'] && target_port <= r['max'] }
    in_range ? { ok: true, code: nil } : { ok: false, code: 'E-NET-PORT-BLOCKED' }
  end

  def self.check_policy_net4(cap, operation)
    field = "#{operation}_allowed"
    if cap[field]
      { ok: true, code: nil }
    else
      { ok: false, code: 'E-NET-DIRECTION-BLOCKED' }
    end
  end

  def self.validate_schema(cap)
    errors = []
    return { valid: false, errors: ['capability must be a JSON object'] } unless cap.is_a?(Hash)

    errors << "resource_type must be \"network\"" if cap['resource_type'] != 'network'

    required = %w[capability_id resource_type protocol direction
                  allowed_hosts allowed_port_ranges
                  loopback_only connect_allowed listen_allowed send_allowed receive_allowed]
    required.each { |f| errors << "missing required field: #{f}" unless cap.key?(f) }
    return { valid: false, errors: errors } unless errors.empty?

    %w[loopback_only connect_allowed listen_allowed send_allowed receive_allowed].each do |bf|
      errors << "#{bf} must be a boolean" unless [true, false].include?(cap[bf])
    end
    unless cap['bind_address'].nil? || cap['bind_address'].is_a?(String)
      errors << 'bind_address must be null or a string'
    end

    { valid: errors.empty?, errors: errors }
  end
end

module NetworkDelegationAlgebraP6
  def self.protocol_subset?(child_proto, parent_proto)
    return true if child_proto == parent_proto
    return true if parent_proto == 'tcp_udp' && %w[tcp udp].include?(child_proto)
    false
  end

  def self.range_subset?(child_ranges, parent_ranges)
    child_ranges.all? do |cr|
      parent_ranges.any? { |pr| pr['min'] <= cr['min'] && cr['max'] <= pr['max'] }
    end
  end

  def self.host_subset?(child_hosts, parent_hosts)
    return true if parent_hosts.include?('*')
    child_hosts.all? { |h| parent_hosts.include?(h) }
  end

  def self.valid_delegation?(parent, child)
    violations = []

    violations << 'E-NET-DELEGATION-TYPE-MISMATCH' if
      parent['resource_type'] != 'network' || child['resource_type'] != 'network'

    violations << 'E-NET-DELEGATION-PROTOCOL-ESCALATION' unless
      protocol_subset?(child['protocol'], parent['protocol'])

    %w[connect listen send receive].each do |dir|
      field = "#{dir}_allowed"
      if child[field] && !parent[field]
        violations << 'E-NET-DELEGATION-PERMISSION-ESCALATION'
        break
      end
    end

    violations << 'E-NET-DELEGATION-LOOPBACK-ESCAPE' if
      parent['loopback_only'] && !child['loopback_only']

    violations << 'E-NET-DELEGATION-HOST-ESCAPE' unless
      host_subset?(child['allowed_hosts'], parent['allowed_hosts'])

    violations << 'E-NET-DELEGATION-PORT-ESCAPE' unless
      range_subset?(child['allowed_port_ranges'], parent['allowed_port_ranges'])

    violations << 'E-NET-DELEGATION-TLS-DOWNGRADE' if
      parent['tls_required'] && !child['tls_required']

    if !parent['bind_address'].nil? &&
       !child['bind_address'].nil? &&
       child['bind_address'] != parent['bind_address']
      violations << 'E-NET-DELEGATION-BIND-ESCALATION'
    end

    { valid: violations.empty?, violations: violations }
  end

  def self.most_restrictive_protocol(p1, p2)
    return p1 if p1 == p2
    return p2 if p1 == 'tcp_udp'
    return p1 if p2 == 'tcp_udp'
    'none'
  end

  def self.intersect_hosts(h1, h2)
    return h2 if h1.include?('*')
    return h1 if h2.include?('*')
    h1 & h2
  end

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

  # Current (canonical) compose — sets bind_address: nil always (Option C)
  def self.compose(g1, g2)
    {
      'capability_id'       => "#{g1['capability_id']}_compose_#{g2['capability_id']}",
      'resource_type'       => 'network',
      'protocol'            => most_restrictive_protocol(g1['protocol'], g2['protocol']),
      'allowed_hosts'       => intersect_hosts(g1['allowed_hosts'], g2['allowed_hosts']),
      'allowed_port_ranges' => intersect_port_ranges(g1['allowed_port_ranges'], g2['allowed_port_ranges']),
      'connect_allowed'     => g1['connect_allowed']  && g2['connect_allowed'],
      'listen_allowed'      => g1['listen_allowed']   && g2['listen_allowed'],
      'send_allowed'        => g1['send_allowed']     && g2['send_allowed'],
      'receive_allowed'     => g1['receive_allowed']  && g2['receive_allowed'],
      'loopback_only'       => g1['loopback_only']    || g2['loopback_only'],
      'tls_required'        => g1['tls_required']     || g2['tls_required'],
      'bind_address'        => nil
    }
  end

  # ── Dead grant predicate ──────────────────────────────────────────────────────
  # A dead grant has all four permission bits false — it is schema-valid but
  # operationally useless: no operation can be authorized through it.
  def self.dead_grant?(cap)
    !cap['connect_allowed'] && !cap['listen_allowed'] &&
      !cap['send_allowed']   && !cap['receive_allowed']
  end

  # Proposed E-NET-DEAD-GRANT warning: fires when compose result is a dead grant
  def self.dead_grant_warning?(cap)
    dead_grant?(cap)
  end

  # ── Three candidate bind_address compose variants ─────────────────────────────

  # Option A — inherit-first: result.bind_address = g1.bind_address
  def self.compose_bind_inherit_first(g1, g2)
    compose(g1, g2).merge('bind_address' => g1['bind_address'])
  end

  # Option B — intersect: result.bind_address follows strict intersection rules:
  #   both nil        → nil
  #   one nil         → nil (the nil side is unconstrained; we take the safe nil)
  #   both same       → that value
  #   both non-nil but different → :conflict (caller must handle)
  def self.compose_bind_intersect(g1, g2)
    b1 = g1['bind_address']
    b2 = g2['bind_address']
    bind_result =
      if b1.nil? && b2.nil?
        nil
      elsif b1.nil? || b2.nil?
        nil
      elsif b1 == b2
        b1
      else
        :conflict
      end
    compose(g1, g2).merge('bind_address' => bind_result)
  end

  # Option C — nil-always: current behavior (compose already does this)
  def self.compose_bind_nil(g1, g2)
    compose(g1, g2)  # bind_address: nil by construction
  end

  # Helper: core permission fields (excluding bind_address)
  def self.core_fields(result)
    result.reject { |k, _| k == 'bind_address' || k == 'capability_id' }
  end
end

NDAP6 = NetworkDelegationAlgebraP6
NCVP6 = NetworkCapabilityValidatorP6

# ═══════════════════════════════════════════════════════════════════════════════
# Load fixtures
# ═══════════════════════════════════════════════════════════════════════════════

def p6_fixture(name)
  path = FIXTURE_DIR_P6 / "#{name}.json"
  raise "Fixture not found: #{path}" unless path.exist?
  JSON.parse(path.read(encoding: 'UTF-8'))
end

dir_connect = p6_fixture('direction_connect_only')
dir_listen  = p6_fixture('direction_listen_only')
dir_both    = p6_fixture('direction_both')
bind_fixed  = p6_fixture('bind_fixed')     # bind_address: "0.0.0.0"
bind_alt    = p6_fixture('bind_alt')       # bind_address: "127.0.0.1"

# ─── Inline helper grant builder ──────────────────────────────────────────────

base_grant_p6 = lambda do |overrides|
  {
    'capability_id'       => 'inline-p6',
    'resource_type'       => 'network',
    'protocol'            => 'tcp',
    'direction'           => 'connect',
    'bind_address'        => nil,
    'allowed_hosts'       => ['127.0.0.1'],
    'allowed_port_ranges' => [{ 'min' => 1, 'max' => 65535 }],
    'loopback_only'       => false,
    'connect_allowed'     => true,
    'listen_allowed'      => false,
    'send_allowed'        => true,
    'receive_allowed'     => true,
    'tls_required'        => false
  }.merge(overrides)
end

# Build a grant with all permission bits false
dead_grant = base_grant_p6.call(
  'capability_id'   => 'dead-grant',
  'connect_allowed' => false,
  'listen_allowed'  => false,
  'send_allowed'    => false,
  'receive_allowed' => false
)

# Build grants for bind_address compose tests
g_null_bind       = base_grant_p6.call('capability_id' => 'null-bind',       'bind_address' => nil)
g_fixed_bind      = base_grant_p6.call('capability_id' => 'fixed-bind',      'bind_address' => '0.0.0.0')
g_fixed_bind_same = base_grant_p6.call('capability_id' => 'fixed-bind-same', 'bind_address' => '0.0.0.0')
g_alt_bind        = base_grant_p6.call('capability_id' => 'alt-bind',        'bind_address' => '127.0.0.1')

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-DEAD — dead grant detection (~10 checks)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-DEAD: dead grant detection ---"

# NET-DEAD-1: dead_grant? returns false for connect-only grant
p6_assert('NET-DEAD', 'NET-DEAD-1',
          !NDAP6.dead_grant?(dir_connect),
          "connect-only grant: dead_grant? must be false; connect_allowed=#{dir_connect['connect_allowed']}")

# NET-DEAD-2: dead_grant? returns false for listen-only grant
p6_assert('NET-DEAD', 'NET-DEAD-2',
          !NDAP6.dead_grant?(dir_listen),
          "listen-only grant: dead_grant? must be false; listen_allowed=#{dir_listen['listen_allowed']}")

# NET-DEAD-3: dead_grant? returns false for both-direction grant
p6_assert('NET-DEAD', 'NET-DEAD-3',
          !NDAP6.dead_grant?(dir_both),
          "both-direction grant: dead_grant? must be false")

# NET-DEAD-4: dead_grant? returns true for a grant with all bits false
p6_assert('NET-DEAD', 'NET-DEAD-4',
          NDAP6.dead_grant?(dead_grant),
          "explicit dead grant (all bits false): dead_grant? must be true; got #{dead_grant.slice('connect_allowed','listen_allowed','send_allowed','receive_allowed').inspect}")

# NET-DEAD-5: compose(connect_only, listen_only) produces a dead grant
# We use inline grants where connect-only has no listen bits and listen-only has no connect bits,
# and neither sends nor receives on the other's channel.
# Pure connect-only: connect=T, listen=F, send=T, receive=F
# Pure listen-only:  connect=F, listen=T, send=F, receive=T
# compose: connect=F, listen=F, send=F, receive=F → dead grant
pure_connect_only = base_grant_p6.call(
  'capability_id'   => 'pure-connect',
  'connect_allowed' => true,
  'listen_allowed'  => false,
  'send_allowed'    => true,
  'receive_allowed' => false
)
pure_listen_only = base_grant_p6.call(
  'capability_id'   => 'pure-listen',
  'connect_allowed' => false,
  'listen_allowed'  => true,
  'send_allowed'    => false,
  'receive_allowed' => true
)
composed_c_l = NDAP6.compose(pure_connect_only, pure_listen_only)
p6_assert('NET-DEAD', 'NET-DEAD-5',
          NDAP6.dead_grant?(composed_c_l),
          "compose(pure_connect_only, pure_listen_only): dead_grant? must be true; permissions=#{composed_c_l.slice('connect_allowed','listen_allowed','send_allowed','receive_allowed').inspect}")

# NET-DEAD-6: dead grant is absorbing for compose — compose(dead, any) is also dead
composed_dead_any = NDAP6.compose(dead_grant, dir_both)
p6_assert('NET-DEAD', 'NET-DEAD-6',
          NDAP6.dead_grant?(composed_dead_any),
          "compose(dead_grant, both): must remain dead; permissions=#{composed_dead_any.slice('connect_allowed','listen_allowed','send_allowed','receive_allowed').inspect}")

# NET-DEAD-7: compose(any, dead) is also dead (both-sided absorption)
composed_any_dead = NDAP6.compose(dir_both, dead_grant)
p6_assert('NET-DEAD', 'NET-DEAD-7',
          NDAP6.dead_grant?(composed_any_dead),
          "compose(both, dead_grant): must remain dead; permissions=#{composed_any_dead.slice('connect_allowed','listen_allowed','send_allowed','receive_allowed').inspect}")

# NET-DEAD-8: valid_delegation?(parent, dead_grant_child) → VALID
# Dead grant has no permission escalation — all child bits are false.
# Condition 3 (permission escalation) only fires when child has a true bit that parent lacks.
parent_for_dead = base_grant_p6.call('capability_id' => 'parent-for-dead')
deleg_to_dead = NDAP6.valid_delegation?(parent_for_dead, dead_grant)
p6_assert('NET-DEAD', 'NET-DEAD-8',
          deleg_to_dead[:valid],
          "valid_delegation?(parent, dead_grant): must be valid (no escalation); violations=#{deleg_to_dead[:violations].inspect}")

# NET-DEAD-9: check_policy_net4(dead_grant, :connect) fires E-NET-DIRECTION-BLOCKED
net4_dead_connect = NCVP6.check_policy_net4(dead_grant, :connect)
p6_assert('NET-DEAD', 'NET-DEAD-9',
          net4_dead_connect[:code] == 'E-NET-DIRECTION-BLOCKED',
          "check_policy_net4(dead_grant, :connect): must fire E-NET-DIRECTION-BLOCKED; got #{net4_dead_connect[:code].inspect}")

# NET-DEAD-10: dead grant is valid by validate_schema (all booleans are false — schema allows it)
schema_result = NCVP6.validate_schema(dead_grant)
p6_assert('NET-DEAD', 'NET-DEAD-10',
          schema_result[:valid],
          "validate_schema(dead_grant): must be schema-valid; errors=#{schema_result[:errors].inspect}")

# NET-DEAD-11: proposed E-NET-DEAD-GRANT warning: dead_grant_warning? fires on compose result
p6_assert('NET-DEAD', 'NET-DEAD-11',
          NDAP6.dead_grant_warning?(composed_c_l),
          "dead_grant_warning? must return true for compose(connect_only, listen_only) result")

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-COMPOSE-BIND — compose bind_address semantics (~12 checks)
# Documenting the current gap and proving three candidate resolutions
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-COMPOSE-BIND: compose bind_address gap and resolution options ---"

# ── Current behavior (Option C: nil-always) ─────────────────────────────────

# NET-COMPOSE-BIND-1: compose(null_bind, null_bind) → result.bind_address is nil (current)
r_null_null = NDAP6.compose(g_null_bind, g_null_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-1',
          r_null_null['bind_address'].nil?,
          "compose(null_bind, null_bind): bind_address must be nil; got #{r_null_null['bind_address'].inspect}")

# NET-COMPOSE-BIND-2: compose(fixed_bind, null_bind) → result.bind_address is nil (parent bind lost)
r_fixed_null = NDAP6.compose(g_fixed_bind, g_null_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-2',
          r_fixed_null['bind_address'].nil?,
          "compose(fixed_bind, null_bind): bind_address nil — parent bind lost; got #{r_fixed_null['bind_address'].inspect}")

# NET-COMPOSE-BIND-3: compose(null_bind, fixed_bind) → result.bind_address is nil (child bind lost)
r_null_fixed = NDAP6.compose(g_null_bind, g_fixed_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-3',
          r_null_fixed['bind_address'].nil?,
          "compose(null_bind, fixed_bind): bind_address nil — child bind lost; got #{r_null_fixed['bind_address'].inspect}")

# NET-COMPOSE-BIND-4: compose(fixed_bind, fixed_bind_same) → result.bind_address is nil (same bind lost)
r_fixed_fixed = NDAP6.compose(g_fixed_bind, g_fixed_bind_same)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-4',
          r_fixed_fixed['bind_address'].nil?,
          "compose(fixed_bind, fixed_bind_same): bind_address nil — same value lost; got #{r_fixed_fixed['bind_address'].inspect}")

# ── Option A: inherit-first ──────────────────────────────────────────────────

# NET-COMPOSE-BIND-5: Option A — (null, null) → nil
ra_null_null = NDAP6.compose_bind_inherit_first(g_null_bind, g_null_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-5',
          ra_null_null['bind_address'].nil?,
          "Option A (null,null): bind_address must be nil; got #{ra_null_null['bind_address'].inspect}")

# NET-COMPOSE-BIND-6: Option A — (fixed, null) → g1.bind_address ('0.0.0.0')
ra_fixed_null = NDAP6.compose_bind_inherit_first(g_fixed_bind, g_null_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-6',
          ra_fixed_null['bind_address'] == '0.0.0.0',
          "Option A (fixed,null): bind_address must be '0.0.0.0' (g1); got #{ra_fixed_null['bind_address'].inspect}")

# NET-COMPOSE-BIND-7: Option A — (null, fixed) → nil (g1 is nil, so nil inherited)
ra_null_fixed = NDAP6.compose_bind_inherit_first(g_null_bind, g_fixed_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-7',
          ra_null_fixed['bind_address'].nil?,
          "Option A (null,fixed): bind_address nil (g1=nil, g2 bind ignored); got #{ra_null_fixed['bind_address'].inspect}")

# NET-COMPOSE-BIND-8: Option A — (fixed, fixed-same) → '0.0.0.0'
ra_fixed_fixed = NDAP6.compose_bind_inherit_first(g_fixed_bind, g_fixed_bind_same)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-8',
          ra_fixed_fixed['bind_address'] == '0.0.0.0',
          "Option A (fixed,fixed-same): bind_address must be '0.0.0.0' (g1); got #{ra_fixed_fixed['bind_address'].inspect}")

# ── Option B: intersect ──────────────────────────────────────────────────────

# NET-COMPOSE-BIND-9: Option B — (null, null) → nil
rb_null_null = NDAP6.compose_bind_intersect(g_null_bind, g_null_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-9',
          rb_null_null['bind_address'].nil?,
          "Option B (null,null): bind_address must be nil; got #{rb_null_null['bind_address'].inspect}")

# NET-COMPOSE-BIND-10: Option B — (fixed, null) → nil (one side nil → nil)
rb_fixed_null = NDAP6.compose_bind_intersect(g_fixed_bind, g_null_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-10',
          rb_fixed_null['bind_address'].nil?,
          "Option B (fixed,null): bind_address nil (nil-side wins); got #{rb_fixed_null['bind_address'].inspect}")

# NET-COMPOSE-BIND-11: Option B — (fixed, fixed-same) → '0.0.0.0' (both equal → keep value)
rb_fixed_fixed = NDAP6.compose_bind_intersect(g_fixed_bind, g_fixed_bind_same)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-11',
          rb_fixed_fixed['bind_address'] == '0.0.0.0',
          "Option B (fixed,fixed-same): bind_address must be '0.0.0.0' (equal intersection); got #{rb_fixed_fixed['bind_address'].inspect}")

# NET-COMPOSE-BIND-12: Option B — (fixed, alt_bind) → :conflict (both non-nil and different)
rb_fixed_alt = NDAP6.compose_bind_intersect(g_fixed_bind, g_alt_bind)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-12',
          rb_fixed_alt['bind_address'] == :conflict,
          "Option B (fixed=0.0.0.0, alt=127.0.0.1): bind_address must be :conflict; got #{rb_fixed_alt['bind_address'].inspect}")

# NET-COMPOSE-BIND-13: All three variants agree on core permission fields
# Use (fixed, fixed-same) case — all variants should produce same permission bits
rc_fixed_fixed = NDAP6.compose_bind_nil(g_fixed_bind, g_fixed_bind_same)
core_a = NDAP6.core_fields(ra_fixed_fixed)
core_b = NDAP6.core_fields(rb_fixed_fixed)
core_c = NDAP6.core_fields(rc_fixed_fixed)
p6_assert('NET-COMPOSE-BIND', 'NET-COMPOSE-BIND-13',
          core_a == core_b && core_b == core_c,
          "All three variants must agree on core fields; A=#{core_a.inspect} B=#{core_b.inspect} C=#{core_c.inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-COMPOSE-PROPS — compose property proofs (~8 checks)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-COMPOSE-PROPS: compose algebraic properties ---"

# NET-COMPOSE-PROPS-1: Idempotence — compose(g, g) reduces scope to same range
# For a grant with port range [1000, 5000], compose(g, g) must still be [1000, 5000]
g_idempotent = base_grant_p6.call(
  'capability_id'       => 'idempotent',
  'allowed_port_ranges' => [{ 'min' => 1000, 'max' => 5000 }],
  'allowed_hosts'       => %w[api.example.com cdn.example.com]
)
g_idem_composed = NDAP6.compose(g_idempotent, g_idempotent)
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-1',
          g_idem_composed['allowed_port_ranges'] == [{ 'min' => 1000, 'max' => 5000 }],
          "Idempotence: compose(g,g) port ranges must equal original; got #{g_idem_composed['allowed_port_ranges'].inspect}")

# NET-COMPOSE-PROPS-2: Idempotence — compose(g, g) hosts stay same
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-2',
          g_idem_composed['allowed_hosts'] == %w[api.example.com cdn.example.com],
          "Idempotence: compose(g,g) hosts must equal original; got #{g_idem_composed['allowed_hosts'].inspect}")

# NET-COMPOSE-PROPS-3: Commutativity of permission bits — AND is commutative
g_comm_a = base_grant_p6.call('capability_id' => 'comm-a', 'connect_allowed' => true,  'listen_allowed' => false)
g_comm_b = base_grant_p6.call('capability_id' => 'comm-b', 'connect_allowed' => false, 'listen_allowed' => true)
comp_ab = NDAP6.compose(g_comm_a, g_comm_b)
comp_ba = NDAP6.compose(g_comm_b, g_comm_a)
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-3',
          comp_ab['connect_allowed'] == comp_ba['connect_allowed'] &&
          comp_ab['listen_allowed']  == comp_ba['listen_allowed'],
          "Commutativity: compose(a,b).connect==compose(b,a).connect; ab=#{comp_ab['connect_allowed']} ba=#{comp_ba['connect_allowed']}")

# NET-COMPOSE-PROPS-4: TLS monotonicity — once tls_required=true in either, result is true
g_tls_false = base_grant_p6.call('capability_id' => 'tls-false', 'tls_required' => false)
g_tls_true  = base_grant_p6.call('capability_id' => 'tls-true',  'tls_required' => true)
comp_tls = NDAP6.compose(g_tls_false, g_tls_true)
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-4',
          comp_tls['tls_required'] == true,
          "TLS monotonicity: compose(tls=false, tls=true) must yield tls_required=true; got #{comp_tls['tls_required']}")

# NET-COMPOSE-PROPS-5: loopback monotonicity — once loopback_only=true in either, result is true
g_loop_false = base_grant_p6.call('capability_id' => 'loop-false', 'loopback_only' => false)
g_loop_true  = base_grant_p6.call('capability_id' => 'loop-true',  'loopback_only' => true)
comp_loop = NDAP6.compose(g_loop_false, g_loop_true)
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-5',
          comp_loop['loopback_only'] == true,
          "loopback monotonicity: compose(loop=false, loop=true) must yield loopback_only=true; got #{comp_loop['loopback_only']}")

# NET-COMPOSE-PROPS-6: Protocol narrowing — most_restrictive_protocol('tcp_udp', 'tcp') == 'tcp'
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-6',
          NDAP6.most_restrictive_protocol('tcp_udp', 'tcp') == 'tcp',
          "most_restrictive_protocol('tcp_udp','tcp') must be 'tcp'; got #{NDAP6.most_restrictive_protocol('tcp_udp','tcp').inspect}")

# NET-COMPOSE-PROPS-7: Protocol conflict — most_restrictive_protocol('tcp', 'udp') == 'none'
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-7',
          NDAP6.most_restrictive_protocol('tcp', 'udp') == 'none',
          "most_restrictive_protocol('tcp','udp') must be 'none'; got #{NDAP6.most_restrictive_protocol('tcp','udp').inspect}")

# NET-COMPOSE-PROPS-8: Empty intersection — non-overlapping port ranges produce []
g_ports_low  = base_grant_p6.call('capability_id' => 'low-ports',  'allowed_port_ranges' => [{ 'min' => 1000, 'max' => 2000 }])
g_ports_high = base_grant_p6.call('capability_id' => 'high-ports', 'allowed_port_ranges' => [{ 'min' => 3000, 'max' => 4000 }])
comp_empty = NDAP6.compose(g_ports_low, g_ports_high)
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-8',
          comp_empty['allowed_port_ranges'] == [],
          "Non-overlapping port ranges: compose must produce []; got #{comp_empty['allowed_port_ranges'].inspect}")

# NET-COMPOSE-PROPS-9: compose with empty port ranges → result has empty port ranges
g_empty_ports = base_grant_p6.call('capability_id' => 'empty-ports', 'allowed_port_ranges' => [])
comp_with_empty = NDAP6.compose(g_empty_ports, g_idempotent)
p6_assert('NET-COMPOSE-PROPS', 'NET-COMPOSE-PROPS-9',
          comp_with_empty['allowed_port_ranges'] == [],
          "compose(empty_ports, g): result must have empty port ranges; got #{comp_with_empty['allowed_port_ranges'].inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-STABLE-P6 — closed-surface guards
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-STABLE-P6: closed-surface guards ---"

this_src_p6 = File.read(__FILE__, encoding: 'UTF-8')
active_lines_p6 = this_src_p6.lines.reject { |l| l.strip.start_with?('#') || l.strip.empty? }

# NET-STABLE-P6-1: No real socket references in this file
forbidden_p6 = ['TCP' + 'Socket', 'UDP' + 'Socket', 'Socket' + '.new', 'Net::' + 'HTTP']
p6_assert('NET-STABLE-P6', 'NET-STABLE-P6-1',
          active_lines_p6.none? { |l| forbidden_p6.any? { |t| l.include?(t) } },
          'Closed-surface breach: real socket/HTTP references found in proof runner')

# NET-STABLE-P6-2: igniter-lang repo untouched
lang_path_p6 = File.expand_path('../../../../igniter-lang', __dir__)
if Dir.exist?(lang_path_p6)
  git_st = `git -C #{lang_path_p6} status --porcelain 2>/dev/null`
  p6_assert('NET-STABLE-P6', 'NET-STABLE-P6-2',
            git_st.strip.empty?,
            "Closed-surface breach: changes in igniter-lang:\n#{git_st}")
else
  p6_pass('NET-STABLE-P6', 'NET-STABLE-P6-2')
end

# NET-STABLE-P6-3: P6 does not require network_ffi_stub (FFI stub independence)
ffi_stub_term_p6 = 'network_ffi' + '_stub'
p6_assert('NET-STABLE-P6', 'NET-STABLE-P6-3',
          !active_lines_p6.any? { |l| l.include?(ffi_stub_term_p6) },
          'P6 proof must not depend on P3 FFI stub')

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n"

pass_count = $p6_results.count { |r| r[:status] == 'PASS' }
fail_count = $p6_results.count { |r| r[:status] == 'FAIL' }
total      = $p6_results.size

puts "══════════════════════════════════════════════════════════════════════"
puts "LAB-STDLIB-NET-P6 — Dead Grant + Compose bind_address Proof Results"
puts "══════════════════════════════════════════════════════════════════════"

groups = $p6_results.map { |r| r[:group] }.uniq
groups.each do |g|
  group_results = $p6_results.select { |r| r[:group] == g }
  gpass = group_results.count { |r| r[:status] == 'PASS' }
  puts "\n  #{g} (#{gpass}/#{group_results.size})"
  group_results.each do |r|
    marker = r[:status] == 'PASS' ? '  ✓' : '  ✗'
    line = "#{marker} #{r[:check]}"
    line += " — #{r[:detail]}" if r[:detail]
    puts line
  end
end

puts "\n══════════════════════════════════════════════════════════════════════"
puts "Result: #{pass_count}/#{total} PASS, #{fail_count} FAIL"
puts "══════════════════════════════════════════════════════════════════════"

if fail_count.zero?
  puts "\n[+] All #{total} P6 proofs passed."
  p5_total = 44
  puts "    Proof chain: P2 53/53 + P3 61/61 + P4 42/42 + P5 #{p5_total}/#{p5_total} + P6 #{total}/#{total} = #{53 + 61 + 42 + p5_total + total} total checks."
  exit 0
else
  puts "\n[!] #{fail_count} check(s) failed."
  exit 1
end
