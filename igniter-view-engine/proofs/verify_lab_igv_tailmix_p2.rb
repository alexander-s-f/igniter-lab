#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igv_tailmix_p2.rb
# LAB-IGV-TAILMIX-P2: Proof-local Tailmix-on-Igniter definition, render, and diff-oracle
#
# Validates the P1 architecture with one tiny component (FileTreeRow):
#   - content-addressed definition JSON (per type, D6)
#   - render → { html, def_refs } with per-instance binding only (D7)
#   - N instances → 1 definition / dedup proof (D6)
#   - reference applier oracle over closed instruction vocabulary (D8)
#   - diff-test: interpreter must match oracle for all triples (D10)
#   - dispatch → host event, not local mutation (D5)
#   - unknown op → error, fail-closed (D8)
#
# No compiler / parser / VM / Tauri change. No contract execution in the view runtime.
# No client-side capability authority claim. LAB-ONLY.
#
# Sections:
#   TAILMIX-DEF        — definition structure and content-addressing (8 checks)
#   TAILMIX-RENDER     — render output: { html, def_refs }, per-instance binding (8 checks)
#   TAILMIX-DEDUP      — N instances → 1 definition; per-instance state isolation (5 checks)
#   TAILMIX-ORACLE     — reference applier oracle over all state transitions (10 checks)
#   TAILMIX-INTERP     — interpreter matches oracle for every triple (8 checks)
#   TAILMIX-DISPATCH   — dispatch emits host event; does not mutate state (6 checks)
#   TAILMIX-FAILCLOSED — unknown op returns error, not silent no-op (6 checks)
#   TAILMIX-CLOSED     — definition carries no VM/SIR/capability surface (5 checks)
#
# Run: ruby igniter-view-engine/proofs/verify_lab_igv_tailmix_p2.rb

require 'json'
require 'digest'
require 'open3'
require 'pathname'

ROOT     = Pathname.new(__dir__).parent
FIX_DIR  = ROOT / 'fixtures' / 'igv_tailmix'
DEF_FILE = FIX_DIR / 'file_tree_row_definition.json'
INTERP   = FIX_DIR / 'igv_tailmix_interpreter.js'

DEFINITION = JSON.parse(File.read(DEF_FILE, encoding: 'UTF-8'))

$pass_count = 0
$fail_count = 0

def check(label)
  result = yield
  if result
    puts "  PASS: #{label}"; $pass_count += 1
  else
    puts "  FAIL: #{label}"; $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end


# ── Reference Applier Oracle ──────────────────────────────────────────────────
#
# Pure function: (definition, state, event?) → { state:, attributes:, host_event?: }
#                                             | { error: }
#
# This is the canonical oracle for the P2 diff-test. It defines what "correct" means
# for the closed `:local` instruction vocabulary. The interpreter is tested against it.

CLOSED_OPS = %w[toggle set add_class remove_class toggle_class
                set_attr set_aria show hide match dispatch].freeze

def oracle_apply(defn, state, event = nil)
  current = state.dup
  host_event = nil

  if event
    el_def = defn['elements'][event[:element]]
    if el_def && el_def['on'] && el_def['on'][event[:name]]
      el_def['on'][event[:name]].each do |inst|
        op = inst['op']
        return { error: "unknown_op:#{op}" } unless CLOSED_OPS.include?(op)

        case op
        when 'toggle'
          key = inst['target'].sub('state.', '')
          current[key] = !current[key]
        when 'set'
          key = inst['target'].sub('state.', '')
          current[key] = inst['value']
        when 'dispatch'
          host_event = { 'event' => inst['event'],
                         'payload' => inst.fetch('payload', nil) }
        end
        # add_class / remove_class / etc. are rule-level ops; accepted but no-op here
      end
    end
  end

  attributes = {}
  defn['elements'].each do |el_name, el_def|
    next unless el_def['rules']
    el_def['rules'].each do |rule|
      cond_key = rule['when'].sub('state.', '')
      effect   = current[cond_key] ? rule : rule['else']
      next unless effect

      if effect['classes']
        attributes["#{el_name}.classes"] =
          (attributes["#{el_name}.classes"] || []) + effect['classes']
      end
      (effect['aria'] || {}).each do |k, v|
        attributes["#{el_name}.aria-#{k}"] = v
      end
    end
  end

  result = { state: current, attributes: attributes }
  result[:host_event] = host_event if host_event
  result
end


# ── Interpreter (JS, proof-local) ──────────────────────────────────────────────

def interp_apply(defn, state, event = nil)
  input = { definition: defn, state: state }
  input[:event] = { element: event[:element], name: event[:name] } if event
  stdout, _err, _st = Open3.capture3('node', INTERP.to_s, JSON.generate(input))
  JSON.parse(stdout.strip)
end


# ── Render helper ──────────────────────────────────────────────────────────────
#
# Simulates the Igniter view-engine render: per-instance binding only.
# Returns { html:, def_refs: }.

def render(component_name, props, defn)
  def_id   = defn['def_id']
  inst_id  = props[:instance_id]
  init_st  = defn['states'].transform_values { |v| v['default'] }

  html = %(<div data-igv="#{component_name}" data-igv-def="#{def_id}" ) +
         %(data-igv-instance="#{inst_id}" ) +
         %(data-igv-state='#{JSON.generate(init_st)}'>…</div>)

  { html: html, def_refs: [def_id] }
end


# ── Hash verification ──────────────────────────────────────────────────────────

def canonical_hash(defn)
  content = defn.reject { |k, _| k == 'def_id' }
  'sha256:' + Digest::SHA256.hexdigest(JSON.generate(content))
end


# ── Unknown-op definition (for fail-closed tests) ─────────────────────────────

BAD_OP_DEF = Marshal.load(Marshal.dump(DEFINITION)).tap do |d|
  d['elements']['toggle_btn']['on']['click'] = [{ 'op' => 'exec_arbitrary', 'target' => 'state.expanded' }]
end.freeze


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-DEF  definition structure and content-addressing
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-DEF: definition structure ─"

check('DEF-01: definition file parses as valid JSON') do
  DEFINITION.is_a?(Hash)
end

check('DEF-02: def_id field present and starts with sha256:') do
  DEFINITION['def_id'].is_a?(String) && DEFINITION['def_id'].start_with?('sha256:')
end

check('DEF-03: def_id hash portion is 64 hex characters') do
  hex = DEFINITION['def_id'].sub('sha256:', '')
  hex.length == 64 && hex.match?(/\A[0-9a-f]+\z/)
end

check('DEF-04: component field is FileTreeRow') do
  DEFINITION['component'] == 'FileTreeRow'
end

check('DEF-05: states hash includes expanded key with default false') do
  DEFINITION.dig('states', 'expanded', 'default') == false
end

check('DEF-06: elements has row, toggle_btn, action_btn') do
  %w[row toggle_btn action_btn].all? { |k| DEFINITION['elements'].key?(k) }
end

check('DEF-07: row element has rules array') do
  DEFINITION.dig('elements', 'row', 'rules').is_a?(Array)
end

check('DEF-08: def_id is the correct SHA256 of canonical content') do
  canonical_hash(DEFINITION) == DEFINITION['def_id']
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-RENDER  render output: { html, def_refs }
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-RENDER: render output shape ─"

R1 = render('FileTreeRow', { instance_id: 'inst-abc' }, DEFINITION)

check('RENDER-01: render returns Hash with html and def_refs keys') do
  R1.is_a?(Hash) && R1.key?(:html) && R1.key?(:def_refs)
end

check('RENDER-02: def_refs is a non-empty array') do
  R1[:def_refs].is_a?(Array) && !R1[:def_refs].empty?
end

check('RENDER-03: def_refs[0] equals definition def_id') do
  R1[:def_refs][0] == DEFINITION['def_id']
end

check('RENDER-04: html contains data-igv-def attribute') do
  R1[:html].include?('data-igv-def=')
end

check('RENDER-05: html embeds the def_id hash value') do
  R1[:html].include?(DEFINITION['def_id'])
end

check('RENDER-06: html contains data-igv-state with initial state JSON') do
  R1[:html].include?('data-igv-state=') && R1[:html].include?('"expanded":false')
end

check('RENDER-07: html does NOT inline the full definition (no states/elements structure)') do
  !R1[:html].include?('"elements"') && !R1[:html].include?('"toggle_btn"')
end

check('RENDER-08: html does NOT inline rules or op instructions') do
  !R1[:html].include?('"rules"') && !R1[:html].include?('"op"')
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-DEDUP  N instances → 1 definition; per-instance state isolation
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-DEDUP: N→1 definition dedup ─"

INSTANCES = [
  render('FileTreeRow', { instance_id: 'inst-001' }, DEFINITION),
  render('FileTreeRow', { instance_id: 'inst-002' }, DEFINITION),
  render('FileTreeRow', { instance_id: 'inst-003' }, DEFINITION)
].freeze

check('DEDUP-01: 3 instances all return def_refs pointing to same hash') do
  def_ids = INSTANCES.map { |r| r[:def_refs][0] }.uniq
  def_ids.length == 1 && def_ids[0] == DEFINITION['def_id']
end

check('DEDUP-02: unique def_refs across all N renders == 1 (the core dedup claim)') do
  all_refs = INSTANCES.flat_map { |r| r[:def_refs] }.uniq
  all_refs.length == 1
end

check('DEDUP-03: each instance html carries its own instance id') do
  ids = INSTANCES.map { |r| r[:html].match(/data-igv-instance="([^"]+)"/)[1] rescue nil }
  ids.uniq.length == 3
end

check('DEDUP-04: each instance html has isolated initial state (not cross-contaminated)') do
  INSTANCES.all? { |r| r[:html].include?('"expanded":false') }
end

check('DEDUP-05: one definition covers all 3 instances (bundle = 1 definition)') do
  unique_defs = INSTANCES.map { |r| r[:def_refs][0] }.uniq
  unique_defs.length == 1
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-ORACLE  reference applier oracle
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-ORACLE: reference applier oracle ─"

INIT_STATE    = DEFINITION['states'].transform_values { |v| v['default'] }
O_INITIAL     = oracle_apply(DEFINITION, INIT_STATE)
O_EXPANDED    = oracle_apply(DEFINITION, INIT_STATE, { element: 'toggle_btn', name: 'click' })
O_COLLAPSED   = oracle_apply(DEFINITION, O_EXPANDED[:state], { element: 'toggle_btn', name: 'click' })

check('ORACLE-01: initial state has expanded = false') do
  O_INITIAL[:state]['expanded'] == false
end

check('ORACLE-02: initial attributes row.classes includes "closed"') do
  (O_INITIAL[:attributes]['row.classes'] || []).include?('closed')
end

check('ORACLE-03: initial attributes row.aria-expanded == "false"') do
  O_INITIAL[:attributes]['row.aria-expanded'] == 'false'
end

check('ORACLE-04: after toggle_btn click: state.expanded == true') do
  O_EXPANDED[:state]['expanded'] == true
end

check('ORACLE-05: after toggle: row.classes includes "open"') do
  (O_EXPANDED[:attributes]['row.classes'] || []).include?('open')
end

check('ORACLE-06: after toggle: row.aria-expanded == "true"') do
  O_EXPANDED[:attributes]['row.aria-expanded'] == 'true'
end

check('ORACLE-07: second toggle: state.expanded == false again') do
  O_COLLAPSED[:state]['expanded'] == false
end

check('ORACLE-08: second toggle: row.classes includes "closed" again') do
  (O_COLLAPSED[:attributes]['row.classes'] || []).include?('closed')
end

check('ORACLE-09: second toggle: row.aria-expanded == "false" again') do
  O_COLLAPSED[:attributes]['row.aria-expanded'] == 'false'
end

check('ORACLE-10: initial oracle result has no host_event') do
  !O_INITIAL.key?(:host_event)
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-INTERP  interpreter matches oracle for every triple
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-INTERP: interpreter ↔ oracle parity ─"

I_INITIAL   = interp_apply(DEFINITION, INIT_STATE)
I_EXPANDED  = interp_apply(DEFINITION, INIT_STATE,
                           { element: 'toggle_btn', name: 'click' })
I_COLLAPSED = interp_apply(DEFINITION, I_EXPANDED['state'],
                           { element: 'toggle_btn', name: 'click' })

check('INTERP-01: interpreter initial state matches oracle') do
  I_INITIAL['state'] == O_INITIAL[:state]
end

check('INTERP-02: interpreter initial attributes match oracle') do
  I_INITIAL['attributes'] == O_INITIAL[:attributes]
end

check('INTERP-03: interpreter expanded state matches oracle') do
  I_EXPANDED['state'] == O_EXPANDED[:state]
end

check('INTERP-04: interpreter expanded attributes match oracle') do
  I_EXPANDED['attributes'] == O_EXPANDED[:attributes]
end

check('INTERP-05: interpreter collapsed-again state matches oracle') do
  I_COLLAPSED['state'] == O_COLLAPSED[:state]
end

check('INTERP-06: interpreter collapsed-again attributes match oracle') do
  I_COLLAPSED['attributes'] == O_COLLAPSED[:attributes]
end

check('INTERP-07: interpreter returns parseable JSON (no parse error)') do
  I_INITIAL.is_a?(Hash) && !I_INITIAL.key?('error')
end

check('INTERP-08: interpreter state values are correct types (boolean expanded)') do
  I_INITIAL['state']['expanded'] == false &&
    I_EXPANDED['state']['expanded'] == true
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-DISPATCH  dispatch emits host event; does not mutate local state
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-DISPATCH: dispatch seam ─"

O_DISPATCH = oracle_apply(DEFINITION, INIT_STATE, { element: 'action_btn', name: 'click' })
I_DISPATCH = interp_apply(DEFINITION, INIT_STATE, { element: 'action_btn', name: 'click' })

check('DISPATCH-01: oracle: action_btn click produces host_event') do
  O_DISPATCH.key?(:host_event) && !O_DISPATCH[:host_event].nil?
end

check('DISPATCH-02: oracle: host_event.event == "file_selected"') do
  O_DISPATCH[:host_event]['event'] == 'file_selected'
end

check('DISPATCH-03: oracle: dispatch does NOT mutate state (state unchanged from init)') do
  O_DISPATCH[:state] == INIT_STATE
end

check('DISPATCH-04: interpreter: action_btn click produces host_event') do
  I_DISPATCH.key?('host_event') && !I_DISPATCH['host_event'].nil?
end

check('DISPATCH-05: interpreter: host_event.event matches oracle') do
  I_DISPATCH['host_event']['event'] == O_DISPATCH[:host_event]['event']
end

check('DISPATCH-06: interpreter: dispatch state unchanged from init') do
  I_DISPATCH['state'] == INIT_STATE
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-FAILCLOSED  unknown op → error, not silent no-op
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-FAILCLOSED: fail-closed on unknown op ─"

O_BADOP = oracle_apply(BAD_OP_DEF, INIT_STATE, { element: 'toggle_btn', name: 'click' })
I_BADOP = interp_apply(BAD_OP_DEF, INIT_STATE, { element: 'toggle_btn', name: 'click' })

check('FAILCLOSED-01: oracle returns error hash for unknown op') do
  O_BADOP.is_a?(Hash) && O_BADOP.key?(:error)
end

check('FAILCLOSED-02: oracle error format starts with "unknown_op:"') do
  O_BADOP[:error].to_s.start_with?('unknown_op:')
end

check('FAILCLOSED-03: interpreter returns error for unknown op') do
  I_BADOP.is_a?(Hash) && I_BADOP.key?('error')
end

check('FAILCLOSED-04: interpreter error value is non-empty string') do
  I_BADOP['error'].is_a?(String) && !I_BADOP['error'].empty?
end

check('FAILCLOSED-05: unknown op does NOT produce host_event') do
  !O_BADOP.key?(:host_event) && !I_BADOP.key?('host_event')
end

check('FAILCLOSED-06: unknown op does NOT include partial state (no state key on error)') do
  !O_BADOP.key?(:state) && !I_BADOP.key?('state')
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-CLOSED  no VM/SIR/capability surface in the definition
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-CLOSED: definition carries no VM/SIR/capability ─"

DEF_JSON_STR = File.read(DEF_FILE, encoding: 'UTF-8').freeze
INTERP_SRC   = File.read(INTERP.to_s, encoding: 'UTF-8').freeze

check('CLOSED-01: definition contains no VM bytecode keys (bytecode/instructions/SIR)') do
  !DEF_JSON_STR.include?('"bytecode"') &&
    !DEF_JSON_STR.include?('"instructions"') &&
    !DEF_JSON_STR.include?('"SIR"')
end

check('CLOSED-02: definition contains no capability fields') do
  !DEF_JSON_STR.include?('"capability"') &&
    !DEF_JSON_STR.include?('"passport"')
end

check('CLOSED-03: definition contains no contract execution semantics') do
  !DEF_JSON_STR.include?('"contract"') &&
    !DEF_JSON_STR.include?('"effect"') &&
    !DEF_JSON_STR.include?('"observed"')
end

check('CLOSED-04: interpreter source contains no eval / Function() / new Function') do
  !INTERP_SRC.include?(' eval(') &&
    !INTERP_SRC.match?(/new\s+Function\s*\(/) &&
    !INTERP_SRC.match?(/Function\s*\(/)
end

check('CLOSED-05: definition def_id matches the content-addressed sha256 pattern') do
  DEFINITION['def_id'].match?(/\Asha256:[0-9a-f]{64}\z/)
end


# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "LAB-IGV-TAILMIX-P2  #{$pass_count}/#{$pass_count + $fail_count} PASS"
if $fail_count.zero?
  puts "All checks PASS — P2 proof complete."
else
  puts "#{$fail_count} FAILURE(S) — see above."
end
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit($fail_count.zero? ? 0 : 1)
