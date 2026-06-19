# frozen_string_literal: true
# Proof: SiteArtifact URL Contract
# Card: LAB-WEB-FRAMEWORK-P2 / Hardening: LAB-WEB-FRAMEWORK-P2-A
# Surface: lab-only, proof-local evidence only.
# No canon claim, no public API, no stable schema.

require 'json'
require 'pathname'

FIXTURE_DIR = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'siteartifact_url_contract'

PASS_FIXTURES = %w[igniter_org_v0.json valid_minimal.json].freeze
FAIL_FIXTURE   = 'invalid_forbidden_routes.json'

FORBIDDEN_PATTERNS = [
  %r{\A/docs/i18n/},
  %r{\A/docs/tutorial/en/},
  %r{\A/content/},
  %r{\A/_site/}
].freeze

REQUIRED_ROUTES_IGNITER_ORG = %w[
  /
  /en/
  /ru/
  /uk/
  /language/
  /ru/language/
  /uk/language/
  /tutorial/
  /ru/tutorial/
  /uk/tutorial/
  /tutorial/lab-orientation/
  /tutorial/compiler-first-proof/
  /ru/tutorial/lab-orientation/
  /uk/tutorial/lab-orientation/
  /lab/
  /lab/compiler/
  /lab/vm/
  /lab/ide/
  /lab/view/
  /lab/gui/
  /status/
].freeze

# Routes derived from Jekyll route-contract evidence (read-only pressure source).
# This list is used by check jekyll_contract_route_families_present.
# It documents what the Jekyll candidate has proven must be covered.
JEKYLL_CONTRACT_ROUTES = [
  "/",
  "/en/",
  "/ru/",
  "/uk/",
  "/language/",
  "/ru/language/",
  "/uk/language/",
  "/language/covenant/",
  "/language/specification/",
  "/language/proposals/",
  "/tutorial/",
  "/ru/tutorial/",
  "/uk/tutorial/",
  "/lab/",
  "/lab/compiler/",
  "/lab/vm/",
  "/lab/ide/",
  "/lab/view/",
  "/lab/gui/",
  "/lab/design-system/",
  "/status/"
].freeze

# ── helpers ──────────────────────────────────────────────────────────────────

def all_strings_recursive(value, path = '')
  results = []
  case value
  when String
    results << [path, value]
  when Array
    value.each_with_index { |v, i| results.concat(all_strings_recursive(v, "#{path}[#{i}]")) }
  when Hash
    value.each { |k, v| results.concat(all_strings_recursive(v, "#{path}.#{k}")) }
  end
  results
end

def collect_all_paths(route_node)
  paths = []
  return paths unless route_node.is_a?(Hash)
  paths << route_node['path'] if route_node['path']
  (route_node['children'] || []).each { |c| paths.concat(collect_all_paths(c)) }
  paths
end

def forbidden_path?(path)
  FORBIDDEN_PATTERNS.any? { |pat| pat.match?(path) }
end

# ── result tracking ───────────────────────────────────────────────────────────

results = []

def pass(results, label, fixture)
  results << { status: 'PASS', fixture: fixture, check: label }
  print '.'
end

def fail_check(results, label, fixture, detail = nil)
  results << { status: 'FAIL', fixture: fixture, check: label, detail: detail }
  print 'F'
end

# ═══════════════════════════════════════════════════════════════════════════════
# PASS-fixture checks
# ═══════════════════════════════════════════════════════════════════════════════

PASS_FIXTURES.each do |fname|
  fpath = FIXTURE_DIR / fname
  unless fpath.exist?
    results << { status: 'FAIL', fixture: fname, check: 'fixture_exists', detail: "File not found: #{fpath.basename}" }
    next
  end

  data = JSON.parse(fpath.read(encoding: 'UTF-8'))
  pages = data['pages'] || []
  locale_equivalents = data['locale_equivalents'] || {}
  canonical_policy = data['canonical_url_policy'] || {}
  hreflang_policy = data['hreflang_policy'] || {}
  output_policy = data['generated_output_policy'] || {}
  source_refs = data['source_content_refs'] || {}
  route_tree = data['route_tree']
  all_route_paths = collect_all_paths(route_tree)
  all_strings = all_strings_recursive(data)

  # ── 1. Required routes exist (only for igniter_org_v0) ────────────────────
  if fname == 'igniter_org_v0.json'
    missing = REQUIRED_ROUTES_IGNITER_ORG.reject { |r| all_route_paths.include?(r) }
    if missing.empty?
      pass(results, 'required_routes_present', fname)
    else
      fail_check(results, 'required_routes_present', fname, "Missing routes: #{missing.join(', ')}")
    end
  else
    pass(results, 'required_routes_present', fname) # not applicable to minimal
  end

  # ── 2. No forbidden routes in route tree ──────────────────────────────────
  forbidden_found = all_route_paths.select { |p| forbidden_path?(p) }
  if forbidden_found.empty?
    pass(results, 'no_forbidden_routes_in_route_tree', fname)
  else
    fail_check(results, 'no_forbidden_routes_in_route_tree', fname, "Forbidden routes: #{forbidden_found.join(', ')}")
  end

  # ── 3. Locale equivalents are distinct per locale ─────────────────────────
  same_path_violations = []
  locale_equivalents.each do |canonical_key, equiv_map|
    next unless equiv_map.is_a?(Hash) && equiv_map.size > 1
    paths = equiv_map.values
    if paths.uniq.size == 1
      same_path_violations << "#{canonical_key}: all locales point to #{paths.first}"
    end
  end
  if same_path_violations.empty?
    pass(results, 'locale_equivalents_are_distinct', fname)
  else
    fail_check(results, 'locale_equivalents_are_distinct', fname, same_path_violations.join('; '))
  end

  # ── 4. No locale equivalents use forbidden path shapes ────────────────────
  forbidden_equiv = []
  locale_equivalents.each do |canonical_key, equiv_map|
    next unless equiv_map.is_a?(Hash)
    equiv_map.each_value do |p|
      forbidden_equiv << p if forbidden_path?(p.to_s)
    end
  end
  if forbidden_equiv.empty?
    pass(results, 'locale_equivalents_no_forbidden_paths', fname)
  else
    fail_check(results, 'locale_equivalents_no_forbidden_paths', fname, "Forbidden equiv paths: #{forbidden_equiv.join(', ')}")
  end

  # ── 5. Canonical path selected correctly ─────────────────────────────────
  # Rule: translated pages have canonical = self; fallback (only en) pages
  # have fallback_locale set. Verify no en-only page lacks fallback_locale.
  bad_fallback = []
  pages.each do |page|
    locales = page['locales'] || []
    fallback = page['fallback_locale']
    all_locales = data['locales'] || []
    if locales.length == 1 && locales.first == (data['default_locale'] || 'en') && all_locales.length > 1
      bad_fallback << page['id'] if fallback.nil?
    end
  end
  if bad_fallback.empty?
    pass(results, 'fallback_locale_set_for_en_only_pages', fname)
  else
    fail_check(results, 'fallback_locale_set_for_en_only_pages', fname, "Pages missing fallback_locale: #{bad_fallback.join(', ')}")
  end

  # ── 6. hreflang entries complete where equivalents exist ─────────────────
  bad_hreflang = []
  pages.each do |page|
    hreflang = page['hreflang'] || {}
    page_locales = page['locales'] || []
    page_locales.each do |loc|
      bad_hreflang << "#{page['id']}:#{loc}" unless hreflang.key?(loc)
    end
    # x-default must always be present
    bad_hreflang << "#{page['id']}:x-default" unless hreflang.key?('x-default')
  end
  if bad_hreflang.empty?
    pass(results, 'hreflang_entries_complete', fname)
  else
    fail_check(results, 'hreflang_entries_complete', fname, "Missing hreflang keys: #{bad_hreflang.join(', ')}")
  end

  # ── 7. Generated output paths separate from source paths ─────────────────
  output_root = output_policy['output_root'] || ''
  source_overlap = source_refs.values.select { |sr| sr.to_s.start_with?(output_root) && !output_root.empty? }
  if source_overlap.empty?
    pass(results, 'output_paths_separate_from_source', fname)
  else
    fail_check(results, 'output_paths_separate_from_source', fname, "Overlap: #{source_overlap.join(', ')}")
  end

  # ── 8. No absolute local paths in any string value ───────────────────────
  abs_path_strings = all_strings.select { |_, v| v.match?(%r{\A/Users/|/home/|/root/|[A-Z]:\\}) }
  if abs_path_strings.empty?
    pass(results, 'no_absolute_local_paths', fname)
  else
    fail_check(results, 'no_absolute_local_paths', fname, "Found: #{abs_path_strings.map { |p, v| "#{p}=#{v[0..40]}" }.join(', ')}")
  end

  # ── 9. No file:// URIs ───────────────────────────────────────────────────
  file_uri_strings = all_strings.select { |_, v| v.include?('file://') }
  if file_uri_strings.empty?
    pass(results, 'no_file_uri', fname)
  else
    fail_check(results, 'no_file_uri', fname, "Found file:// in: #{file_uri_strings.map { |p, _| p }.join(', ')}")
  end

  # ── 10. No javascript: scheme ───────────────────────────────────────────
  js_strings = all_strings.select { |_, v| v.match?(/\Ajavascript:/i) }
  if js_strings.empty?
    pass(results, 'no_javascript_scheme', fname)
  else
    fail_check(results, 'no_javascript_scheme', fname, "Found javascript: in: #{js_strings.map { |p, _| p }.join(', ')}")
  end

  # ── NEW HARDENING CHECKS (LAB-WEB-FRAMEWORK-P2-A) ────────────────────────

  # ── 11. Jekyll contract route families present (igniter_org_v0 only) ─────
  # Verifies that the fixture covers all route families documented in the
  # Jekyll candidate's route-contract.md (read-only evidence).
  if fname == 'igniter_org_v0.json'
    missing_jekyll = JEKYLL_CONTRACT_ROUTES.reject { |r| all_route_paths.include?(r) }
    if missing_jekyll.empty?
      pass(results, 'jekyll_contract_route_families_present', fname)
    else
      fail_check(results, 'jekyll_contract_route_families_present', fname,
                 "Fixture missing Jekyll-contract routes: #{missing_jekyll.join(', ')}")
    end
  else
    pass(results, 'jekyll_contract_route_families_present', fname) # not applicable to minimal
  end

  # ── 12. Locale equivalent completeness for tri-locale pages ──────────────
  # For every page whose locales array contains all three of en/ru/uk,
  # the hreflang map must have en, ru, uk, and x-default keys, and
  # the locale_equivalents entry must have all three locale keys mapping
  # to distinct paths.
  site_locales = data['locales'] || []
  all_three = %w[en ru uk]
  completeness_errors = []
  if (site_locales & all_three).sort == all_three.sort
    pages.each do |page|
      page_locales = page['locales'] || []
      next unless (page_locales & all_three).sort == all_three.sort

      hreflang = page['hreflang'] || {}
      missing_hreflang_keys = (all_three + ['x-default']).reject { |k| hreflang.key?(k) }
      unless missing_hreflang_keys.empty?
        completeness_errors << "#{page['id']}: hreflang missing keys #{missing_hreflang_keys.join(', ')}"
      end

      canonical = page['canonical_path']
      # Look up by canonical_path key, or by finding an entry whose default-locale value matches
      default_locale = data['default_locale'] || 'en'
      equiv_entry = locale_equivalents[canonical] ||
                    locale_equivalents.values.find { |e| e.is_a?(Hash) && e[default_locale] == canonical }
      if equiv_entry.nil?
        completeness_errors << "#{page['id']}: no locale_equivalents entry for canonical #{canonical}"
      else
        missing_equiv_keys = all_three.reject { |k| equiv_entry.key?(k) }
        unless missing_equiv_keys.empty?
          completeness_errors << "#{page['id']}: locale_equivalents missing locales #{missing_equiv_keys.join(', ')}"
        end
        equiv_paths = all_three.map { |k| equiv_entry[k] }.compact
        if equiv_paths.uniq.size < equiv_paths.size
          completeness_errors << "#{page['id']}: locale_equivalents has duplicate paths"
        end
      end
    end
  end
  if completeness_errors.empty?
    pass(results, 'locale_equivalent_completeness', fname)
  else
    fail_check(results, 'locale_equivalent_completeness', fname, completeness_errors.first(3).join('; '))
  end

  # ── 13. Fallback pages have no hreflang for missing locales ──────────────
  # For every page where fallback_locale is set (en-only page in a multi-locale
  # site), the hreflang map must NOT contain keys for locales outside the
  # page's own locales array.
  fallback_hreflang_errors = []
  pages.each do |page|
    next if page['fallback_locale'].nil?

    page_locales = Set.new(page['locales'] || [])
    hreflang = page['hreflang'] || {}
    hreflang_locale_keys = hreflang.keys.reject { |k| k == 'x-default' }
    extra_keys = hreflang_locale_keys.reject { |k| page_locales.include?(k) }
    unless extra_keys.empty?
      fallback_hreflang_errors << "#{page['id']}: hreflang has extra locale keys #{extra_keys.join(', ')} not in page locales"
    end
  end
  if fallback_hreflang_errors.empty?
    pass(results, 'fallback_pages_have_no_hreflang_for_missing_locales', fname)
  else
    fail_check(results, 'fallback_pages_have_no_hreflang_for_missing_locales', fname, fallback_hreflang_errors.first(3).join('; '))
  end

  # ── 14. Tutorial slug routes localized ───────────────────────────────────
  # For every page with a slug that starts with "tutorial-" (but not the index),
  # if the page is active in ru and uk locales, verify that the corresponding
  # localized routes exist in the route_tree.
  tutorial_locale_errors = []
  pages.each do |page|
    slug = page['slug'] || ''
    page_locales = page['locales'] || []
    # Only check tutorial content pages (not the index slug "tutorial")
    next unless page['id'].to_s.start_with?('tutorial-') && slug != 'tutorial'

    if page_locales.include?('ru')
      expected_ru = "/ru/tutorial/#{slug}/"
      unless all_route_paths.include?(expected_ru)
        tutorial_locale_errors << "Missing route #{expected_ru} for page #{page['id']}"
      end
    end
    if page_locales.include?('uk')
      expected_uk = "/uk/tutorial/#{slug}/"
      unless all_route_paths.include?(expected_uk)
        tutorial_locale_errors << "Missing route #{expected_uk} for page #{page['id']}"
      end
    end
  end
  if tutorial_locale_errors.empty?
    pass(results, 'tutorial_slug_routes_localized', fname)
  else
    fail_check(results, 'tutorial_slug_routes_localized', fname, tutorial_locale_errors.first(3).join('; '))
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# FAIL-fixture checks (invalid_forbidden_routes.json)
# Every route in forbidden_routes must match at least one forbidden pattern.
# Every locale-equivalent set in forbidden_locale_equivalent_violations must be
# caught by at least one structural rule.
# ═══════════════════════════════════════════════════════════════════════════════

fpath = FIXTURE_DIR / FAIL_FIXTURE
unless fpath.exist?
  results << { status: 'FAIL', fixture: FAIL_FIXTURE, check: 'fixture_exists', detail: 'File not found' }
else
  data = JSON.parse(fpath.read(encoding: 'UTF-8'))
  forbidden_routes = data['forbidden_routes'] || []
  forbidden_equiv_violations = data['forbidden_locale_equivalent_violations'] || []

  # All forbidden_routes must match a forbidden pattern
  uncaught = forbidden_routes.reject { |r| forbidden_path?(r['path']) }
  if uncaught.empty?
    pass(results, 'all_forbidden_routes_rejected', FAIL_FIXTURE)
  else
    fail_check(results, 'all_forbidden_routes_rejected', FAIL_FIXTURE, "Uncaught: #{uncaught.map { |r| r['path'] }.join(', ')}")
  end

  # forbidden_locale_equivalent_violations: same-path rule catches case 0
  same_path_caught = forbidden_equiv_violations.count do |v|
    equiv = v['equivalents'] || {}
    paths = equiv.values
    paths.uniq.size == 1 || paths.any? { |p| forbidden_path?(p.to_s) }
  end
  if same_path_caught == forbidden_equiv_violations.size
    pass(results, 'all_forbidden_equiv_violations_caught', FAIL_FIXTURE)
  else
    fail_check(results, 'all_forbidden_equiv_violations_caught', FAIL_FIXTURE, "Only #{same_path_caught}/#{forbidden_equiv_violations.size} caught")
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Print matrix
# ═══════════════════════════════════════════════════════════════════════════════

puts "\n"
puts '=' * 72
puts 'SiteArtifact URL Contract Proof — Results Matrix'
puts '=' * 72

col_fixture = 34
col_check   = 44
col_status  = 6

header = "  #{('FIXTURE').ljust(col_fixture)} #{('CHECK').ljust(col_check)} STATUS"
puts header
puts '-' * 72

current_fixture = nil
results.each do |r|
  if r[:fixture] != current_fixture
    puts '' if current_fixture
    current_fixture = r[:fixture]
  end
  status_str = r[:status] == 'PASS' ? 'PASS' : 'FAIL'
  line = "  #{r[:fixture].to_s.ljust(col_fixture)} #{r[:check].to_s.ljust(col_check)} #{status_str}"
  puts line
  puts "    Detail: #{r[:detail]}" if r[:detail] && r[:status] == 'FAIL'
end

puts '-' * 72

total   = results.size
passing = results.count { |r| r[:status] == 'PASS' }
failing = results.count { |r| r[:status] == 'FAIL' }

puts "Total: #{total}  |  PASS: #{passing}  |  FAIL: #{failing}"
puts '=' * 72

if failing.zero?
  puts 'Result: ALL CHECKS PASSED'
  exit 0
else
  puts "Result: #{failing} CHECK(S) FAILED"
  exit 1
end
