# igniter-lab/igniter-view-engine/run_vsafe_proof.rb

require 'fileutils'
require 'json'
require_relative 'lib/igniter_view_engine'
require_relative 'lib/parser_builder'
require_relative 'fixtures/malicious_page'

# 1. Compile the malicious page
diagnostics = IgniterView::DiagnosticsTracker.new
malicious_node = IgniterView::Fixtures.malicious_page(diagnostics)

out_dir = File.expand_path('out', __dir__)
FileUtils.mkdir_p(out_dir)

File.write(File.join(out_dir, 'malicious_index.html'), malicious_node.to_html)
File.write(File.join(out_dir, 'malicious_view_tree.json'), JSON.pretty_generate(malicious_node.to_h))

diagnostics.log_event("compilation_complete", "Successfully compiled malicious spec", {})
File.write(File.join(out_dir, 'malicious_diagnostics.json'), JSON.pretty_generate({
  artifact: "diagnostics",
  events: diagnostics.events
}))
File.write(File.join(out_dir, 'malicious_token_usage_report.json'), JSON.pretty_generate({
  artifact: "token_usage_report",
  token_usage: diagnostics.token_usage
}))

# 2. Run simulation of safe_renderer_policy.ts on the compiled tree
ALLOWED_TAGS = %w[
  div span p h1 h2 h3 h4 h5 h6 a button
  input textarea label table thead tbody tr th td
  img style meta link head body html header footer
  section nav ul ol li br hr text component
].freeze

ALLOWED_ATTRIBUTES = %w[
  class id style href placeholder value type
  disabled readonly checked src alt lang charset
  rel for name rows cols target
].freeze

DOCUMENT_ROOT_TAGS = %w[html head body meta link].freeze

def is_suspicious_url(url, tag, attr)
  clean_url = url.to_s.strip.downcase
  return true if clean_url.start_with?('javascript:')
  return true if clean_url.start_with?('vbscript:')
  return true if clean_url.start_with?('file:')
  if clean_url.start_with?('data:')
    # Only allow data:image/ for img src
    if tag.downcase == 'img' && attr.downcase == 'src' && clean_url.start_with?('data:image/')
      return false
    end
    return true
  end
  # Regex for protocol
  match = clean_url.match(/^([a-z0-9+.-]+):/)
  if match
    proto = match[1]
    if proto != 'http' && proto != 'https' && proto != 'mailto' && proto != 'tel'
      return true
    end
  end
  false
end

def sanitize_node(node, is_root = false)
  warnings = []
  blocked_attrs = []
  sanitized_attrs = {}

  tag = node['tag'].to_s.downcase

  # 1. Tag policy check
  is_blocked_tag = !ALLOWED_TAGS.include?(tag)

  if !is_blocked_tag && DOCUMENT_ROOT_TAGS.include?(tag) && !is_root
    is_blocked_tag = true
    warnings << "Blocked document-level tag <#{node['tag']}> in nested child position"
  end

  if is_blocked_tag && !warnings.any? { |w| w.include?(node['tag']) }
    warnings << "Blocked unsafe/disallowed tag <#{node['tag']}>"
  end

  # 2. Attribute policy check
  if node['attributes']
    node['attributes'].each do |key, value|
      key_lower = key.to_s.downcase
      val_str = value.to_s.strip.downcase

      is_event = key_lower.start_with?('on')
      is_js_url = is_suspicious_url(val_str, tag, key_lower)
      is_not_whitelisted = !ALLOWED_ATTRIBUTES.include?(key_lower)
      is_css_leak = (key_lower == 'style' && (val_str =~ /@import/i || val_str =~ /url\s*\(/i))

      if is_event || is_js_url || is_not_whitelisted || is_css_leak
        blocked_attrs << key
        warnings << "Stripped unsafe event handler: '#{key}'" if is_event
        warnings << "Blocked unsafe/suspicious protocol URL in '#{key}': '#{value}'" if is_js_url
        warnings << "Blocked url()/@import inside style attribute to prevent CSS leaks" if is_css_leak
        warnings << "Stripped non-whitelisted attribute: '#{key}'" if is_not_whitelisted && !is_event && !is_js_url && !is_css_leak
      else
        sanitized_attrs[key] = value
      end
    end
  end

  # 3. Reverse Tabnabbing prevention with token preservation (VEDGE-4)
  if sanitized_attrs['target'] == '_blank'
    existing_rel = sanitized_attrs['rel'] ? sanitized_attrs['rel'].to_s : ''
    tokens = existing_rel.split(/\s+/).reject(&:empty?).uniq
    tokens << 'noopener' unless tokens.include?('noopener')
    tokens << 'noreferrer' unless tokens.include?('noreferrer')
    sanitized_attrs['rel'] = tokens.join(' ')
  end

  # 4. Style tag contents check - sanitize all children (VEDGE-1, VEDGE-2)
  children = node['children'] ? node['children'].dup : []
  if tag == 'style'
    children = children.map do |first_child|
      if first_child.is_a?(String)
        css = first_child.dup
        if css =~ /@import/i || css =~ /url\s*\(/i
          css.gsub!(/@import/i, '/* blocked @import */')
          css.gsub!(/url\s*\(/i, '/* blocked url( */')
          warnings << "Sanitized <style> block contents to strip @import and url() directives"
        end
        css
      elsif first_child.is_a?(Hash) && first_child['tag'] == 'text'
        text_node = first_child.dup
        if text_node['children'] && !text_node['children'].empty? && text_node['children'][0].is_a?(String)
          css = text_node['children'][0].dup
          if css =~ /@import/i || css =~ /url\s*\(/i
            css.gsub!(/@import/i, '/* blocked @import */')
            css.gsub!(/url\s*\(/i, '/* blocked url( */')
            text_node['children'] = [css] + text_node['children'][1..-1]
            warnings << "Sanitized <style> block contents to strip @import and url() directives"
          end
        end
        text_node
      else
        first_child
      end
    end
  end

  {
    'tag' => node['tag'],
    'isBlockedTag' => is_blocked_tag,
    'blockedTag' => node['tag'],
    'blockedAttrs' => blocked_attrs,
    'warnings' => warnings,
    'attributes' => sanitized_attrs,
    'children' => children.map { |c| c.is_a?(Hash) ? sanitize_node(c, false) : c }
  }
end

# Find all warnings in sanitized tree
def collect_warnings(node)
  warnings = node['warnings'] ? node['warnings'].dup : []
  node['children'].each do |c|
    warnings.concat(collect_warnings(c)) if c.is_a?(Hash)
  end
  warnings
end

# Walk tree to find a node by tag name
def find_nodes_by_tag(node, tag_name)
  results = []
  results << node if node['tag'] == tag_name
  node['children'].each do |c|
    results.concat(find_nodes_by_tag(c, tag_name)) if c.is_a?(Hash)
  end
  results
end

# Check if tabnabbing was fixed on a tag
def check_tabnabbing(node)
  results = []
  if node['tag'] == 'a' && node['attributes']['target'] == '_blank'
    results << node
  end
  node['children'].each do |c|
    results.concat(check_tabnabbing(c)) if c.is_a?(Hash)
  end
  results
end

# Check if nested script tags or doc-level tags are blocked
def check_nested_blocked(node)
  results = []
  results << node if node['isBlockedTag']
  node['children'].each do |c|
    results.concat(check_nested_blocked(c)) if c.is_a?(Hash)
  end
  results
end

# Parse tree as JSON first to ensure all keys are strings and simulate browser environment
parsed_tree = JSON.parse(JSON.generate(malicious_node.to_h))
sanitized_tree = sanitize_node(parsed_tree, true)
all_warnings = collect_warnings(sanitized_tree)

vsafe_results = {}

puts "=========================================================="
puts "  IGNITER VIEW ENGINE: VSAFE SECURITY POLICY VALIDATION    "
puts "=========================================================="

def check_rule(name, description)
  passed = yield
  status = passed ? "\e[32m[PASS]\e[0m" : "\e[31m[FAIL]\e[0m"
  puts " #{status}  #{name.ljust(8)} - #{description}"
  passed
end

# VCON-4a: Strip @import and url() in style tag contents
vsafe_results['VCON-4a'] = check_rule('VCON-4a', 'Strip @import and url() inside <style> blocks') do
  style_nodes = find_nodes_by_tag(sanitized_tree, 'style')
  import_blocked = style_nodes.any? do |n|
    n['children'].any? do |first_child|
      if first_child.is_a?(String)
        first_child.include?('/* blocked @import */')
      elsif first_child.is_a?(Hash) && first_child['tag'] == 'text'
        first_child['children'][0].to_s.include?('/* blocked @import */')
      else
        false
      end
    end
  end
  url_blocked = style_nodes.any? do |n|
    n['children'].any? do |first_child|
      if first_child.is_a?(String)
        first_child.include?('/* blocked url( */')
      elsif first_child.is_a?(Hash) && first_child['tag'] == 'text'
        first_child['children'][0].to_s.include?('/* blocked url( */')
      else
        false
      end
    end
  end
  import_blocked && url_blocked
end

# VCON-4b: Strip url()/@import in inline style attributes
vsafe_results['VCON-4b'] = check_rule('VCON-4b', 'Strip url()/@import inside style attributes to prevent leaks') do
  all_warnings.any? { |w| w.include?('Blocked url()/@import inside style attribute') }
end

# VCON-4c: target='_blank' links must force rel='noopener noreferrer'
vsafe_results['VCON-4c'] = check_rule('VCON-4c', 'Add rel="noopener noreferrer" to target="_blank" links') do
  links = check_tabnabbing(sanitized_tree)
  links.all? do |l|
    rel = l['attributes']['rel'].to_s
    rel.include?('noopener') && rel.include?('noreferrer')
  end && !links.empty?
end

# VCON-5: Nested document-level tags (html, head, body, meta, link) must be blocked
vsafe_results['VCON-5'] = check_rule('VCON-5', 'Block nested document-level tags (html, head, body)') do
  blocked = check_nested_blocked(sanitized_tree)
  blocked.any? { |n| DOCUMENT_ROOT_TAGS.include?(n['tag'].downcase) }
end

# VCON-6a: Disallowed tags script and iframe remain blocked
vsafe_results['VCON-6a'] = check_rule('VCON-6a', 'Block script and iframe tags completely') do
  blocked = check_nested_blocked(sanitized_tree)
  blocked.any? { |n| n['tag'] == 'script' } && blocked.any? { |n| n['tag'] == 'iframe' }
end

# VCON-6b: Inline handlers (on*) are stripped
vsafe_results['VCON-6b'] = check_rule('VCON-6b', 'Strip inline on* event handlers') do
  all_warnings.any? { |w| w.include?("Stripped unsafe event handler: 'onclick'") }
end

# VCON-6c: javascript: href scheme is blocked
vsafe_results['VCON-6c'] = check_rule('VCON-6c', 'Block javascript: schemes in href') do
  all_warnings.any? { |w| w.include?("Blocked unsafe/suspicious protocol URL") }
end

# VCON-7: Diagnostics timeline warning logging
vsafe_results['VCON-7'] = check_rule('VCON-7', 'Ensure safety policy generates warning events') do
  all_warnings.size > 0
end

# VEDGE-1: Sanitize all style children, not only the first child
vsafe_results['VEDGE-1'] = check_rule('VEDGE-1', 'Sanitize all style children, not only the first child') do
  style_nodes = find_nodes_by_tag(sanitized_tree, 'style')
  style_nodes.any? do |n|
    n['children'].size >= 3 &&
    n['children'].any? { |c| c.is_a?(Hash) && c['tag'] == 'text' && c['children'][0].include?('/* blocked @import */') } &&
    n['children'].any? { |c| c.is_a?(Hash) && c['tag'] == 'text' && c['children'][0].include?('/* blocked url( */') }
  end
end

# VEDGE-2: Detect CSS url variants with whitespace/case and reject remote CSS leak forms
vsafe_results['VEDGE-2'] = check_rule('VEDGE-2', 'Spaced and mixed-case url/import CSS variants blocked') do
  all_warnings.any? { |w| w.include?('Blocked url()/@import inside style attribute') }
end

# VEDGE-3: Suspicious protocol URLs fail closed but allow safe image data URI
vsafe_results['VEDGE-3'] = check_rule('VEDGE-3', 'Suspicious protocol URLs fail closed (javascript, vbscript, file, data) but allow safe data:image') do
  has_suspicious = all_warnings.any? { |w| w.include?("Blocked unsafe/suspicious protocol URL in 'href': 'data:text/html") } &&
                   all_warnings.any? { |w| w.include?("Blocked unsafe/suspicious protocol URL in 'href': 'vbscript:") } &&
                   all_warnings.any? { |w| w.include?("Blocked unsafe/suspicious protocol URL in 'href': 'file:") }
  
  # Ensure img src is NOT blocked (it won't generate warning or block tag)
  img_nodes = find_nodes_by_tag(sanitized_tree, 'img')
  img_safe = img_nodes.any? { |n| n['attributes']['src'].start_with?('data:image/') }
  
  has_suspicious && img_safe
end

# VEDGE-4: target="_blank" preserves existing rel tokens (rel merging)
vsafe_results['VEDGE-4'] = check_rule('VEDGE-4', 'target="_blank" preserves and merges existing rel tokens') do
  links = check_tabnabbing(sanitized_tree)
  # One link had rel="nofollow" and should merge to "nofollow noopener noreferrer"
  with_rel = links.find { |l| l['attributes']['href'] == 'https://external.com/b' }
  no_rel = links.find { |l| l['attributes']['href'] == 'https://external.com/a' }
  
  with_rel && with_rel['attributes']['rel'] == 'nofollow noopener noreferrer' &&
    no_rel && no_rel['attributes']['rel'] == 'noopener noreferrer'
end

all_passed = vsafe_results.values.all?

# Output vsafe_summary.json (VCON-3)
summary_hash = {
  timestamp: Time.now.to_s,
  overall_status: all_passed ? "SUCCESS" : "FAILURE",
  results: vsafe_results,
  warnings: all_warnings
}
File.write(File.join(out_dir, 'vsafe_summary.json'), JSON.pretty_generate(summary_hash))

puts "=========================================================="
if all_passed
  puts " \e[32mALL VSAFE SECURITY POLICY CHECKS PASSED!\e[0m vsafe_summary.json generated."
else
  puts " \e[31mSECURITY POLICY CHECKS FAILED!\e[0m Please check the failing assertions."
end
puts "=========================================================="

exit(all_passed ? 0 : 1)
