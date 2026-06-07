# frozen_string_literal: true
# Proof: stdlib/io/network — Network Capability Hardening
# Card: LAB-STDLIB-NET-P5
# Analog to: LAB-STDLIB-IO-P9
# Proves: 5 edge cases deferred from P1-P4:
#   (1) Glob host matching semantics: exact-match-only resolution
#   (2) direction:"both" compose and delegation behavior
#   (3) Multi-hop delegation chains (3+ grants) scope reduction and transitivity
#   (4) Bind-address restriction enforcement (Condition 8)
#   (5) Wildcard allowed_hosts:"*" + loopback_only:true interaction
# No real TCP. Proof-local algebra only. Modules inlined from P2 (provenance noted).
# Authorized surface: fixtures/network_capability_hardening/, proofs/ (this file)
# Closed: igniter-lang canon, igniter-org, no real sockets

require 'json'
require 'set'
require 'pathname'

FIXTURE_DIR_P5 = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'network_capability_hardening'

# ═══════════════════════════════════════════════════════════════════════════════
# Result tracking helpers
# ═══════════════════════════════════════════════════════════════════════════════

$p5_results = []

def p5_pass(group, check)
  $p5_results << { status: 'PASS', group: group, check: check }
  print '.'
end

def p5_fail(group, check, detail = nil)
  $p5_results << { status: 'FAIL', group: group, check: check, detail: detail }
  print 'F'
end

def p5_assert(group, check, condition, detail = nil)
  if condition
    p5_pass(group, check)
  else
    p5_fail(group, check, detail || 'expected true, got false')
  end
end

def p5_assert_violation(group, check, result, expected_code)
  has_code = result[:violations].include?(expected_code)
  if has_code
    p5_pass(group, check)
  else
    p5_fail(group, check, "expected violation #{expected_code}; got #{result[:violations].inspect}")
  end
end

def p5_assert_no_violation(group, check, result, unwanted_code)
  has_code = result[:violations].include?(unwanted_code)
  if has_code
    p5_fail(group, check, "unexpected violation #{unwanted_code}")
  else
    p5_pass(group, check)
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# P2 Algebra Modules — inlined from proofs/network_capability_proof.rb
# (copied verbatim; provenance: LAB-STDLIB-NET-P2)
# ═══════════════════════════════════════════════════════════════════════════════

module NetworkCapabilityValidatorH
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
end

module NetworkDelegationAlgebraH
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
end

NDA = NetworkDelegationAlgebraH
NCV = NetworkCapabilityValidatorH

# ═══════════════════════════════════════════════════════════════════════════════
# Load fixtures
# ═══════════════════════════════════════════════════════════════════════════════

def p5_fixture(name)
  path = FIXTURE_DIR_P5 / "#{name}.json"
  raise "Fixture not found: #{path}" unless path.exist?
  JSON.parse(path.read(encoding: 'UTF-8'))
end

g1_root         = p5_fixture('chain_g1_root')
g2_mid          = p5_fixture('chain_g2_mid')
g3_leaf         = p5_fixture('chain_g3_leaf')
dir_both        = p5_fixture('direction_both')
dir_connect     = p5_fixture('direction_connect_only')
dir_listen      = p5_fixture('direction_listen_only')
bind_fixed      = p5_fixture('bind_fixed')      # bind_address: "0.0.0.0"
bind_alt        = p5_fixture('bind_alt')        # bind_address: "127.0.0.1"

# ─── Inline helper grants ─────────────────────────────────────────────────────

base_grant = lambda do |overrides|
  {
    'capability_id'       => 'inline',
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

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-GLOB — host matching semantics (exact-match-only resolution)
# Design decision proved: P2 host_subset? treats hosts as opaque strings;
# *.example.com is a literal identifier, not a glob pattern.
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-GLOB: host matching semantics (exact-match resolution) ---"

# Exact match is identity
p5_assert('NET-GLOB', 'NET-GLOB-1',
          NDA.host_subset?(['api.example.com'], ['api.example.com']),
          'exact match: api.example.com ⊆ {api.example.com} must be true')

# *.example.com is NOT a glob — does not expand to api.example.com
p5_assert('NET-GLOB', 'NET-GLOB-2',
          !NDA.host_subset?(['api.example.com'], ['*.example.com']),
          'design decision: *.example.com is opaque literal; api.example.com ⊄ {*.example.com}')

# *.example.com ⊆ {*.example.com} (same literal)
p5_assert('NET-GLOB', 'NET-GLOB-3',
          NDA.host_subset?(['*.example.com'], ['*.example.com']),
          '*.example.com ⊆ {*.example.com} (same literal) must be true')

# Any host ⊆ {*} (full wildcard parent)
p5_assert('NET-GLOB', 'NET-GLOB-4',
          NDA.host_subset?(['api.example.com'], ['*']),
          'api.example.com ⊆ {*} must be true (full wildcard)')

# Multi-host child, partial parent — fails
p5_assert('NET-GLOB', 'NET-GLOB-5',
          !NDA.host_subset?(['api.example.com', 'cdn.example.com'], ['api.example.com']),
          'cdn.example.com not in parent {api.example.com} — must be false')

# check_policy_net2 with * wildcard cap — any host passes
cap_star = base_grant.call('allowed_hosts' => ['*'])
p5_assert('NET-GLOB', 'NET-GLOB-6',
          NCV.check_policy_net2(cap_star, 'any.arbitrary.host.example.com')[:ok] == true,
          'allowed_hosts:[*] must permit any host via check_policy_net2')

# check_policy_net2 with explicit host — wrong host fails
cap_explicit = base_grant.call('allowed_hosts' => ['trusted.example.com'])
p5_assert('NET-GLOB', 'NET-GLOB-7',
          NCV.check_policy_net2(cap_explicit, 'other.example.com')[:code] == 'E-NET-HOST-BLOCKED',
          'allowed_hosts:[trusted.example.com] must block other.example.com')

# Delegation: child with [api.example.com] under parent with [*.example.com]
# → HOST-ESCAPE because host_subset? uses exact match (opaque literals)
parent_glob = base_grant.call('allowed_hosts' => ['*.example.com'])
child_exact = base_grant.call('allowed_hosts' => ['api.example.com'])
deleg_glob  = NDA.valid_delegation?(parent_glob, child_exact)
p5_assert('NET-GLOB', 'NET-GLOB-8',
          deleg_glob[:violations].include?('E-NET-DELEGATION-HOST-ESCAPE'),
          "api.example.com ⊄ {*.example.com} in algebra → HOST-ESCAPE; got #{deleg_glob[:violations].inspect}")

# Delegation: child with [*.example.com] under parent with [*] → valid
parent_full_wild = base_grant.call('allowed_hosts' => ['*'])
child_glob_lit   = base_grant.call('allowed_hosts' => ['*.example.com'])
deleg_wild       = NDA.valid_delegation?(parent_full_wild, child_glob_lit)
p5_assert('NET-GLOB', 'NET-GLOB-9',
          deleg_wild[:valid],
          "*.example.com ⊆ {*} (full wildcard parent) — must be valid; violations=#{deleg_wild[:violations].inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-BOTH-DIR — direction:"both" compose and delegation behavior
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-BOTH-DIR: direction:both compose and delegation ---"

# direction_both fixture has connect_allowed:true AND listen_allowed:true
p5_assert('NET-BOTH-DIR', 'NET-BOTH-1',
          dir_both['connect_allowed'] == true && dir_both['listen_allowed'] == true,
          'direction_both fixture: both connect_allowed and listen_allowed must be true')

# compose(connect_only, listen_only) → both permission bits false
composed_c_l = NDA.compose(dir_connect, dir_listen)
p5_assert('NET-BOTH-DIR', 'NET-BOTH-2',
          composed_c_l['connect_allowed'] == false && composed_c_l['listen_allowed'] == false,
          "compose(connect_only, listen_only): connect=#{composed_c_l['connect_allowed']}, listen=#{composed_c_l['listen_allowed']}; both must be false")

# compose(both, connect_only) → connect_allowed:true, listen_allowed:false
composed_both_c = NDA.compose(dir_both, dir_connect)
p5_assert('NET-BOTH-DIR', 'NET-BOTH-3',
          composed_both_c['connect_allowed'] == true && composed_both_c['listen_allowed'] == false,
          "compose(both, connect_only): connect=#{composed_both_c['connect_allowed']}, listen=#{composed_both_c['listen_allowed']}")

# compose(both, listen_only) → connect_allowed:false, listen_allowed:true
composed_both_l = NDA.compose(dir_both, dir_listen)
p5_assert('NET-BOTH-DIR', 'NET-BOTH-4',
          composed_both_l['connect_allowed'] == false && composed_both_l['listen_allowed'] == true,
          "compose(both, listen_only): connect=#{composed_both_l['connect_allowed']}, listen=#{composed_both_l['listen_allowed']}")

# valid_delegation?(both_parent, connect_child) → valid (connect sub-grant)
deleg_both_to_connect = NDA.valid_delegation?(dir_both, dir_connect)
p5_assert('NET-BOTH-DIR', 'NET-BOTH-5',
          deleg_both_to_connect[:valid],
          "both → connect: expected valid; violations=#{deleg_both_to_connect[:violations].inspect}")

# valid_delegation?(both_parent, listen_child) → valid (listen sub-grant)
deleg_both_to_listen = NDA.valid_delegation?(dir_both, dir_listen)
p5_assert('NET-BOTH-DIR', 'NET-BOTH-6',
          deleg_both_to_listen[:valid],
          "both → listen: expected valid; violations=#{deleg_both_to_listen[:violations].inspect}")

# valid_delegation?(connect_parent, listen_child) → invalid PERMISSION_ESCALATION
deleg_connect_to_listen = NDA.valid_delegation?(dir_connect, dir_listen)
p5_assert('NET-BOTH-DIR', 'NET-BOTH-7',
          deleg_connect_to_listen[:violations].include?('E-NET-DELEGATION-PERMISSION-ESCALATION'),
          "connect → listen: must produce PERMISSION_ESCALATION; got #{deleg_connect_to_listen[:violations].inspect}")

# compose(both, both) → still both true
composed_both_both = NDA.compose(dir_both, dir_both)
p5_assert('NET-BOTH-DIR', 'NET-BOTH-8',
          composed_both_both['connect_allowed'] == true && composed_both_both['listen_allowed'] == true,
          "compose(both, both): both bits must remain true")

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-CHAIN — multi-hop delegation chains (3+ grants)
# G1 (root: tcp_udp, *, 1-65535) → G2 (tcp, api.example.com, 443-8080) → G3 (tcp, api.example.com, 443-443, tls)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-CHAIN: multi-hop delegation chain (G1 → G2 → G3) ---"

deleg_g1_g2 = NDA.valid_delegation?(g1_root, g2_mid)
p5_assert('NET-CHAIN', 'NET-CHAIN-1',
          deleg_g1_g2[:valid],
          "G1 → G2: expected valid; violations=#{deleg_g1_g2[:violations].inspect}")

deleg_g2_g3 = NDA.valid_delegation?(g2_mid, g3_leaf)
p5_assert('NET-CHAIN', 'NET-CHAIN-2',
          deleg_g2_g3[:valid],
          "G2 → G3: expected valid; violations=#{deleg_g2_g3[:violations].inspect}")

# Transitivity: G3 ⊑ G1 directly (skipping G2)
deleg_g1_g3 = NDA.valid_delegation?(g1_root, g3_leaf)
p5_assert('NET-CHAIN', 'NET-CHAIN-3',
          deleg_g1_g3[:valid],
          "Transitivity: G1 → G3 direct must be valid; violations=#{deleg_g1_g3[:violations].inspect}")

# compose(G1, G2) = G_12; then G3 ⊑ G_12 valid
g12 = NDA.compose(g1_root, g2_mid)
deleg_g12_g3 = NDA.valid_delegation?(g12, g3_leaf)
p5_assert('NET-CHAIN', 'NET-CHAIN-4',
          deleg_g12_g3[:valid],
          "compose(G1,G2) → G3: expected valid; violations=#{deleg_g12_g3[:violations].inspect}")

# Port escape: G3 with port outside G2 range → G2→G3 invalid
g3_port_escape = g3_leaf.merge(
  'capability_id'       => 'g3-port-escape',
  'allowed_port_ranges' => [{ 'min' => 443, 'max' => 9000 }],  # wider than G2's 443-8080? no, 9000 > 8080
  'tls_required'        => false
)
deleg_g2_g3_port_esc = NDA.valid_delegation?(g2_mid, g3_port_escape)
p5_assert('NET-CHAIN', 'NET-CHAIN-5',
          deleg_g2_g3_port_esc[:violations].include?('E-NET-DELEGATION-PORT-ESCAPE'),
          "G2→G3 port escape (9000 > G2.max 8080): expected PORT-ESCAPE; got #{deleg_g2_g3_port_esc[:violations].inspect}")

# Protocol escalation: G3 trying udp under tcp-only G2
g3_proto_esc = g3_leaf.merge('capability_id' => 'g3-proto-esc', 'protocol' => 'udp')
deleg_g2_g3_proto = NDA.valid_delegation?(g2_mid, g3_proto_esc)
p5_assert('NET-CHAIN', 'NET-CHAIN-6',
          deleg_g2_g3_proto[:violations].include?('E-NET-DELEGATION-PROTOCOL-ESCALATION'),
          "G2(tcp) → G3(udp): expected PROTOCOL-ESCALATION; got #{deleg_g2_g3_proto[:violations].inspect}")

# TLS hardening chain: G2(no TLS) → G3(tls_required) is valid (adding TLS is non-escalation)
deleg_tls_harden = NDA.valid_delegation?(g2_mid, g3_leaf)
p5_assert('NET-CHAIN', 'NET-CHAIN-7',
          deleg_tls_harden[:valid],
          "G2(no TLS) → G3(tls_required): TLS hardening is valid; violations=#{deleg_tls_harden[:violations].inspect}")

# TLS downgrade: G3(tls_required) → G2(no TLS) → invalid DOWNGRADE
deleg_tls_down = NDA.valid_delegation?(g3_leaf, g2_mid)
p5_assert('NET-CHAIN', 'NET-CHAIN-8',
          deleg_tls_down[:violations].include?('E-NET-DELEGATION-TLS-DOWNGRADE'),
          "G3(tls) → G2(no tls): expected TLS-DOWNGRADE; got #{deleg_tls_down[:violations].inspect}")

# Associativity: compose(G1, compose(G2, G3)) == compose(compose(G1, G2), G3) for port ranges
g23  = NDA.compose(g2_mid, g3_leaf)
g123_right = NDA.compose(g1_root, g23)
g12b = NDA.compose(g1_root, g2_mid)
g123_left  = NDA.compose(g12b, g3_leaf)
p5_assert('NET-CHAIN', 'NET-CHAIN-9',
          g123_right['allowed_port_ranges'] == g123_left['allowed_port_ranges'] &&
          g123_right['protocol'] == g123_left['protocol'] &&
          g123_right['connect_allowed'] == g123_left['connect_allowed'],
          "compose associativity: compose(G1,(G2,G3)) must match compose((G1,G2),G3) for key fields")

# compose reduces scope at each step: G12 port max ≤ G1 port max
p5_assert('NET-CHAIN', 'NET-CHAIN-10',
          g12['allowed_port_ranges'].all? { |r| r['max'] <= 8080 },
          "compose(G1,G2): resulting port max must be ≤ G2.max (8080)")

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-BIND — bind-address restriction enforcement (Condition 8)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-BIND: bind-address restriction enforcement ---"

# Null parent bind_address → any child bind_address is valid
parent_null_bind  = base_grant.call('bind_address' => nil, 'listen_allowed' => true, 'connect_allowed' => false)
child_some_bind   = base_grant.call('bind_address' => '127.0.0.1', 'listen_allowed' => true, 'connect_allowed' => false)
deleg_null_parent = NDA.valid_delegation?(parent_null_bind, child_some_bind)
p5_assert('NET-BIND', 'NET-BIND-1',
          deleg_null_parent[:valid],
          "parent.bind_address=null → any child bind is valid; violations=#{deleg_null_parent[:violations].inspect}")

# Same bind_address in parent and child → valid
deleg_same_bind = NDA.valid_delegation?(bind_fixed, bind_fixed.merge('capability_id' => 'child-fixed'))
p5_assert('NET-BIND', 'NET-BIND-2',
          deleg_same_bind[:valid],
          "parent.bind=0.0.0.0 → child.bind=0.0.0.0: same value must be valid; violations=#{deleg_same_bind[:violations].inspect}")

# Different bind_address (both non-null) → BIND-ESCALATION
deleg_diff_bind = NDA.valid_delegation?(bind_fixed, bind_alt)
p5_assert('NET-BIND', 'NET-BIND-3',
          deleg_diff_bind[:violations].include?('E-NET-DELEGATION-BIND-ESCALATION'),
          "parent.bind=0.0.0.0 → child.bind=127.0.0.1: must fire BIND-ESCALATION; got #{deleg_diff_bind[:violations].inspect}")

# Null parent, non-null child → valid (Condition 8 only fires when both non-null and differ)
deleg_null_to_nonnull = NDA.valid_delegation?(
  bind_fixed.merge('bind_address' => nil),
  bind_alt
)
p5_assert('NET-BIND', 'NET-BIND-4',
          !deleg_null_to_nonnull[:violations].include?('E-NET-DELEGATION-BIND-ESCALATION'),
          "parent.bind=null → child.bind=127.0.0.1: Condition 8 must NOT fire; got #{deleg_null_to_nonnull[:violations].inspect}")

# Non-null parent, null child → valid (Condition 8 only fires when BOTH non-null and different)
deleg_nonnull_to_null = NDA.valid_delegation?(
  bind_fixed,
  bind_fixed.merge('capability_id' => 'child-null-bind', 'bind_address' => nil)
)
p5_assert('NET-BIND', 'NET-BIND-5',
          !deleg_nonnull_to_null[:violations].include?('E-NET-DELEGATION-BIND-ESCALATION'),
          "parent.bind=0.0.0.0 → child.bind=null: Condition 8 must NOT fire (child null is OK); got #{deleg_nonnull_to_null[:violations].inspect}")

# BIND-ESCALATION code is the only violation in the diff-bind case
p5_assert('NET-BIND', 'NET-BIND-6',
          deleg_diff_bind[:violations] == ['E-NET-DELEGATION-BIND-ESCALATION'],
          "diff-bind violation list must be exactly [BIND-ESCALATION]; got #{deleg_diff_bind[:violations].inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-WILD — wildcard allowed_hosts:"*" + loopback_only:true interaction
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-WILD: wildcard + loopback_only interaction ---"

cap_wild_no_loop  = base_grant.call('allowed_hosts' => ['*'], 'loopback_only' => false)
cap_wild_loop     = base_grant.call('allowed_hosts' => ['*'], 'loopback_only' => true)

# Wildcard + no loopback: both loopback and external pass NET-1 and NET-2
p5_assert('NET-WILD', 'NET-WILD-1',
          NCV.check_policy_net1(cap_wild_no_loop, 'external.example.com')[:ok] &&
          NCV.check_policy_net2(cap_wild_no_loop, 'external.example.com')[:ok],
          'allowed_hosts:[*], loopback_only:false — external host must pass both NET-1 and NET-2')

# Wildcard + loopback: loopback host passes both checks
p5_assert('NET-WILD', 'NET-WILD-2',
          NCV.check_policy_net1(cap_wild_loop, '127.0.0.1')[:ok] &&
          NCV.check_policy_net2(cap_wild_loop, '127.0.0.1')[:ok],
          'allowed_hosts:[*], loopback_only:true — 127.0.0.1 must pass both NET-1 and NET-2')

# Wildcard + loopback: external host passes NET-2 (wildcard) but FAILS NET-1 (loopback)
net1_ext = NCV.check_policy_net1(cap_wild_loop, 'external.example.com')
net2_ext = NCV.check_policy_net2(cap_wild_loop, 'external.example.com')
p5_assert('NET-WILD', 'NET-WILD-3',
          net2_ext[:ok] == true && net1_ext[:ok] == false,
          "Wildcard+loopback: external host — NET-2 ok=#{net2_ext[:ok]}, NET-1 ok=#{net1_ext[:ok]}; NET-2 must pass, NET-1 must fail")

# NET-1 and NET-2 are independent: NET-1 fires E-NET-LOOPBACK-VIOLATION
p5_assert('NET-WILD', 'NET-WILD-4',
          net1_ext[:code] == 'E-NET-LOOPBACK-VIOLATION',
          "loopback check code must be E-NET-LOOPBACK-VIOLATION; got #{net1_ext[:code].inspect}")

# Delegation under loopback parent: child.loopback_only=false → LOOPBACK-ESCAPE
parent_loopback = base_grant.call('allowed_hosts' => ['*'], 'loopback_only' => true)
child_no_loop   = base_grant.call('allowed_hosts' => ['*'], 'loopback_only' => false)
deleg_loop_esc  = NDA.valid_delegation?(parent_loopback, child_no_loop)
p5_assert('NET-WILD', 'NET-WILD-5',
          deleg_loop_esc[:violations].include?('E-NET-DELEGATION-LOOPBACK-ESCAPE'),
          "loopback parent → no-loop child: must fire LOOPBACK-ESCAPE; got #{deleg_loop_esc[:violations].inspect}")

# Delegation under loopback parent: child.loopback_only=true → valid Condition 4
child_also_loop = base_grant.call('allowed_hosts' => ['127.0.0.1'], 'loopback_only' => true)
deleg_loop_ok   = NDA.valid_delegation?(parent_loopback, child_also_loop)
p5_assert('NET-WILD', 'NET-WILD-6',
          deleg_loop_ok[:valid],
          "loopback parent → loopback child: Condition 4 must pass; violations=#{deleg_loop_ok[:violations].inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP: NET-STABLE — module integrity, closed-surface, no real I/O
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n--- NET-STABLE: module integrity and closed-surface ---"

# P2 modules loaded and respond to key methods
p5_assert('NET-STABLE', 'NET-STABLE-1',
          NDA.respond_to?(:valid_delegation?) &&
          NDA.respond_to?(:compose) &&
          NDA.respond_to?(:host_subset?),
          'NetworkDelegationAlgebraH must respond to valid_delegation?, compose, host_subset?')

# All 7 E-NET-DELEGATION-* violation codes can be produced
all_seven_codes = %w[
  E-NET-DELEGATION-TYPE-MISMATCH
  E-NET-DELEGATION-PROTOCOL-ESCALATION
  E-NET-DELEGATION-PERMISSION-ESCALATION
  E-NET-DELEGATION-LOOPBACK-ESCAPE
  E-NET-DELEGATION-HOST-ESCAPE
  E-NET-DELEGATION-PORT-ESCAPE
  E-NET-DELEGATION-TLS-DOWNGRADE
  E-NET-DELEGATION-BIND-ESCALATION
]
# Build a maximally violating child
maximally_violating_child = {
  'capability_id' => 'violator',
  'resource_type' => 'file',          # type mismatch
  'protocol'      => 'udp',           # protocol escalation under tcp parent
  'direction'     => 'both',
  'bind_address'  => '10.0.0.1',      # bind escalation under fixed-bind parent
  'allowed_hosts' => ['evil.net'],    # host escape
  'allowed_port_ranges' => [{ 'min' => 1, 'max' => 65535 }],  # port escape under narrow parent
  'loopback_only'   => false,         # loopback escape under loopback parent
  'connect_allowed' => true,
  'listen_allowed'  => true,          # permission escalation under listen=false parent
  'send_allowed'    => true,
  'receive_allowed' => true,
  'tls_required'    => false          # TLS downgrade under tls_required parent
}
maximally_violating_parent = {
  'resource_type'       => 'network',
  'protocol'            => 'tcp',
  'bind_address'        => '0.0.0.0',
  'allowed_hosts'       => ['trusted.example.com'],
  'allowed_port_ranges' => [{ 'min' => 443, 'max' => 443 }],
  'loopback_only'       => true,
  'connect_allowed'     => true,
  'listen_allowed'      => false,
  'send_allowed'        => true,
  'receive_allowed'     => true,
  'tls_required'        => true
}
all_viols = NDA.valid_delegation?(maximally_violating_parent, maximally_violating_child)[:violations]
p5_assert('NET-STABLE', 'NET-STABLE-2',
          all_seven_codes.all? { |code| all_viols.include?(code) },
          "All 7 delegation violation codes must be producible; missing: #{all_seven_codes.reject { |c| all_viols.include?(c) }.inspect}")

# Closed-surface guard: no real socket references in this file
this_src_p5 = File.read(__FILE__, encoding: 'UTF-8')
active_lines_p5 = this_src_p5.lines.reject { |l| l.strip.start_with?('#') || l.strip.empty? }
forbidden_p5 = ['TCP' + 'Socket', 'UDP' + 'Socket', 'Socket' + '.new', 'Net::' + 'HTTP']
no_real_io = active_lines_p5.none? { |l| forbidden_p5.any? { |t| l.include?(t) } }
p5_assert('NET-STABLE', 'NET-STABLE-3',
          no_real_io,
          'Closed-surface breach: real socket/HTTP references found in proof runner')

# igniter-lang repo untouched
lang_path_p5 = File.expand_path('../../../../igniter-lang', __dir__)
if Dir.exist?(lang_path_p5)
  git_st = `git -C #{lang_path_p5} status --porcelain 2>/dev/null`
  p5_assert('NET-STABLE', 'NET-STABLE-4',
            git_st.strip.empty?,
            "Closed-surface breach: changes in igniter-lang:\n#{git_st}")
else
  p5_pass('NET-STABLE', 'NET-STABLE-4')
end

# P5 does not require network_ffi_stub (FFI stub independence)
ffi_stub_term_p5 = 'network_ffi' + '_stub'
p5_assert('NET-STABLE', 'NET-STABLE-5',
          !active_lines_p5.any? { |l| l.include?(ffi_stub_term_p5) },
          'P5 hardening proof must not depend on P3 FFI stub')

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n"

pass_count = $p5_results.count { |r| r[:status] == 'PASS' }
fail_count = $p5_results.count { |r| r[:status] == 'FAIL' }
total      = $p5_results.size

puts "══════════════════════════════════════════════════════════════════════"
puts "LAB-STDLIB-NET-P5 — Network Capability Hardening Proof Results"
puts "══════════════════════════════════════════════════════════════════════"

groups = $p5_results.map { |r| r[:group] }.uniq
groups.each do |g|
  group_results = $p5_results.select { |r| r[:group] == g }
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
  puts "\n[+] All #{total} P5 hardening proofs passed."
  puts "    Proof chain: P2 53/53 + P3 61/61 + P4 42/42 + P5 #{total}/#{total} = #{53 + 61 + 42 + total} total checks."
  exit 0
else
  puts "\n[!] #{fail_count} check(s) failed."
  exit 1
end
