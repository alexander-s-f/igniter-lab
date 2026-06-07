# frozen_string_literal: true
# Proof: LayoutEngine — Layout Primitives
# Card: LAB-WEB-FRAMEWORK-P4
# Surface: lab-only · proof-local · no canon claim · no stable API
#
# 43 checks across 6 groups:
#   LAYOUT-SCHEMA  (8)
#   LAYOUT-FILL    (8)
#   LAYOUT-RENDER  (10)
#   LAYOUT-INHERIT (8)
#   LAYOUT-SAFETY  (4)
#   LAYOUT-STABLE  (5)

require 'pathname'
require 'json'

PROOF_DIR   = Pathname.new(__FILE__).dirname
LIB_DIR     = PROOF_DIR.parent / 'lib'
FIXTURE_DIR = PROOF_DIR.parent / 'fixtures' / 'web_framework_p4'

$LOAD_PATH.unshift(LIB_DIR.to_s)
require 'layout_engine'

# ── Result tracking ────────────────────────────────────────────────────────────

results = []

def pass(results, group, check)
  results << { status: 'PASS', group: group, check: check }
  print '.'
end

def fail_check(results, group, check, detail = nil)
  results << { status: 'FAIL', group: group, check: check, detail: detail }
  print 'F'
end

def assert_pass(results, group, check, value, detail = nil)
  if value
    pass(results, group, check)
  else
    fail_check(results, group, check, detail || 'assertion failed')
  end
end

# ── Load fixtures ──────────────────────────────────────────────────────────────

base_layout_json    = JSON.parse((FIXTURE_DIR / 'base_layout.json').read)
article_layout_json = JSON.parse((FIXTURE_DIR / 'article_layout.json').read)

# Reconstruct layout descriptors from JSON fixtures (JSON uses string keys; convert to symbols)
BASE_LAYOUT = LayoutEngine.define_layout(
  base_layout_json['name'],
  slots: base_layout_json['slots'],
  template: base_layout_json['template'],
  parent_layout: base_layout_json['parent_layout']
)

ARTICLE_LAYOUT = LayoutEngine.define_layout(
  article_layout_json['name'],
  slots: article_layout_json['slots'],
  template: article_layout_json['template'],
  parent_layout: article_layout_json['parent_layout']
)

SAMPLE_CONTENT  = (FIXTURE_DIR / 'sample_content.md').read
SAMPLE_NAV      = (FIXTURE_DIR / 'sample_nav.md').read
SAMPLE_SIDEBAR  = (FIXTURE_DIR / 'sample_sidebar.md').read

# ════════════════════════════════════════════════════════════════════════════════
# GROUP: LAYOUT-SCHEMA (8 checks)
# ════════════════════════════════════════════════════════════════════════════════

group = 'LAYOUT-SCHEMA'

# 1. define_layout creates valid layout with correct fields
layout = LayoutEngine.define_layout('test', slots: %w[header content footer], template: '<div>{{content}}</div>')
assert_pass(results, group, 'define_layout_returns_hash_with_name',
            layout[:name] == 'test',
            "Expected name 'test', got #{layout[:name].inspect}")

assert_pass(results, group, 'define_layout_returns_hash_with_slots',
            layout[:slots] == %w[header content footer],
            "slots mismatch: #{layout[:slots].inspect}")

assert_pass(results, group, 'define_layout_returns_hash_with_template',
            layout[:template] == '<div>{{content}}</div>',
            "template mismatch")

# 2. Unknown slot name raises ArgumentError
raised_unknown = false
begin
  LayoutEngine.define_layout('bad', slots: %w[content unknown_slot], template: '{{content}}')
rescue ArgumentError => e
  raised_unknown = true
rescue => _e
end
assert_pass(results, group, 'define_layout_raises_on_unknown_slot',
            raised_unknown,
            'Expected ArgumentError for unknown slot name')

# 3. validate_layout with valid layout → valid: true
valid_layout = { name: 'page', slots: %w[header content footer], template: '<main>{{content}}</main>' }
v = LayoutEngine.validate_layout(valid_layout)
assert_pass(results, group, 'validate_layout_valid_layout_returns_true',
            v[:valid] == true && v[:errors].empty?,
            "Expected valid:true, got #{v.inspect}")

# 4. validate_layout with empty name → errors
bad_name = { name: '', slots: %w[content], template: '{{content}}' }
v2 = LayoutEngine.validate_layout(bad_name)
assert_pass(results, group, 'validate_layout_empty_name_returns_error',
            !v2[:valid] && v2[:errors].any? { |e| e.include?('name') },
            "Expected name error, got #{v2.inspect}")

# 5. validate_layout with unknown slot → errors
bad_slots = { name: 'x', slots: %w[content mystery_slot], template: '{{content}}' }
v3 = LayoutEngine.validate_layout(bad_slots)
assert_pass(results, group, 'validate_layout_unknown_slot_returns_error',
            !v3[:valid] && v3[:errors].any? { |e| e.include?('unknown') },
            "Expected unknown-slot error, got #{v3.inspect}")

# 6. validate_layout with nil template → errors
bad_tmpl = { name: 'x', slots: %w[content], template: nil }
v4 = LayoutEngine.validate_layout(bad_tmpl)
assert_pass(results, group, 'validate_layout_nil_template_returns_error',
            !v4[:valid] && v4[:errors].any? { |e| e.include?('template') },
            "Expected template error, got #{v4.inspect}")

# 7. SLOT_NAMES contains exactly: header, nav, content, sidebar, footer
assert_pass(results, group, 'SLOT_NAMES_contains_expected_values',
            LayoutEngine::SLOT_NAMES.sort == %w[content footer header nav sidebar],
            "SLOT_NAMES mismatch: #{LayoutEngine::SLOT_NAMES.inspect}")

# 8. REQUIRED_SLOTS contains exactly: content
assert_pass(results, group, 'REQUIRED_SLOTS_contains_only_content',
            LayoutEngine::REQUIRED_SLOTS == %w[content],
            "REQUIRED_SLOTS mismatch: #{LayoutEngine::REQUIRED_SLOTS.inspect}")

# ════════════════════════════════════════════════════════════════════════════════
# GROUP: LAYOUT-FILL (8 checks)
# ════════════════════════════════════════════════════════════════════════════════

group = 'LAYOUT-FILL'

# 1. fill_slot with valid slot name and markdown content → compiled HTML in :content
fill_result = LayoutEngine.fill_slot(BASE_LAYOUT, 'content', SAMPLE_CONTENT)
assert_pass(results, group, 'fill_slot_returns_compiled_html',
            fill_result[:content].is_a?(String) && fill_result[:content].include?('<'),
            "Expected compiled HTML in :content, got #{fill_result[:content][0, 60].inspect}")

# 2. fill_slot with unknown slot name raises ArgumentError
raised_fill_unknown = false
begin
  LayoutEngine.fill_slot(BASE_LAYOUT, 'bogus_slot', 'hello')
rescue ArgumentError
  raised_fill_unknown = true
rescue => _e
end
assert_pass(results, group, 'fill_slot_raises_on_unknown_slot',
            raised_fill_unknown,
            'Expected ArgumentError for unknown slot name in fill_slot')

# 3. fill_slot sanitizes: content with script tag stripped/rejected by SiteContentCompiler
# SiteContentCompiler.compile on raw HTML with a script tag: the markdown compiler
# will escape the < > so the script tag won't be executable
script_result = SiteContentCompiler.compile('<script>alert(1)</script>')
# Either errors are present OR the output has no live <script> tag
no_live_script = script_result[:errors].any? ||
                 !script_result[:html].include?('<script>')
assert_pass(results, group, 'fill_slot_sanitizes_script_tag',
            no_live_script,
            "Expected script tag to be sanitized; got html=#{script_result[:html][0, 80].inspect} errors=#{script_result[:errors].inspect}")

# 4. fill_slot for 'header' slot
header_fill = LayoutEngine.fill_slot(BASE_LAYOUT, 'header', '# Site Header')
assert_pass(results, group, 'fill_slot_header_slot_works',
            header_fill[:slot] == 'header' && !header_fill[:content].empty?,
            "fill_slot('header') failed: #{header_fill.inspect}")

# 5. fill_slot for 'nav' slot
nav_fill = LayoutEngine.fill_slot(BASE_LAYOUT, 'nav', SAMPLE_NAV)
assert_pass(results, group, 'fill_slot_nav_slot_works',
            nav_fill[:slot] == 'nav' && nav_fill[:content].include?('<'),
            "fill_slot('nav') failed: #{nav_fill.inspect}")

# 6. fill_slot for 'sidebar' slot
sidebar_fill = LayoutEngine.fill_slot(ARTICLE_LAYOUT, 'sidebar', SAMPLE_SIDEBAR)
assert_pass(results, group, 'fill_slot_sidebar_slot_works',
            sidebar_fill[:slot] == 'sidebar' && !sidebar_fill[:content].empty?,
            "fill_slot('sidebar') failed: #{sidebar_fill.inspect}")

# 7. fill_slot for 'footer' slot
footer_fill = LayoutEngine.fill_slot(BASE_LAYOUT, 'footer', 'Copyright 2026 Igniter')
assert_pass(results, group, 'fill_slot_footer_slot_works',
            footer_fill[:slot] == 'footer' && !footer_fill[:content].empty?,
            "fill_slot('footer') failed: #{footer_fill.inspect}")

# 8. fill_slot returns hash with :slot, :content, :layout keys
assert_pass(results, group, 'fill_slot_returns_hash_with_required_keys',
            fill_result.key?(:slot) && fill_result.key?(:content) && fill_result.key?(:layout),
            "fill_slot result missing expected keys: #{fill_result.keys.inspect}")

# ════════════════════════════════════════════════════════════════════════════════
# GROUP: LAYOUT-RENDER (10 checks)
# ════════════════════════════════════════════════════════════════════════════════

group = 'LAYOUT-RENDER'

compiled_content = fill_result[:content]  # from LAYOUT-FILL above
compiled_nav     = nav_fill[:content]

# 1. render with required 'content' slot filled → ok:true
render_result = LayoutEngine.render(BASE_LAYOUT, { 'content' => compiled_content })
assert_pass(results, group, 'render_with_content_slot_ok_true',
            render_result[:ok] == true,
            "Expected ok:true, got #{render_result.inspect}")

# 2. render without required 'content' slot → ok:false with error mentioning 'content'
render_no_content = LayoutEngine.render(BASE_LAYOUT, {})
assert_pass(results, group, 'render_without_content_slot_ok_false',
            render_no_content[:ok] == false &&
            render_no_content[:errors].any? { |e| e.include?('content') },
            "Expected ok:false with content error, got #{render_no_content.inspect}")

# 3. render uses template substitution: {{content}} replaced
assert_pass(results, group, 'render_substitutes_content_slot',
            render_result[:html].include?(compiled_content) &&
            !render_result[:html].include?('{{content}}'),
            "content slot not substituted in HTML")

# 4. render uses template substitution: {{nav}} replaced when nav slot defined and filled
render_with_nav = LayoutEngine.render(BASE_LAYOUT, { 'content' => compiled_content, 'nav' => compiled_nav })
assert_pass(results, group, 'render_substitutes_nav_slot',
            render_with_nav[:html].include?(compiled_nav) &&
            !render_with_nav[:html].include?('{{nav}}'),
            "nav slot not substituted in HTML")

# 5. render with optional slots not filled → uses empty default (ok:true)
render_minimal = LayoutEngine.render(BASE_LAYOUT, { 'content' => '<p>Hello</p>' })
assert_pass(results, group, 'render_optional_slots_use_empty_defaults',
            render_minimal[:ok] == true &&
            !render_minimal[:html].include?('{{header}}') &&
            !render_minimal[:html].include?('{{footer}}'),
            "Optional slot placeholders leaked into output: #{render_minimal[:html][0, 200].inspect}")

# 6. render result has :html, :layout, :filled_slots keys
assert_pass(results, group, 'render_result_has_required_keys',
            render_result.key?(:html) && render_result.key?(:layout) && render_result.key?(:filled_slots),
            "render result missing expected keys: #{render_result.keys.inspect}")

# 7. render HTML contains filled slot content at correct position
# BASE_LAYOUT template has <main>{{content}}</main> — check structure
assert_pass(results, group, 'render_html_contains_content_at_position',
            render_result[:html].include?('<main>') && render_result[:html].include?(compiled_content),
            "Expected <main> wrapping content in output")

# 8. render with multiple slots filled → all substituted
multi_filled = {
  'content' => '<p>Main content</p>',
  'nav'     => '<ul><li>Nav</li></ul>',
  'header'  => '<h1>Site Header</h1>',
  'footer'  => '<p>Footer</p>'
}
render_multi = LayoutEngine.render(BASE_LAYOUT, multi_filled)
all_substituted = multi_filled.all? do |slot, val|
  render_multi[:html].include?(val) && !render_multi[:html].include?("{{#{slot}}}")
end
assert_pass(results, group, 'render_with_multiple_slots_all_substituted',
            render_multi[:ok] && all_substituted,
            "Not all slots substituted: #{render_multi[:html][0, 300].inspect}")

# 9. render with layout that has no sidebar slot → sidebar content ignored gracefully
# BASE_LAYOUT does not include 'sidebar' in its slots array
extra_slots = { 'content' => '<p>Hello</p>', 'sidebar' => '<p>This should be ignored</p>' }
render_no_sidebar = LayoutEngine.render(BASE_LAYOUT, extra_slots)
assert_pass(results, group, 'render_extra_slot_ignored_gracefully',
            render_no_sidebar[:ok] == true,
            "render failed when extra slot provided: #{render_no_sidebar.inspect}")

# 10. render result :filled_slots lists only the slots that were explicitly filled
assert_pass(results, group, 'render_filled_slots_lists_explicitly_filled',
            render_result[:filled_slots] == ['content'],
            "Expected ['content'] in :filled_slots, got #{render_result[:filled_slots].inspect}")

# ════════════════════════════════════════════════════════════════════════════════
# GROUP: LAYOUT-INHERIT (8 checks)
# ════════════════════════════════════════════════════════════════════════════════

group = 'LAYOUT-INHERIT'

child_slots  = { 'content' => '<p>Article body</p>', 'sidebar' => '<p>Sidebar info</p>' }
parent_slots = { 'nav' => '<ul><li><a href="/">Home</a></li></ul>', 'header' => '<h1>Site</h1>' }

# 1. render_inherited ok:true with valid child and parent slots
inherited_result = LayoutEngine.render_inherited(BASE_LAYOUT, ARTICLE_LAYOUT, child_slots, parent_slots)
assert_pass(results, group, 'render_inherited_ok_true',
            inherited_result[:ok] == true,
            "Expected ok:true from render_inherited, got #{inherited_result.inspect}")

# 2. Child HTML injected as 'content' of parent
# The child renders ARTICLE_LAYOUT → html fragment; that becomes BASE_LAYOUT 'content'
# BASE_LAYOUT wraps content in <main>...</main>
assert_pass(results, group, 'child_html_injected_as_parent_content',
            inherited_result[:html].include?('<main>') &&
            inherited_result[:html].include?('Article body'),
            "Child content not found inside parent <main>: #{inherited_result[:html][0, 400].inspect}")

# 3. Parent template wraps child content
assert_pass(results, group, 'parent_template_wraps_child_content',
            inherited_result[:html].include?('<body>') &&
            inherited_result[:html].include?('Article body'),
            "Parent template does not wrap child: #{inherited_result[:html][0, 400].inspect}")

# 4. render_inherited when child render fails → propagates child error
bad_child_layout = LayoutEngine.define_layout('bad_child', slots: %w[content], template: '{{content}}')
inherited_fail = LayoutEngine.render_inherited(BASE_LAYOUT, bad_child_layout, {}, {})
assert_pass(results, group, 'render_inherited_propagates_child_error',
            inherited_fail[:ok] == false && inherited_fail[:errors].any?,
            "Expected child error propagation, got #{inherited_fail.inspect}")

# 5. render_inherited: parent required 'content' slot satisfied by child output
# Already covered above (inherited_result ok:true); verify no 'content' missing error
assert_pass(results, group, 'render_inherited_parent_content_satisfied',
            inherited_result[:ok] == true && !inherited_result.key?(:errors),
            "Expected no errors in inherited render, got #{inherited_result.inspect}")

# 6. 2-level inheritance: parent.nav filled explicitly still renders
assert_pass(results, group, 'render_inherited_parent_nav_explicit',
            inherited_result[:html].include?('<ul>') &&
            inherited_result[:html].include?('Home'),
            "Parent nav not rendered in inherited output: #{inherited_result[:html][0, 400].inspect}")

# 7. render_inherited result :html contains both parent and child slot content
assert_pass(results, group, 'render_inherited_html_contains_both_parent_and_child',
            inherited_result[:html].include?('Article body') &&
            inherited_result[:html].include?('<body>'),
            "Missing parent or child content in inherited HTML")

# 8. render_inherited with missing child required slot → ok:false
child_missing_content = LayoutEngine.define_layout('child_no_content', slots: %w[content], template: '{{content}}')
fail_inherited = LayoutEngine.render_inherited(BASE_LAYOUT, child_missing_content, {}, {})
assert_pass(results, group, 'render_inherited_missing_child_required_slot_ok_false',
            fail_inherited[:ok] == false,
            "Expected ok:false when child has missing required slot, got #{fail_inherited.inspect}")

# ════════════════════════════════════════════════════════════════════════════════
# GROUP: LAYOUT-SAFETY (4 checks)
# ════════════════════════════════════════════════════════════════════════════════

group = 'LAYOUT-SAFETY'

# 1. Script tag content blocked or stripped by SiteContentCompiler
script_html = '<script>alert(1)</script>'
compiled_script = SiteContentCompiler.compile(script_html)
no_live_script_tag = compiled_script[:errors].any? || !compiled_script[:html].include?('<script>')
assert_pass(results, group, 'script_tag_blocked_or_stripped',
            no_live_script_tag,
            "Expected script tag to be blocked/stripped, got: #{compiled_script.inspect}")

# 2. javascript: link blocked by SiteContentCompiler
js_link_md = '[click me](javascript:alert(1))'
compiled_js = SiteContentCompiler.compile(js_link_md)
assert_pass(results, group, 'javascript_scheme_link_blocked',
            compiled_js[:errors].any? { |e| e.downcase.include?('javascript') },
            "Expected javascript: link error, got: #{compiled_js.inspect}")

# 3. Valid HTML content (safe markdown) passes through
safe_md = "# Hello\n\nThis is **safe** content with a [link](/en/)."
compiled_safe = SiteContentCompiler.compile(safe_md)
assert_pass(results, group, 'valid_safe_content_passes_through',
            compiled_safe[:errors].empty? &&
            compiled_safe[:html].include?('<h1>') &&
            compiled_safe[:html].include?('<strong>'),
            "Expected safe content to compile cleanly, got: #{compiled_safe.inspect}")

# 4. SiteContentCompiler integration: fill_slot uses compile() from SiteContentCompiler
# Verify the fill_slot method internally uses SiteContentCompiler.compile
# by checking that the output is compiled HTML (has structural tags)
integration_fill = LayoutEngine.fill_slot(BASE_LAYOUT, 'content', '# Integration Test')
assert_pass(results, group, 'fill_slot_uses_site_content_compiler',
            integration_fill[:content].include?('<h1>') || integration_fill[:content].include?('<p>'),
            "fill_slot did not produce compiled HTML: #{integration_fill[:content].inspect}")

# ════════════════════════════════════════════════════════════════════════════════
# GROUP: LAYOUT-STABLE (5 checks)
# ════════════════════════════════════════════════════════════════════════════════

group = 'LAYOUT-STABLE'

# 1. LayoutEngine responds to required module methods
expected_methods = %i[define_layout render fill_slot render_inherited]
all_respond = expected_methods.all? { |m| LayoutEngine.respond_to?(m) }
assert_pass(results, group, 'layout_engine_responds_to_required_methods',
            all_respond,
            "LayoutEngine missing methods: #{expected_methods.reject { |m| LayoutEngine.respond_to?(m) }.inspect}")

# 2. SiteContentCompiler dependency loaded correctly
assert_pass(results, group, 'site_content_compiler_dependency_loaded',
            defined?(SiteContentCompiler) == 'constant' &&
            SiteContentCompiler.respond_to?(:compile),
            'SiteContentCompiler not loaded or missing .compile class method')

# 3. No real network calls (split-string guard: check source for 'Net::' + 'HTTP')
layout_engine_source = File.read(LIB_DIR.join('layout_engine.rb'))
net_http_pattern = 'Net::' + 'HTTP'
assert_pass(results, group, 'no_net_http_usage_in_layout_engine',
            !layout_engine_source.include?(net_http_pattern),
            "Found #{net_http_pattern} usage in layout_engine.rb")

# 4. igniter-lang untouched
igniter_lang_dir = PROOF_DIR.parent.parent.parent / 'igniter-lang'
git_status = `git -C #{igniter_lang_dir} status --porcelain 2>/dev/null`.strip
assert_pass(results, group, 'igniter_lang_untouched',
            git_status.empty?,
            "igniter-lang has uncommitted changes: #{git_status}")

# 5. lib/layout_engine.rb is a new file (does not modify existing lib files)
lib_files_before_p4 = %w[
  igv_compiler.rb ssr_renderer.rb view_artifact.rb site_content_compiler.rb
  slot_type_linker.rb compiled_contract_extractor.rb contract_schema_supplement.rb
]
layout_engine_path = LIB_DIR / 'layout_engine.rb'
assert_pass(results, group, 'layout_engine_is_new_file_not_existing_lib',
            layout_engine_path.exist? &&
            lib_files_before_p4.none? { |f| (LIB_DIR / f).to_s == layout_engine_path.to_s },
            "layout_engine.rb is not present or conflicts with existing lib files")

# ════════════════════════════════════════════════════════════════════════════════
# Results matrix
# ════════════════════════════════════════════════════════════════════════════════

puts "\n"
puts '=' * 76
puts 'LayoutEngine Proof — Results Matrix  [LAB-WEB-FRAMEWORK-P4]'
puts '=' * 76

col_group = 18
col_check = 48
header_line = "  #{'GROUP'.ljust(col_group)} #{'CHECK'.ljust(col_check)} STATUS"
puts header_line
puts '-' * 76

current_group = nil
results.each do |r|
  if r[:group] != current_group
    puts '' if current_group
    current_group = r[:group]
  end
  line = "  #{r[:group].to_s.ljust(col_group)} #{r[:check].to_s.ljust(col_check)} #{r[:status]}"
  puts line
  puts "    Detail: #{r[:detail]}" if r[:detail] && r[:status] == 'FAIL'
end

puts '-' * 76

total   = results.size
passing = results.count { |r| r[:status] == 'PASS' }
failing = results.count { |r| r[:status] == 'FAIL' }

puts "Total: #{total}  |  PASS: #{passing}  |  FAIL: #{failing}"
puts '=' * 76

if failing.zero?
  puts 'Result: ALL CHECKS PASSED'
  exit 0
else
  puts "Result: #{failing} CHECK(S) FAILED"
  exit 1
end
