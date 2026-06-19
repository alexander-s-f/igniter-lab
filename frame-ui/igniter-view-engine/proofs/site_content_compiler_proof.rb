# frozen_string_literal: true
# Proof: SiteContentCompiler
# Card: LAB-WEB-FRAMEWORK-P3
# Surface: lab-only · proof-local · no canon claim · no stable API
#
# Compiles each fixture markdown in fixtures/site_content_compiler/,
# writes output HTML to fixtures/site_content_compiler/output/,
# and asserts structural and safety properties on each compiled page.

require 'pathname'

PROOF_DIR     = Pathname.new(__FILE__).dirname
LIB_DIR       = PROOF_DIR.parent / 'lib'
FIXTURE_DIR   = PROOF_DIR.parent / 'fixtures' / 'site_content_compiler'
OUTPUT_DIR    = FIXTURE_DIR / 'output'
ARTIFACT_PATH = PROOF_DIR.parent / 'fixtures' / 'siteartifact_url_contract' / 'igniter_org_v0.json'

$LOAD_PATH.unshift(LIB_DIR.to_s)
require 'site_content_compiler'

OUTPUT_DIR.mkpath

# ── Result tracking ────────────────────────────────────────────────────────

results = []

def pass(results, fixture, check)
  results << { status: 'PASS', fixture: fixture, check: check }
  print '.'
end

def fail_check(results, fixture, check, detail = nil)
  results << { status: 'FAIL', fixture: fixture, check: check, detail: detail }
  print 'F'
end

def assert_pass(results, fixture, check, value, detail = nil)
  if value
    pass(results, fixture, check)
  else
    fail_check(results, fixture, check, detail || "assertion failed")
  end
end

# ── Instantiate compiler ───────────────────────────────────────────────────

compiler = SiteContentCompiler.new(ARTIFACT_PATH.to_s)

# ── Universal checks for any compiled fixture ──────────────────────────────

def universal_checks(results, compiler, fixture_path, fixture_name, expected_canonical)
  result = compiler.compile_file(fixture_path.to_s)
  html   = result[:html]

  assert_pass(results, fixture_name, 'html_has_doctype',
              html.start_with?('<!DOCTYPE html>'),
              "Output does not start with <!DOCTYPE html>")

  assert_pass(results, fixture_name, 'html_has_canonical',
              html.include?('<link rel="canonical" href="'),
              "No canonical link tag found")

  assert_pass(results, fixture_name, 'html_has_lang_attribute',
              html.include?('<html lang="'),
              "No lang attribute on <html>")

  assert_pass(results, fixture_name, 'html_has_title',
              html.match?(/<title>[^<]+<\/title>/),
              "No non-empty <title> found")

  assert_pass(results, fixture_name, 'html_has_body_content',
              html.match?(/<body>[\s\S]+<\/body>/),
              "Body appears empty")

  assert_pass(results, fixture_name, 'no_absolute_local_paths',
              !html.include?('/Users/') && !html.include?('/home/'),
              "Found absolute local path in output")

  assert_pass(results, fixture_name, 'no_file_uri',
              !html.include?('file://'),
              "Found file:// URI in output")

  assert_pass(results, fixture_name, 'no_javascript_scheme',
              !html.match?(/href\s*=\s*["']?javascript:/i),
              "Found javascript: scheme in output")

  canonical_match = html.match(/<link rel="canonical" href="([^"]+)"/)
  actual_canonical = canonical_match ? canonical_match[1] : ''
  assert_pass(results, fixture_name, 'canonical_matches_fixture',
              actual_canonical == expected_canonical,
              "Expected canonical #{expected_canonical.inspect}, got #{actual_canonical.inspect}")

  html
rescue => e
  fail_check(results, fixture_name, 'compile_did_not_raise', e.message)
  nil
end

# ── en_language_index.md ──────────────────────────────────────────────────

fixture_path = FIXTURE_DIR / 'en_language_index.md'
html = universal_checks(results, compiler, fixture_path, 'en_language_index.md', '/language/')

if html
  output_path = OUTPUT_DIR / 'en_language_index.html'
  output_path.write(html, encoding: 'UTF-8')

  assert_pass(results, 'en_language_index.md', 'has_hreflang_en',
              html.include?('hreflang="en"'),
              "Missing hreflang=en")

  assert_pass(results, 'en_language_index.md', 'has_hreflang_ru',
              html.include?('hreflang="ru"'),
              "Missing hreflang=ru")

  assert_pass(results, 'en_language_index.md', 'has_hreflang_uk',
              html.include?('hreflang="uk"'),
              "Missing hreflang=uk")

  assert_pass(results, 'en_language_index.md', 'has_hreflang_x_default',
              html.include?('hreflang="x-default"'),
              "Missing hreflang=x-default")
end

# ── ru_language_index.md ──────────────────────────────────────────────────

fixture_path = FIXTURE_DIR / 'ru_language_index.md'
html = universal_checks(results, compiler, fixture_path, 'ru_language_index.md', '/ru/language/')

if html
  output_path = OUTPUT_DIR / 'ru_language_index.html'
  output_path.write(html, encoding: 'UTF-8')

  assert_pass(results, 'ru_language_index.md', 'has_lang_ru',
              html.include?('<html lang="ru"'),
              "html element does not have lang=ru")

  hreflang_count = html.scan(/rel="alternate" hreflang=/).length
  assert_pass(results, 'ru_language_index.md', 'has_hreflang_entries',
              hreflang_count >= 2,
              "Expected at least 2 hreflang entries, found #{hreflang_count}")

  canonical_match = html.match(/<link rel="canonical" href="([^"]+)"/)
  actual_canonical = canonical_match ? canonical_match[1] : ''
  assert_pass(results, 'ru_language_index.md', 'canonical_is_ru_path',
              actual_canonical == '/ru/language/',
              "Expected canonical /ru/language/, got #{actual_canonical.inspect}")
end

# ── en_tutorial_intro.md ──────────────────────────────────────────────────

fixture_path = FIXTURE_DIR / 'en_tutorial_intro.md'
html = universal_checks(results, compiler, fixture_path, 'en_tutorial_intro.md', '/tutorial/compiler-first-proof/')

if html
  output_path = OUTPUT_DIR / 'en_tutorial_intro.html'
  output_path.write(html, encoding: 'UTF-8')

  assert_pass(results, 'en_tutorial_intro.md', 'has_code_block',
              html.include?('<pre><code'),
              "No <pre><code> found in body")

  # Verify code blocks do not contain raw < or > characters (must be &lt; / &gt;)
  raw_angle_in_code = html.scan(/<pre><code[^>]*>(.*?)<\/code><\/pre>/m).any? do |captures|
    captures.first.to_s.match?(/(?<!&lt|&gt|&amp|&quot)[<>]/)
  end
  assert_pass(results, 'en_tutorial_intro.md', 'code_is_escaped',
              !raw_angle_in_code,
              "Code block contains raw < or > characters (should be escaped)")

  assert_pass(results, 'en_tutorial_intro.md', 'has_heading',
              html.match?(/<h[12]>/),
              "No h1 or h2 found in output")
end

# ── en_status.md ──────────────────────────────────────────────────────────

fixture_path = FIXTURE_DIR / 'en_status.md'
html = universal_checks(results, compiler, fixture_path, 'en_status.md', '/status/')

if html
  output_path = OUTPUT_DIR / 'en_status.html'
  output_path.write(html, encoding: 'UTF-8')

  assert_pass(results, 'en_status.md', 'has_table',
              html.include?('<table>'),
              "No <table> found in body")
end

# ── en_fallback_only.md ───────────────────────────────────────────────────

fixture_path = FIXTURE_DIR / 'en_fallback_only.md'
html = universal_checks(results, compiler, fixture_path, 'en_fallback_only.md', '/lab/design-system/')

if html
  output_path = OUTPUT_DIR / 'en_fallback_only.html'
  output_path.write(html, encoding: 'UTF-8')

  assert_pass(results, 'en_fallback_only.md', 'no_fallback_banner',
              !html.include?('iglab-fallback-banner'),
              "Fallback banner shown but should not be — locale is en and fallback_locale is en")
end

# ── Safety rejection tests ────────────────────────────────────────────────

# javascript: link should raise SiteCompilerSafetyError
js_fixture = <<~MD
  ---
  page_id: test-js-link
  locale: en
  title: "Test"
  slug: test
  canonical_path: /status/
  fallback_locale: ~
  ---

  [Click me](javascript:alert(1))
MD

raised_js = false
begin
  compiler.compile_page(js_fixture)
rescue SiteCompilerSafetyError
  raised_js = true
rescue => e
  # unexpected error — still mark as fail
end
assert_pass(results, 'safety_rejection', 'javascript_link_raises_safety_error',
            raised_js,
            "Expected SiteCompilerSafetyError for javascript: link, but no error was raised")

# file:// link should raise SiteCompilerSafetyError
file_fixture = <<~MD
  ---
  page_id: test-file-link
  locale: en
  title: "Test"
  slug: test
  canonical_path: /status/
  fallback_locale: ~
  ---

  [Local file](file:///etc/passwd)
MD

raised_file = false
begin
  compiler.compile_page(file_fixture)
rescue SiteCompilerSafetyError
  raised_file = true
rescue => e
  # unexpected error — still mark as fail
end
assert_pass(results, 'safety_rejection', 'file_uri_link_raises_safety_error',
            raised_file,
            "Expected SiteCompilerSafetyError for file:// link, but no error was raised")

# ── Print results matrix ───────────────────────────────────────────────────

puts "\n"
puts '=' * 72
puts 'SiteContentCompiler Proof — Results Matrix'
puts '=' * 72

col_fixture = 26
col_check   = 38
header = "  #{('FIXTURE').ljust(col_fixture)} #{('CHECK').ljust(col_check)} STATUS"
puts header
puts '-' * 72

current_fixture = nil
results.each do |r|
  if r[:fixture] != current_fixture
    puts '' if current_fixture
    current_fixture = r[:fixture]
  end
  status_str = r[:status]
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
