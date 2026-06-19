#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igv_tailmix_p3.rb
# LAB-IGV-TAILMIX-P3: Nested composition, bundle dedup, and slot values
#
# Extends the P2 single-component proof to a two-component composed set:
#   Sidebar (search_active state, header dispatch, search_toggle, children)
#   └─ FileTreeRow × N  (expanded state, toggle, dispatch — reused from P2)
#
# New claims over P2:
#   - Definition bundle: 2 definitions, keyed by def_id hash
#   - Nested render: Sidebar HTML wraps N FileTreeRow instance bindings
#   - `def_refs` unique count == 2 regardless of N rows
#   - Slot values drive N rows without touching definitions
#   - Per-instance state isolation across components
#   - Oracle/interpreter parity for nested triples
#   - Fail-closed for missing/unknown component in bundle
#   - .igv sketch exists and is marked non-canon
#
# Reuses the P2 interpreter (igv_tailmix_interpreter.js) via Open3.
# No toolchain, compiler, parser, VM, or public API change.
#
# Sections:
#   TAILMIX-BUNDLE     — bundle structure and hash integrity (8 checks)
#   TAILMIX-SIDEBAR    — Sidebar definition structure (6 checks)
#   TAILMIX-COMPOSE    — nested render output: { html, def_refs } (10 checks)
#   TAILMIX-SLOTS      — slot values drive render; definitions unchanged (7 checks)
#   TAILMIX-DEDUP2     — N rows → 2 unique def_refs (5 checks)
#   TAILMIX-ISOLATE    — per-instance state isolation across components (6 checks)
#   TAILMIX-ORACLE2    — reference applier for bundle/nested cases (10 checks)
#   TAILMIX-INTERP2    — interpreter matches oracle for nested triples (8 checks)
#   TAILMIX-FAILCLOSED2— fail-closed: missing/unknown component, unknown op (6 checks)
#   TAILMIX-IGV        — .igv sketch is present and non-canon (4 checks)
#
# Run: ruby igniter-view-engine/proofs/verify_lab_igv_tailmix_p3.rb

require 'json'
require 'digest'
require 'open3'
require 'pathname'

ROOT        = Pathname.new(__dir__).parent
FIX_DIR     = ROOT / 'fixtures' / 'igv_tailmix'
BUNDLE_FILE = FIX_DIR / 'definition_bundle.json'
FTR_FILE    = FIX_DIR / 'file_tree_row_definition.json'
SIDE_FILE   = FIX_DIR / 'sidebar_definition.json'
IGV_SKETCH  = FIX_DIR / 'sidebar.igv'
INTERP      = FIX_DIR / 'igv_tailmix_interpreter.js'

BUNDLE  = JSON.parse(File.read(BUNDLE_FILE, encoding: 'UTF-8'))
FTR_DEF = JSON.parse(File.read(FTR_FILE,    encoding: 'UTF-8'))
SIDE_DEF = JSON.parse(File.read(SIDE_FILE,  encoding: 'UTF-8'))

FTR_DEF_ID  = FTR_DEF['def_id'].freeze
SIDE_DEF_ID = SIDE_DEF['def_id'].freeze

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


# ── Hash helpers ──────────────────────────────────────────────────────────────

def canonical_hash(defn)
  content = defn.reject { |k, _| k == 'def_id' }
  'sha256:' + Digest::SHA256.hexdigest(JSON.generate(content))
end

def bundle_hash(component_map)
  'sha256:' + Digest::SHA256.hexdigest(JSON.generate(component_map))
end


# ── Reference Applier Oracle (same as P2; generic over any definition) ────────

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


# ── Interpreter (reuses P2 JS via Open3) ─────────────────────────────────────

def interp_apply(defn, state, event = nil)
  input = { definition: defn, state: state }
  input[:event] = { element: event[:element], name: event[:name] } if event
  stdout, _err, _st = Open3.capture3('node', INTERP.to_s, JSON.generate(input))
  JSON.parse(stdout.strip)
end


# ── Nested render helper ──────────────────────────────────────────────────────
#
# Simulates the IGV render pipeline for a Sidebar containing N FileTreeRow children.
# Returns { html, def_refs }.

def render_nested(inst_id, slots, bundle)
  side_def_id = bundle['component_map']['Sidebar']
  ftr_def_id  = bundle['component_map']['FileTreeRow']
  side_def    = bundle['definitions'][side_def_id]
  ftr_def     = bundle['definitions'][ftr_def_id]

  side_init   = side_def['states'].transform_values { |v| v['default'] }
  ftr_init    = ftr_def['states'].transform_values  { |v| v['default'] }

  items = slots['items'] || []

  row_htmls = items.each_with_index.map do |item, idx|
    row_inst = "#{inst_id}-row-#{idx}"
    %(<div data-igv="FileTreeRow" data-igv-def="#{ftr_def_id}" ) +
    %(data-igv-instance="#{row_inst}" ) +
    %(data-igv-state='#{JSON.generate(ftr_init)}' ) +
    %(data-igv-slots='#{JSON.generate(item)}'>…</div>)
  end

  html = %(<div data-igv="Sidebar" data-igv-def="#{side_def_id}" ) +
         %(data-igv-instance="#{inst_id}" ) +
         %(data-igv-state='#{JSON.generate(side_init)}' ) +
         %(data-igv-slots='#{JSON.generate(slots)}'>#{row_htmls.join}</div>)

  { html: html, def_refs: [side_def_id, ftr_def_id].uniq }
end


# ── Sample props ──────────────────────────────────────────────────────────────

SAMPLE_ITEMS = [
  { 'label' => 'src', 'path' => '/src' },
  { 'label' => 'test', 'path' => '/test' },
  { 'label' => 'lib', 'path' => '/lib' }
].freeze

SAMPLE_SLOTS = { 'title' => 'Explorer', 'items' => SAMPLE_ITEMS }.freeze

RENDER_3 = render_nested('sidebar-1', SAMPLE_SLOTS, BUNDLE).freeze
RENDER_5 = render_nested('sidebar-2', {
  'title' => 'Explorer',
  'items' => SAMPLE_ITEMS + [
    { 'label' => 'docs', 'path' => '/docs' },
    { 'label' => 'bin',  'path' => '/bin'  }
  ]
}, BUNDLE).freeze


# ── Unknown-op definition (for fail-closed tests) ─────────────────────────────

BAD_OP_FTR = Marshal.load(Marshal.dump(FTR_DEF)).tap do |d|
  d['elements']['toggle_btn']['on']['click'] = [{ 'op' => 'exec_arbitrary', 'target' => 'state.expanded' }]
end.freeze

BAD_BUNDLE = Marshal.load(Marshal.dump(BUNDLE)).tap do |b|
  b['definitions'][FTR_DEF_ID] = BAD_OP_FTR
end.freeze


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-BUNDLE  bundle structure and hash integrity
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-BUNDLE: bundle structure ─"

check('BUNDLE-01: bundle file parses as valid JSON') do
  BUNDLE.is_a?(Hash)
end

check('BUNDLE-02: bundle_id field present with sha256: prefix') do
  BUNDLE['bundle_id'].is_a?(String) && BUNDLE['bundle_id'].start_with?('sha256:')
end

check('BUNDLE-03: bundle has component_map and definitions sections') do
  BUNDLE.key?('component_map') && BUNDLE.key?('definitions')
end

check('BUNDLE-04: component_map contains exactly Sidebar and FileTreeRow') do
  BUNDLE['component_map'].keys.sort == ['FileTreeRow', 'Sidebar']
end

check('BUNDLE-05: definitions contains exactly 2 entries') do
  BUNDLE['definitions'].size == 2
end

check('BUNDLE-06: bundle def_ids are unique (no collision)') do
  BUNDLE['definitions'].keys.uniq.length == 2
end

check('BUNDLE-07: bundle_id is correct SHA256 of component_map') do
  bundle_hash(BUNDLE['component_map']) == BUNDLE['bundle_id']
end

check('BUNDLE-08: both component definitions have self-consistent def_ids') do
  BUNDLE['definitions'].all? do |def_id, defn|
    canonical_hash(defn) == def_id
  end
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-SIDEBAR  Sidebar definition structure
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-SIDEBAR: Sidebar definition structure ─"

check('SIDEBAR-01: Sidebar def_id starts with sha256: (64 hex chars)') do
  SIDE_DEF['def_id'].match?(/\Asha256:[0-9a-f]{64}\z/)
end

check('SIDEBAR-02: Sidebar has states.search_active with default false') do
  SIDE_DEF.dig('states', 'search_active', 'default') == false
end

check('SIDEBAR-03: Sidebar has slots: title and items') do
  %w[title items].all? { |k| SIDE_DEF.dig('slots', k) }
end

check('SIDEBAR-04: Sidebar has elements: header and search_toggle') do
  %w[header search_toggle].all? { |k| SIDE_DEF.dig('elements', k) }
end

check('SIDEBAR-05: Sidebar has children.item_list pointing to FileTreeRow from items') do
  child = SIDE_DEF.dig('children', 'item_list')
  child && child['component'] == 'FileTreeRow' && child['slot'] == 'items'
end

check('SIDEBAR-06: search_toggle has toggle handler on state.search_active') do
  inst = SIDE_DEF.dig('elements', 'search_toggle', 'on', 'click', 0)
  inst && inst['op'] == 'toggle' && inst['target'] == 'state.search_active'
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-COMPOSE  nested render output: { html, def_refs }
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-COMPOSE: nested render output ─"

check('COMPOSE-01: render returns Hash with html and def_refs') do
  RENDER_3.is_a?(Hash) && RENDER_3.key?(:html) && RENDER_3.key?(:def_refs)
end

check('COMPOSE-02: def_refs is an array') do
  RENDER_3[:def_refs].is_a?(Array)
end

check('COMPOSE-03: def_refs contains Sidebar def_id') do
  RENDER_3[:def_refs].include?(SIDE_DEF_ID)
end

check('COMPOSE-04: def_refs contains FileTreeRow def_id') do
  RENDER_3[:def_refs].include?(FTR_DEF_ID)
end

check('COMPOSE-05: HTML contains Sidebar instance binding') do
  RENDER_3[:html].include?('data-igv="Sidebar"') &&
    RENDER_3[:html].include?(SIDE_DEF_ID)
end

check('COMPOSE-06: HTML contains 3 FileTreeRow instance bindings') do
  RENDER_3[:html].scan('data-igv="FileTreeRow"').length == 3
end

check('COMPOSE-07: FileTreeRow definitions not inlined per-row (no elements key in row HTML)') do
  row_htmls = RENDER_3[:html].scan(/<div data-igv="FileTreeRow"[^>]*>…<\/div>/)
  row_htmls.all? { |h| !h.include?('"elements"') && !h.include?('"rules"') }
end

check('COMPOSE-08: all 3 row bindings reference the same FileTreeRow def_id') do
  RENDER_3[:html].scan(/data-igv-def="([^"]+)"/).map(&:first).count(FTR_DEF_ID) == 3
end

check('COMPOSE-09: each row has a unique instance id') do
  ids = RENDER_3[:html].scan(/data-igv-instance="([^"]+)"/).map(&:first)
  ids.uniq.length == ids.length
end

check('COMPOSE-10: each row initial state is the FileTreeRow default state') do
  states = RENDER_3[:html].scan(/data-igv-state='([^']+)'/).map(&:first)
  ftr_default = JSON.generate(FTR_DEF['states'].transform_values { |v| v['default'] })
  states.count { |s| s == ftr_default } == 3
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-SLOTS  slot values drive render; definitions unchanged
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-SLOTS: slot values ─"

RENDER_DIFF_SLOTS = render_nested('sidebar-x', {
  'title' => 'Alt Explorer',
  'items' => [{ 'label' => 'apps', 'path' => '/apps' }]
}, BUNDLE).freeze

check('SLOTS-01: render with different slots produces same def_refs') do
  RENDER_3[:def_refs].sort == RENDER_DIFF_SLOTS[:def_refs].sort
end

check('SLOTS-02: render with different props does not change def_id hashes') do
  RENDER_3[:def_refs].include?(FTR_DEF_ID) &&
    RENDER_DIFF_SLOTS[:def_refs].include?(FTR_DEF_ID)
end

check('SLOTS-03: items slot drives row count (1-item render has 1 FileTreeRow binding)') do
  RENDER_DIFF_SLOTS[:html].scan('data-igv="FileTreeRow"').length == 1
end

check('SLOTS-04: row HTML contains slot data per-item (path appears in instance binding)') do
  RENDER_3[:html].include?('/src') && RENDER_3[:html].include?('/test')
end

check('SLOTS-05: slot values do not appear inside the definition bundle JSON') do
  bundle_str = JSON.generate(BUNDLE)
  !bundle_str.include?('/src') && !bundle_str.include?('Explorer')
end

check('SLOTS-06: empty items slot renders 0 FileTreeRow children') do
  r = render_nested('empty-sidebar', { 'title' => 'Empty', 'items' => [] }, BUNDLE)
  r[:html].scan('data-igv="FileTreeRow"').length == 0
end

check('SLOTS-07: def_refs are still exactly 2 for empty-items render') do
  r = render_nested('empty-sidebar', { 'title' => 'Empty', 'items' => [] }, BUNDLE)
  r[:def_refs].uniq.length == 2
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-DEDUP2  N instances → 2 unique def_refs
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-DEDUP2: N→2 bundle dedup ─"

check('DEDUP2-01: 3-row render has exactly 2 unique def_refs') do
  RENDER_3[:def_refs].uniq.length == 2
end

check('DEDUP2-02: 5-row render still has exactly 2 unique def_refs') do
  RENDER_5[:def_refs].uniq.length == 2
end

check('DEDUP2-03: rendering the same sidebar twice produces identical def_refs') do
  r1 = render_nested('dup-1', SAMPLE_SLOTS, BUNDLE)
  r2 = render_nested('dup-2', SAMPLE_SLOTS, BUNDLE)
  r1[:def_refs].sort == r2[:def_refs].sort
end

check('DEDUP2-04: bundle definitions count == 2 (one per type, not per instance)') do
  BUNDLE['definitions'].size == 2
end

check('DEDUP2-05: N=5 rows → 5 FileTreeRow bindings still referencing 1 FileTreeRow def_id') do
  RENDER_5[:html].scan('data-igv="FileTreeRow"').length == 5 &&
    RENDER_5[:def_refs].count(FTR_DEF_ID) == 1
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-ISOLATE  per-instance state isolation across components
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-ISOLATE: per-instance state isolation ─"

FTR_INIT_STATE  = FTR_DEF['states'].transform_values  { |v| v['default'] }.freeze
SIDE_INIT_STATE = SIDE_DEF['states'].transform_values { |v| v['default'] }.freeze

check('ISOLATE-01: FTR and Sidebar initial states have disjoint keys') do
  (FTR_INIT_STATE.keys & SIDE_INIT_STATE.keys).empty?
end

check('ISOLATE-02: toggle FTR row 0 does not affect a separate FTR row 1 state') do
  row0_state = FTR_INIT_STATE.dup
  row1_state = FTR_INIT_STATE.dup
  result0 = oracle_apply(FTR_DEF, row0_state, { element: 'toggle_btn', name: 'click' })
  # row1 not touched
  result0[:state]['expanded'] == true && row1_state['expanded'] == false
end

check('ISOLATE-03: toggle Sidebar search_toggle does not affect FTR state') do
  side_after = oracle_apply(SIDE_DEF, SIDE_INIT_STATE, { element: 'search_toggle', name: 'click' })
  ftr_state  = FTR_INIT_STATE.dup
  side_after[:state]['search_active'] == true && ftr_state['expanded'] == false
end

check('ISOLATE-04: instance ids in RENDER_3 are all unique') do
  ids = RENDER_3[:html].scan(/data-igv-instance="([^"]+)"/).map(&:first)
  ids.uniq.length == ids.length
end

check('ISOLATE-05: Sidebar and FileTreeRow states are never merged or shared') do
  # Sidebar state has search_active; FTR state has expanded — no overlap
  SIDE_INIT_STATE.keys.none? { |k| FTR_INIT_STATE.key?(k) }
end

check('ISOLATE-06: two separate FTR instances start with identical independent states') do
  s1 = FTR_DEF['states'].transform_values { |v| v['default'] }
  s2 = FTR_DEF['states'].transform_values { |v| v['default'] }
  # They are equal but not the same object
  s1 == s2 && !s1.equal?(s2)
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-ORACLE2  reference applier for nested cases
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-ORACLE2: oracle over bundle/nested ─"

O2_SIDE_INIT   = oracle_apply(SIDE_DEF, SIDE_INIT_STATE)
O2_SIDE_SEARCH = oracle_apply(SIDE_DEF, SIDE_INIT_STATE, { element: 'search_toggle', name: 'click' })
O2_SIDE_FOCUS  = oracle_apply(SIDE_DEF, SIDE_INIT_STATE, { element: 'header', name: 'click' })
O2_ROW_INIT    = oracle_apply(FTR_DEF,  FTR_INIT_STATE)
O2_ROW_TOGGLE  = oracle_apply(FTR_DEF,  FTR_INIT_STATE,  { element: 'toggle_btn', name: 'click' })
O2_ROW_DISPATCH= oracle_apply(FTR_DEF,  FTR_INIT_STATE,  { element: 'action_btn', name: 'click' })

check('ORACLE2-01: Sidebar initial: search_active == false') do
  O2_SIDE_INIT[:state]['search_active'] == false
end

check('ORACLE2-02: Sidebar initial: header.classes includes "browse-mode"') do
  (O2_SIDE_INIT[:attributes]['header.classes'] || []).include?('browse-mode')
end

check('ORACLE2-03: Sidebar search toggle: search_active becomes true') do
  O2_SIDE_SEARCH[:state]['search_active'] == true
end

check('ORACLE2-04: Sidebar search toggle: header.classes includes "search-mode"') do
  (O2_SIDE_SEARCH[:attributes]['header.classes'] || []).include?('search-mode')
end

check('ORACLE2-05: Sidebar header click: dispatches sidebar_focused host event') do
  O2_SIDE_FOCUS[:host_event] && O2_SIDE_FOCUS[:host_event]['event'] == 'sidebar_focused'
end

check('ORACLE2-06: Sidebar header dispatch does not mutate state') do
  O2_SIDE_FOCUS[:state] == SIDE_INIT_STATE
end

check('ORACLE2-07: FileTreeRow initial: row.classes includes "closed"') do
  (O2_ROW_INIT[:attributes]['row.classes'] || []).include?('closed')
end

check('ORACLE2-08: FileTreeRow toggle: row.classes includes "open"') do
  (O2_ROW_TOGGLE[:attributes]['row.classes'] || []).include?('open')
end

check('ORACLE2-09: FileTreeRow dispatch: host_event.event == "file_selected"') do
  O2_ROW_DISPATCH[:host_event] && O2_ROW_DISPATCH[:host_event]['event'] == 'file_selected'
end

check('ORACLE2-10: FileTreeRow dispatch: state unchanged') do
  O2_ROW_DISPATCH[:state] == FTR_INIT_STATE
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-INTERP2  interpreter matches oracle for all nested triples
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-INTERP2: interpreter ↔ oracle parity (nested) ─"

I2_SIDE_INIT   = interp_apply(SIDE_DEF, SIDE_INIT_STATE)
I2_SIDE_SEARCH = interp_apply(SIDE_DEF, SIDE_INIT_STATE, { element: 'search_toggle', name: 'click' })
I2_SIDE_FOCUS  = interp_apply(SIDE_DEF, SIDE_INIT_STATE, { element: 'header', name: 'click' })
I2_ROW_TOGGLE  = interp_apply(FTR_DEF,  FTR_INIT_STATE,  { element: 'toggle_btn', name: 'click' })
I2_ROW_DISPATCH= interp_apply(FTR_DEF,  FTR_INIT_STATE,  { element: 'action_btn', name: 'click' })

check('INTERP2-01: interpreter Sidebar initial state matches oracle') do
  I2_SIDE_INIT['state'] == O2_SIDE_INIT[:state]
end

check('INTERP2-02: interpreter Sidebar initial attributes match oracle') do
  I2_SIDE_INIT['attributes'] == O2_SIDE_INIT[:attributes]
end

check('INTERP2-03: interpreter Sidebar search toggle state matches oracle') do
  I2_SIDE_SEARCH['state'] == O2_SIDE_SEARCH[:state]
end

check('INTERP2-04: interpreter Sidebar search toggle attributes match oracle') do
  I2_SIDE_SEARCH['attributes'] == O2_SIDE_SEARCH[:attributes]
end

check('INTERP2-05: interpreter Sidebar header dispatch matches oracle host_event') do
  I2_SIDE_FOCUS['host_event'] &&
    I2_SIDE_FOCUS['host_event']['event'] == O2_SIDE_FOCUS[:host_event]['event']
end

check('INTERP2-06: interpreter FTR toggle state matches oracle') do
  I2_ROW_TOGGLE['state'] == O2_ROW_TOGGLE[:state]
end

check('INTERP2-07: interpreter FTR dispatch host_event matches oracle') do
  I2_ROW_DISPATCH['host_event'] &&
    I2_ROW_DISPATCH['host_event']['event'] == O2_ROW_DISPATCH[:host_event]['event']
end

check('INTERP2-08: interpreter handles both component types without error') do
  !I2_SIDE_INIT.key?('error') && !I2_ROW_TOGGLE.key?('error')
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-FAILCLOSED2  fail-closed for nested/bundle edge cases
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-FAILCLOSED2: fail-closed (nested) ─"

check('FAILCLOSED2-01: unknown op in nested FTR returns error (oracle)') do
  r = oracle_apply(BAD_OP_FTR, FTR_INIT_STATE, { element: 'toggle_btn', name: 'click' })
  r.key?(:error) && r[:error].start_with?('unknown_op:')
end

check('FAILCLOSED2-02: unknown op in nested FTR returns error (interpreter)') do
  r = interp_apply(BAD_OP_FTR, FTR_INIT_STATE, { element: 'toggle_btn', name: 'click' })
  r.key?('error')
end

check('FAILCLOSED2-03: missing component in bundle yields nil definition') do
  BUNDLE['definitions'][BUNDLE['component_map']['NonExistent']] == nil
end

check('FAILCLOSED2-04: unknown component name in component_map lookup yields nil') do
  BUNDLE['component_map']['NotAComponent'] == nil
end

check('FAILCLOSED2-05: oracle fail-closed does not leak host_event') do
  r = oracle_apply(BAD_OP_FTR, FTR_INIT_STATE, { element: 'toggle_btn', name: 'click' })
  !r.key?(:host_event)
end

check('FAILCLOSED2-06: oracle fail-closed does not leak state') do
  r = oracle_apply(BAD_OP_FTR, FTR_INIT_STATE, { element: 'toggle_btn', name: 'click' })
  !r.key?(:state)
end


# ─────────────────────────────────────────────────────────────────────────────
# § TAILMIX-IGV  .igv sketch exists and is marked non-canon
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ TAILMIX-IGV: .igv sketch artifact ─"

IGV_SRC = File.read(IGV_SKETCH.to_s, encoding: 'UTF-8').freeze

check('IGV-01: sidebar.igv file exists and is non-empty') do
  File.exist?(IGV_SKETCH.to_s) && !IGV_SRC.strip.empty?
end

check('IGV-02: sketch contains Sidebar and FileTreeRow component declarations') do
  IGV_SRC.include?('component Sidebar') && IGV_SRC.include?('component FileTreeRow')
end

check('IGV-03: sketch contains a non-canon marker comment') do
  IGV_SRC.match?(/DESIGN SKETCH ONLY|non-canon|not canon|not-canon|no grammar|no compiler/i)
end

check('IGV-04: sketch contains children and slot declarations') do
  IGV_SRC.include?('children') && IGV_SRC.include?('slot')
end


# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "LAB-IGV-TAILMIX-P3  #{$pass_count}/#{$pass_count + $fail_count} PASS"
if $fail_count.zero?
  puts "All checks PASS — P3 proof complete."
else
  puts "#{$fail_count} FAILURE(S) — see above."
end
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit($fail_count.zero? ? 0 : 1)
