#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igv_tailmix_p4.rb
# LAB-IGV-TAILMIX-P4: Proof-local .igv → definition JSON compiler
#
# Proves that the P3 candidate syntax in sidebar.igv can be mechanically compiled
# to definition JSON that reproduces the hand-authored P3 hashes exactly.
#
# New claims over P3:
#   - IgvCompiler.compile(source) is a pure Ruby function; no external tools
#   - Compiled Sidebar def_id == sha256:c59650b5... (matches hand-authored)
#   - Compiled FileTreeRow def_id == sha256:d9e2a8bb... (matches hand-authored)
#   - Same source → same hashes (content-addressable / deterministic)
#   - Compiled bundle_id matches hand-authored bundle_id
#   - P3 render/oracle/interpreter work unchanged with compiled bundle
#   - Fail-closed on 7 error categories (unknown op, duplicate component, child
#     references missing component, instruction targets undeclared state, invalid
#     state default type, malformed children block, missing component name)
#
# No toolchain, parser, VM, or public API file is changed by this proof.
# The compiler is proof-local Ruby only.
#
# Sections:
#   COMPILE      — parse sidebar.igv → 2 definitions, hashes match (10 checks)
#   ADDR         — content-addressability and semantic-change isolation (6 checks)
#   BUNDLE       — build_bundle from compiled defs; bundle_id matches (7 checks)
#   COMPAT       — compiled bundle works with P3 render/oracle/interpreter (10 checks)
#   FAILCLOSED   — 7 error categories, 2 checks each (14 checks)
#
# Run: ruby igniter-view-engine/proofs/verify_lab_igv_tailmix_p4.rb

require 'json'
require 'digest'
require 'open3'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIX_DIR      = ROOT / 'fixtures' / 'igv_tailmix'
INTERP       = FIX_DIR / 'igv_tailmix_interpreter.js'
BUNDLE_FILE  = FIX_DIR / 'definition_bundle.json'
IGV_SKETCH   = FIX_DIR / 'sidebar.igv'

# Hand-authored fixtures (P3 canonical references)
HAND_BUNDLE  = JSON.parse(File.read(BUNDLE_FILE, encoding: 'UTF-8'))
HAND_FTR_ID  = 'sha256:d9e2a8bb5abdb4850579ba071a7b18bc7e2840e51c3b65c6305211edeebb1cf5'
HAND_SIDE_ID = 'sha256:c59650b539c5111a5d5b2e849c0b2212215640b4fbfb8f5fe6d40584a38b0570'
HAND_BDL_ID  = 'sha256:63157b4265357541c4a21621c2c0afe41c709cc7562f593d0ebe2e1e08c22943'

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


# ══════════════════════════════════════════════════════════════════════════════
# IgvCompiler — proof-local .igv → definition JSON compiler
#
# Parses the P3 candidate syntax (sidebar.igv) and emits content-addressed
# definition hashes. Pure Ruby. Fail-closed on all error categories.
# No grammar adoption, no toolchain authority, no canon claim.
# ══════════════════════════════════════════════════════════════════════════════

module IgvCompiler
  CLOSED_OPS = %w[toggle set add_class remove_class toggle_class
                  set_attr set_aria show hide match dispatch].freeze

  class CompileError < StandardError; end

  Line = Struct.new(:indent, :text)

  # compile(source) → Array of definition hashes (with def_id).
  # Raises CompileError on any structural or semantic error.
  def self.compile(source)
    lines = tokenize(source)
    pos   = [0]
    components = []

    until pos[0] >= lines.size
      line = peek(lines, pos)
      if line && line.indent == 0 && line.text.start_with?('component')
        components << parse_component(lines, pos, components.map { |c| c['component'] })
      else
        pos[0] += 1
      end
    end

    validate_cross_refs!(components)
    components
  end

  # build_bundle(definitions) → bundle hash { bundle_id, component_map, definitions }
  def self.build_bundle(definitions)
    component_map = definitions.each_with_object({}) do |defn, map|
      map[defn['component']] = defn['def_id']
    end
    bundle_id  = 'sha256:' + Digest::SHA256.hexdigest(JSON.generate(component_map))
    defs_by_id = definitions.each_with_object({}) { |d, h| h[d['def_id']] = d }
    { 'bundle_id' => bundle_id, 'component_map' => component_map, 'definitions' => defs_by_id }
  end

  # ── private helpers ──────────────────────────────────────────────────────────

  def self.tokenize(source)
    source.lines
          .map(&:rstrip)
          .reject { |l| l.lstrip.start_with?('--') }
          .reject { |l| l.strip.empty? }
          .map    { |l| Line.new(l.match(/^( *)/)[1].length, l.strip) }
  end
  private_class_method :tokenize

  def self.peek(lines, pos, min_indent = nil)
    i = pos[0]
    return nil if i >= lines.size
    l = lines[i]
    return nil if min_indent && l.indent < min_indent
    l
  end
  private_class_method :peek

  def self.consume(lines, pos)
    line = lines[pos[0]]
    pos[0] += 1
    line
  end
  private_class_method :consume

  def self.parse_component(lines, pos, existing_names)
    header = consume(lines, pos)
    name   = header.text.sub(/^component\s*/, '').strip
    raise CompileError, 'missing component name' if name.empty?
    raise CompileError, "duplicate component: #{name}" if existing_names.include?(name)

    comp = { name: name, states: {}, slots: {}, elements: {}, children: {} }

    while (line = peek(lines, pos, 2))
      break if line.indent < 2

      if line.indent == 2
        case line.text
        when /^slot (\w+) : (.+)/
          consume(lines, pos)
          base_type   = $2.strip.split('[').first.strip
          default_val = slot_default(base_type)
          comp[:slots][$1] = { 'type' => base_type, 'default' => default_val }

        when /^state (\w+) : (\w+) = (.+)/
          consume(lines, pos)
          comp[:states][$1] = { 'default' => parse_default($2, $3.strip) }

        when /^element (\w+)/
          consume(lines, pos)
          comp[:elements][$1] = parse_element(lines, pos, comp[:states])

        when /^children (\w+)/
          consume(lines, pos)
          comp[:children][$1] = parse_children(lines, pos, $1)

        else
          consume(lines, pos)
        end
      else
        break
      end
    end

    finalize(comp)
  end
  private_class_method :parse_component

  def self.parse_element(lines, pos, declared_states)
    el = { rules: [], on: {} }

    while (line = peek(lines, pos, 4))
      break if line.indent < 4

      if line.indent == 4
        if line.text.start_with?('style ')
          consume(lines, pos)
          el[:rules] << parse_rule(lines, pos, line.text.sub(/^style\s+/, ''))
        elsif line.text.start_with?('on ')
          consume(lines, pos)
          event_name        = line.text.sub(/^on\s+/, '').strip
          el[:on][event_name] = parse_instructions(lines, pos, declared_states)
        else
          consume(lines, pos)
        end
      else
        break
      end
    end

    result = {}
    result['rules'] = el[:rules] unless el[:rules].empty?
    result['on']    = el[:on]    unless el[:on].empty?
    result
  end
  private_class_method :parse_element

  def self.parse_rule(lines, pos, condition)
    true_b  = {}
    false_b = nil

    # true branch (indent 6)
    while (line = peek(lines, pos, 6))
      break if line.indent < 6
      consume(lines, pos)
      case line.text
      when /^classes:/  then true_b['classes'] = parse_classes(line.text.sub(/^classes:\s*/, ''))
      when /^aria:/     then true_b['aria']    = parse_aria(line.text.sub(/^aria:\s*/, ''))
      end
    end

    # optional otherwise clause (at level 4)
    if (line = peek(lines, pos, 4)) && line.indent == 4 && line.text == 'otherwise'
      consume(lines, pos)
      false_b = {}
      while (line = peek(lines, pos, 6))
        break if line.indent < 6
        consume(lines, pos)
        case line.text
        when /^classes:/  then false_b['classes'] = parse_classes(line.text.sub(/^classes:\s*/, ''))
        when /^aria:/     then false_b['aria']    = parse_aria(line.text.sub(/^aria:\s*/, ''))
        end
      end
    end

    rule = { 'when' => condition }
    rule['classes'] = true_b['classes'] if true_b['classes']
    rule['aria']    = true_b['aria']    if true_b['aria']
    rule['else']    = false_b           if false_b
    rule
  end
  private_class_method :parse_rule

  def self.parse_instructions(lines, pos, declared_states)
    instructions = []
    while (line = peek(lines, pos, 6))
      break if line.indent < 6
      consume(lines, pos)
      next if line.indent > 6
      inst = parse_instruction(line.text)
      if %w[toggle set].include?(inst['op'])
        key = inst['target'].sub('state.', '')
        raise CompileError, "instruction references undeclared state: #{key}" \
          unless declared_states.key?(key)
      end
      instructions << inst
    end
    instructions
  end
  private_class_method :parse_instructions

  def self.parse_children(lines, pos, block_name)
    comp_ref = nil
    slot_ref = nil
    while (line = peek(lines, pos, 4))
      break if line.indent < 4
      consume(lines, pos)
      if   line.text.start_with?('component ') then comp_ref = line.text.sub(/^component\s+/, '').strip
      elsif line.text.start_with?('from ')      then slot_ref = line.text.sub(/^from\s+/, '').strip
      end
    end
    raise CompileError, "children block '#{block_name}' missing component declaration" if comp_ref.nil?
    { component_ref: comp_ref, slot_ref: slot_ref }
  end
  private_class_method :parse_children

  def self.validate_cross_refs!(components)
    names = components.map { |c| c['component'] }
    components.each do |defn|
      (defn['children'] || {}).each_value do |child|
        ref = child['component']
        raise CompileError, "child references unknown component: #{ref}" unless names.include?(ref)
      end
    end
  end
  private_class_method :validate_cross_refs!

  def self.slot_default(base_type)
    case base_type
    when 'String' then ''
    when 'List'   then []
    else raise CompileError, "unknown slot type: #{base_type}"
    end
  end
  private_class_method :slot_default

  def self.parse_default(type_str, default_str)
    case type_str
    when 'Bool'
      case default_str
      when 'false' then false
      when 'true'  then true
      else raise CompileError, "invalid Bool default: #{default_str}"
      end
    when 'String'
      raise CompileError, "invalid String default (must be quoted): #{default_str}" \
        unless default_str.match?(/^".*"$/)
      default_str[1..-2]
    when 'Int'
      raise CompileError, "invalid Int default: #{default_str}" unless default_str.match?(/^\d+$/)
      default_str.to_i
    else
      raise CompileError, "unknown state type: #{type_str}"
    end
  end
  private_class_method :parse_default

  def self.parse_classes(str)
    str.strip.sub(/^\[/, '').sub(/\]$/, '').split(',').map(&:strip).reject(&:empty?)
  end
  private_class_method :parse_classes

  def self.parse_aria(str)
    result = {}
    str.scan(/(\w+):\s*"([^"]*)"/) { |k, v| result[k] = v }
    result
  end
  private_class_method :parse_aria

  def self.parse_instruction(str)
    parts = str.split(/\s+/, 2)
    op    = parts[0]
    raise CompileError, "unknown op: #{op}" unless CLOSED_OPS.include?(op)
    case op
    when 'toggle', 'set' then { 'op' => op, 'target' => (parts[1] || '') }
    when 'dispatch'      then { 'op' => op, 'event'  => (parts[1] || '') }
    else                      { 'op' => op }
    end
  end
  private_class_method :parse_instruction

  def self.finalize(comp)
    defn = {}
    defn['component'] = comp[:name]
    defn['states']    = comp[:states]
    defn['slots']     = comp[:slots]     unless comp[:slots].empty?
    defn['elements']  = comp[:elements]
    defn['children']  = comp[:children].transform_values { |v|
      { 'component' => v[:component_ref], 'slot' => v[:slot_ref] }
    } unless comp[:children].empty?

    def_id = 'sha256:' + Digest::SHA256.hexdigest(JSON.generate(defn))
    { 'def_id' => def_id }.merge(defn)
  end
  private_class_method :finalize
end


# ── Reference applier oracle (same as P3, generic) ────────────────────────────

CLOSED_OPS_SET = IgvCompiler::CLOSED_OPS.freeze

def oracle_apply(defn, state, event = nil)
  current    = state.dup
  host_event = nil

  if event
    el_def = defn['elements'][event[:element]]
    if el_def && el_def['on'] && el_def['on'][event[:name]]
      el_def['on'][event[:name]].each do |inst|
        op = inst['op']
        return { error: "unknown_op:#{op}" } unless CLOSED_OPS_SET.include?(op)
        case op
        when 'toggle'   then current[inst['target'].sub('state.', '')] ^= true
        when 'set'      then current[inst['target'].sub('state.', '')] = inst['value']
        when 'dispatch' then host_event = { 'event' => inst['event'], 'payload' => inst.fetch('payload', nil) }
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
        attributes["#{el_name}.classes"] = (attributes["#{el_name}.classes"] || []) + effect['classes']
      end
      (effect['aria'] || {}).each { |k, v| attributes["#{el_name}.aria-#{k}"] = v }
    end
  end

  result = { state: current, attributes: attributes }
  result[:host_event] = host_event if host_event
  result
end

def interp_apply(defn, state, event = nil)
  input = { definition: defn, state: state }
  input[:event] = { element: event[:element], name: event[:name] } if event
  stdout, _err, _st = Open3.capture3('node', INTERP.to_s, JSON.generate(input))
  JSON.parse(stdout.strip)
end

def render_nested(inst_id, slots, bundle)
  side_def_id = bundle['component_map']['Sidebar']
  ftr_def_id  = bundle['component_map']['FileTreeRow']
  side_def    = bundle['definitions'][side_def_id]
  ftr_def     = bundle['definitions'][ftr_def_id]
  side_init   = side_def['states'].transform_values { |v| v['default'] }
  ftr_init    = ftr_def['states'].transform_values  { |v| v['default'] }
  items       = slots['items'] || []

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

def canonical_hash(defn)
  content = defn.reject { |k, _| k == 'def_id' }
  'sha256:' + Digest::SHA256.hexdigest(JSON.generate(content))
end


# ── Compile sidebar.igv once; reused across sections ─────────────────────────

IGV_SOURCE     = File.read(IGV_SKETCH, encoding: 'UTF-8').freeze
COMPILED_DEFS  = IgvCompiler.compile(IGV_SOURCE).freeze
COMPILED_SIDE  = COMPILED_DEFS.find { |d| d['component'] == 'Sidebar' }.freeze
COMPILED_FTR   = COMPILED_DEFS.find { |d| d['component'] == 'FileTreeRow' }.freeze
COMPILED_BDL   = IgvCompiler.build_bundle(COMPILED_DEFS).freeze

SAMPLE_ITEMS = [
  { 'label' => 'src',  'path' => '/src'  },
  { 'label' => 'test', 'path' => '/test' },
  { 'label' => 'lib',  'path' => '/lib'  }
].freeze
SAMPLE_SLOTS = { 'title' => 'Explorer', 'items' => SAMPLE_ITEMS }.freeze


# ─────────────────────────────────────────────────────────────────────────────
# § COMPILE  parse sidebar.igv → 2 definitions, hashes match
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ COMPILE: parse sidebar.igv → 2 definitions ─"

check('COMPILE-01: IgvCompiler.compile is callable') do
  IgvCompiler.respond_to?(:compile)
end

check('COMPILE-02: parsing sidebar.igv yields 2 definitions') do
  COMPILED_DEFS.length == 2
end

check('COMPILE-03: first component is Sidebar, second is FileTreeRow') do
  COMPILED_DEFS[0]['component'] == 'Sidebar' &&
    COMPILED_DEFS[1]['component'] == 'FileTreeRow'
end

check('COMPILE-04: compiled Sidebar def_id matches hand-authored') do
  COMPILED_SIDE['def_id'] == HAND_SIDE_ID
end

check('COMPILE-05: compiled FileTreeRow def_id matches hand-authored') do
  COMPILED_FTR['def_id'] == HAND_FTR_ID
end

check('COMPILE-06: compiled Sidebar content (sans def_id) equals hand-authored') do
  compiled_content = COMPILED_SIDE.reject { |k, _| k == 'def_id' }
  hand_content     = HAND_BUNDLE['definitions'][HAND_SIDE_ID].reject { |k, _| k == 'def_id' }
  JSON.generate(compiled_content) == JSON.generate(hand_content)
end

check('COMPILE-07: compiled FileTreeRow content (sans def_id) equals hand-authored') do
  compiled_content = COMPILED_FTR.reject { |k, _| k == 'def_id' }
  hand_content     = HAND_BUNDLE['definitions'][HAND_FTR_ID].reject { |k, _| k == 'def_id' }
  JSON.generate(compiled_content) == JSON.generate(hand_content)
end

check('COMPILE-08: same source compiled twice → same Sidebar def_id') do
  second_compile = IgvCompiler.compile(IGV_SOURCE)
  second_compile.find { |d| d['component'] == 'Sidebar' }['def_id'] == HAND_SIDE_ID
end

check('COMPILE-09: compiled Sidebar def_id is self-consistent (canonical_hash matches)') do
  canonical_hash(COMPILED_SIDE) == COMPILED_SIDE['def_id']
end

check('COMPILE-10: compiled FileTreeRow def_id is self-consistent') do
  canonical_hash(COMPILED_FTR) == COMPILED_FTR['def_id']
end


# ─────────────────────────────────────────────────────────────────────────────
# § ADDR  content-addressability and semantic-change isolation
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ ADDR: content-addressability ─"

check('ADDR-01: comments-only change → same def_id (comments stripped)') do
  commented = "-- extra comment\n" + IGV_SOURCE + "\n-- another comment\n"
  IgvCompiler.compile(commented).find { |d| d['component'] == 'Sidebar' }['def_id'] == HAND_SIDE_ID
end

check('ADDR-02: semantic change (toggle→dispatch) → different FTR def_id') do
  mutant = IGV_SOURCE.sub('toggle state.expanded', 'dispatch state_changed')
  new_id = IgvCompiler.compile(mutant).find { |d| d['component'] == 'FileTreeRow' }['def_id']
  new_id != HAND_FTR_ID
end

check('ADDR-03: different state default → different Sidebar def_id') do
  mutant = IGV_SOURCE.sub('state search_active : Bool = false',
                           'state search_active : Bool = true')
  new_id = IgvCompiler.compile(mutant).find { |d| d['component'] == 'Sidebar' }['def_id']
  new_id != HAND_SIDE_ID
end

check('ADDR-04: extra blank lines only → same def_id') do
  spaced = IGV_SOURCE.gsub("\n", "\n\n")
  IgvCompiler.compile(spaced).find { |d| d['component'] == 'Sidebar' }['def_id'] == HAND_SIDE_ID
end

check('ADDR-05: semantic change in Sidebar does not affect FTR def_id') do
  mutant  = IGV_SOURCE.sub('dispatch sidebar_focused', 'dispatch sidebar_clicked')
  new_ids = IgvCompiler.compile(mutant)
  new_ids.find { |d| d['component'] == 'Sidebar' }['def_id'] != HAND_SIDE_ID &&
    new_ids.find { |d| d['component'] == 'FileTreeRow' }['def_id'] == HAND_FTR_ID
end

check('ADDR-06: swapping component order in source → same individual def_ids') do
  # Split on lookahead for lines starting with "component "; skip leading comment block
  blocks = IGV_SOURCE.split(/(?=^component )/m).select { |b| b.strip.start_with?('component ') }
  if blocks.length == 2
    reversed = blocks[1] + "\n" + blocks[0]
    defs = IgvCompiler.compile(reversed)
    defs.find { |d| d['component'] == 'Sidebar'     }['def_id'] == HAND_SIDE_ID &&
    defs.find { |d| d['component'] == 'FileTreeRow' }['def_id'] == HAND_FTR_ID
  else
    false
  end
end


# ─────────────────────────────────────────────────────────────────────────────
# § BUNDLE  build_bundle from compiled defs; bundle_id matches
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ BUNDLE: build_bundle from compiled definitions ─"

check('BUNDLE-01: build_bundle returns hash with bundle_id, component_map, definitions') do
  %w[bundle_id component_map definitions].all? { |k| COMPILED_BDL.key?(k) }
end

check('BUNDLE-02: compiled bundle has exactly 2 definitions') do
  COMPILED_BDL['definitions'].size == 2
end

check('BUNDLE-03: compiled component_map keys are Sidebar and FileTreeRow') do
  COMPILED_BDL['component_map'].keys.sort == %w[FileTreeRow Sidebar]
end

check('BUNDLE-04: compiled bundle_id matches hand-authored bundle_id') do
  COMPILED_BDL['bundle_id'] == HAND_BDL_ID
end

check('BUNDLE-05: compiled component_map values match hand-authored') do
  COMPILED_BDL['component_map'] == HAND_BUNDLE['component_map']
end

check('BUNDLE-06: semantic change in source → different bundle_id') do
  mutant_defs = IgvCompiler.compile(IGV_SOURCE.sub('dispatch sidebar_focused', 'dispatch sidebar_x'))
  mutant_bdl  = IgvCompiler.build_bundle(mutant_defs)
  mutant_bdl['bundle_id'] != HAND_BDL_ID
end

check('BUNDLE-07: bundle_id is sha256 of component_map only (not definition bodies)') do
  expected = 'sha256:' + Digest::SHA256.hexdigest(JSON.generate(COMPILED_BDL['component_map']))
  COMPILED_BDL['bundle_id'] == expected
end


# ─────────────────────────────────────────────────────────────────────────────
# § COMPAT  compiled bundle works with P3 render/oracle/interpreter
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ COMPAT: compiled bundle with P3 render/oracle/interpreter ─"

COMPAT_RENDER = render_nested('compat-1', SAMPLE_SLOTS, COMPILED_BDL).freeze

check('COMPAT-01: render_nested with compiled bundle returns html and def_refs') do
  COMPAT_RENDER.is_a?(Hash) && COMPAT_RENDER.key?(:html) && COMPAT_RENDER.key?(:def_refs)
end

check('COMPAT-02: compiled render produces 2 unique def_refs') do
  COMPAT_RENDER[:def_refs].uniq.length == 2
end

check('COMPAT-03: compiled and hand-authored bundles produce identical def_refs') do
  hand_render = render_nested('compat-1', SAMPLE_SLOTS, HAND_BUNDLE)
  COMPAT_RENDER[:def_refs].sort == hand_render[:def_refs].sort
end

SIDE_INIT_STATE = COMPILED_SIDE['states'].transform_values { |v| v['default'] }
FTR_INIT_STATE  = COMPILED_FTR['states'].transform_values  { |v| v['default'] }

check('COMPAT-04: oracle on compiled Sidebar init state → browse-mode classes') do
  r = oracle_apply(COMPILED_SIDE, SIDE_INIT_STATE)
  r[:attributes]['header.classes'] == ['browse-mode']
end

check('COMPAT-05: oracle on compiled FTR init state → closed classes') do
  r = oracle_apply(COMPILED_FTR, FTR_INIT_STATE)
  r[:attributes]['row.classes'] == ['closed']
end

check('COMPAT-06: oracle toggle on compiled Sidebar search_toggle → search_active=true') do
  r = oracle_apply(COMPILED_SIDE, SIDE_INIT_STATE, { element: 'search_toggle', name: 'click' })
  r[:state]['search_active'] == true
end

check('COMPAT-07: oracle dispatch on compiled Sidebar header → host_event sidebar_focused') do
  r = oracle_apply(COMPILED_SIDE, SIDE_INIT_STATE, { element: 'header', name: 'click' })
  r[:host_event] && r[:host_event]['event'] == 'sidebar_focused'
end

check('COMPAT-08: interpreter matches oracle for compiled Sidebar toggle') do
  event   = { element: 'search_toggle', name: 'click' }
  o_res   = oracle_apply(COMPILED_SIDE, SIDE_INIT_STATE, event)
  i_res   = interp_apply(COMPILED_SIDE, SIDE_INIT_STATE, event)
  o_res[:state] == i_res['state']
end

check('COMPAT-09: interpreter matches oracle for compiled FTR toggle') do
  event   = { element: 'toggle_btn', name: 'click' }
  o_res   = oracle_apply(COMPILED_FTR, FTR_INIT_STATE, event)
  i_res   = interp_apply(COMPILED_FTR, FTR_INIT_STATE, event)
  o_res[:state] == i_res['state']
end

check('COMPAT-10: interpreter matches oracle for compiled Sidebar dispatch') do
  event   = { element: 'header', name: 'click' }
  o_res   = oracle_apply(COMPILED_SIDE, SIDE_INIT_STATE, event)
  i_res   = interp_apply(COMPILED_SIDE, SIDE_INIT_STATE, event)
  o_res[:host_event] && i_res['host_event'] &&
    o_res[:host_event]['event'] == i_res['host_event']['event']
end


# ─────────────────────────────────────────────────────────────────────────────
# § FAILCLOSED  7 error categories, 2 checks each
# ─────────────────────────────────────────────────────────────────────────────
puts "\n─ FAILCLOSED: compiler error categories ─"

def assert_compile_error(fixture_name)
  src = File.read(
    Pathname.new(__dir__).parent / 'fixtures' / 'igv_tailmix' / fixture_name,
    encoding: 'UTF-8'
  )
  begin
    IgvCompiler.compile(src)
    [false, nil]
  rescue IgvCompiler::CompileError => e
    [true, e.message]
  end
end

# 1. Unknown op
raised_1, msg_1 = assert_compile_error('invalid_unknown_op.igv')
check('FC-01: invalid_unknown_op.igv raises CompileError') { raised_1 }
check('FC-02: error message mentions "unknown op"') { raised_1 && msg_1.include?('unknown op') }

# 2. Duplicate component name
raised_2, msg_2 = assert_compile_error('invalid_duplicate_component.igv')
check('FC-03: invalid_duplicate_component.igv raises CompileError') { raised_2 }
check('FC-04: error message mentions "duplicate"') { raised_2 && msg_2.include?('duplicate') }

# 3. Child references missing component
raised_3, msg_3 = assert_compile_error('invalid_child_missing_component.igv')
check('FC-05: invalid_child_missing_component.igv raises CompileError') { raised_3 }
check('FC-06: error message mentions "unknown component"') { raised_3 && msg_3.include?('unknown component') }

# 4. Instruction targets undeclared state key
raised_4, msg_4 = assert_compile_error('invalid_event_missing_state.igv')
check('FC-07: invalid_event_missing_state.igv raises CompileError') { raised_4 }
check('FC-08: error message mentions "undeclared state"') { raised_4 && msg_4.include?('undeclared state') }

# 5. Invalid state default type
raised_5, msg_5 = assert_compile_error('invalid_state_default_type.igv')
check('FC-09: invalid_state_default_type.igv raises CompileError') { raised_5 }
check('FC-10: error message mentions "invalid"') { raised_5 && msg_5.include?('invalid') }

# 6. Malformed children block (no component line)
raised_6, msg_6 = assert_compile_error('invalid_malformed_block.igv')
check('FC-11: invalid_malformed_block.igv raises CompileError') { raised_6 }
check('FC-12: error message mentions "missing component"') { raised_6 && msg_6.include?('missing component') }

# 7. Missing component name
raised_7, msg_7 = assert_compile_error('invalid_missing_component_name.igv')
check('FC-13: invalid_missing_component_name.igv raises CompileError') { raised_7 }
check('FC-14: error message mentions "missing component name"') { raised_7 && msg_7.include?('missing component name') }


# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
total = $pass_count + $fail_count
puts "\n─────────────────────────────────────────────────────────────────────────────"
puts "#{total} checks: #{$pass_count} PASS, #{$fail_count} FAIL"
puts "─────────────────────────────────────────────────────────────────────────────"
exit($fail_count.zero? ? 0 : 1)
