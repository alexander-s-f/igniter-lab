# frozen_string_literal: true
# SiteContentCompiler — content-to-HTML compiler prototype
# Card: LAB-WEB-FRAMEWORK-P3
# Surface: lab-only · proof-local · no canon claim · no stable API
#
# Reads markdown with YAML frontmatter, looks up routing metadata from a
# SiteArtifact JSON fixture, and emits a safe HTML page with canonical and
# hreflang link tags.

require 'yaml'
require 'json'

class SiteCompilerSafetyError < StandardError; end

class SiteContentCompiler
  # ── Public API ─────────────────────────────────────────────────────────────

  def initialize(site_artifact_path)
    raw = File.read(site_artifact_path, encoding: 'UTF-8')
    @artifact = JSON.parse(raw)
    @pages = @artifact['pages'] || []
  end

  # Parse markdown_source (String), emit HTML.
  # Returns { html: String, page_id: String, locale: String, canonical_path: String }
  def compile_page(markdown_source)
    frontmatter, body_markdown = parse_frontmatter(markdown_source)

    page_id       = frontmatter['page_id'] || ''
    locale        = frontmatter['locale'] || 'en'
    title         = frontmatter['title'] || ''
    canonical_path = frontmatter['canonical_path'] || '/'
    fm_fallback   = frontmatter['fallback_locale']
    # normalize YAML null (~) to nil
    fm_fallback   = nil if fm_fallback == false || fm_fallback.to_s.strip == ''

    # Look up the page in the SiteArtifact
    artifact_page = find_artifact_page(canonical_path)

    # Resolve metadata from artifact (prefer artifact over frontmatter for routing data)
    resolved_hreflang  = artifact_page ? (artifact_page['hreflang'] || {}) : {}
    resolved_canonical = canonical_path
    resolved_fallback  = fm_fallback
    if artifact_page
      resolved_fallback = artifact_page['fallback_locale']
      resolved_fallback = nil if resolved_fallback.to_s.strip == ''
    end
    artifact_locales = artifact_page ? (artifact_page['locales'] || []) : [locale]

    # Compile markdown body to HTML
    body_html = safe_markdown_to_html(body_markdown)

    # Run safety checks on body HTML (after compilation)
    run_safety_checks!(body_html, context: 'compiled body')

    # Determine whether to show fallback banner.
    # Show it only when fallback_locale is set AND the requested locale is not
    # in the artifact page's locales array (i.e., the page does not exist in
    # this locale and we are showing a fallback).
    show_fallback_banner = resolved_fallback &&
                           !resolved_fallback.empty? &&
                           !artifact_locales.include?(locale)

    html = emit_html(
      locale: locale,
      title: title,
      canonical_path: resolved_canonical,
      hreflang: resolved_hreflang,
      body_html: body_html,
      fallback_locale: resolved_fallback,
      show_fallback_banner: show_fallback_banner
    )

    { html: html, page_id: page_id, locale: locale, canonical_path: resolved_canonical }
  end

  # Read file, compile, return hash + output_path suggestion.
  def compile_file(markdown_file_path)
    source = File.read(markdown_file_path, encoding: 'UTF-8')
    result = compile_page(source)
    basename = File.basename(markdown_file_path, '.md')
    result[:output_path] = "#{basename}.html"
    result
  end

  # ── Frontmatter parser ─────────────────────────────────────────────────────

  def parse_frontmatter(source)
    # Accept YAML frontmatter between --- delimiters at the top of the file.
    if source.start_with?("---\n") || source.start_with?("---\r\n")
      # Find the closing ---
      rest = source.sub(/\A---\r?\n/, '')
      end_idx = rest.index(/^---\r?\n/) || rest.index(/^---\z/)
      if end_idx
        yaml_text = rest[0, end_idx]
        body = rest[end_idx..].sub(/\A---\r?\n?/, '')
        frontmatter = YAML.safe_load(yaml_text) || {}
        return [frontmatter, body]
      end
    end
    [{}, source]
  end

  # ── Safe Markdown → HTML converter ────────────────────────────────────────
  #
  # Handles: ATX headings, paragraphs, unordered lists, fenced code blocks,
  # pipe tables, inline code, bold (**), links ([text](url)), HTML escaping.
  # Security: rejects javascript: and file:// links, escapes all text content.

  def safe_markdown_to_html(markdown_text)
    lines   = markdown_text.split("\n", -1)
    output  = []
    i       = 0
    n       = lines.length

    while i < n
      line = lines[i]

      # ── Fenced code block ─────────────────────────────────────────────────
      if line =~ /\A```(.*)\z/
        lang = $1.strip
        i += 1
        code_lines = []
        while i < n && lines[i] !~ /\A```\s*\z/
          code_lines << lines[i]
          i += 1
        end
        i += 1 # consume closing ```
        escaped_code = code_lines.map { |cl| html_escape(cl) }.join("\n")
        lang_attr = lang.empty? ? '' : " class=\"language-#{html_escape(lang)}\""
        output << "<pre><code#{lang_attr}>#{escaped_code}</code></pre>"
        next
      end

      # ── ATX heading ───────────────────────────────────────────────────────
      if line =~ /\A(\#{1,6})\s+(.*)\z/
        level = $1.length
        text  = inline_markup($2.strip)
        output << "<h#{level}>#{text}</h#{level}>"
        i += 1
        next
      end

      # ── Pipe table ────────────────────────────────────────────────────────
      if line =~ /\A\s*\|/ && i + 1 < n && lines[i + 1] =~ /\A\s*\|[-| :]+\|\s*\z/
        header_cells = parse_table_row(line)
        i += 1 # skip separator row
        i += 1
        body_rows = []
        while i < n && lines[i] =~ /\A\s*\|/
          body_rows << parse_table_row(lines[i])
          i += 1
        end
        table_html  = "<table>\n<thead>\n<tr>"
        table_html += header_cells.map { |c| "<th>#{inline_markup(c)}</th>" }.join
        table_html += "</tr>\n</thead>\n<tbody>\n"
        body_rows.each do |row|
          table_html += "<tr>"
          table_html += row.map { |c| "<td>#{inline_markup(c)}</td>" }.join
          table_html += "</tr>\n"
        end
        table_html += "</tbody>\n</table>"
        output << table_html
        next
      end

      # ── Unordered list ────────────────────────────────────────────────────
      if line =~ /\A- (.*)\z/
        items = []
        while i < n && lines[i] =~ /\A- (.*)\z/
          items << $1
          i += 1
        end
        list_html  = "<ul>\n"
        list_html += items.map { |item| "<li>#{inline_markup(item)}</li>" }.join("\n")
        list_html += "\n</ul>"
        output << list_html
        next
      end

      # ── Blank line (paragraph separator) ─────────────────────────────────
      if line.strip.empty?
        i += 1
        next
      end

      # ── Paragraph ─────────────────────────────────────────────────────────
      para_lines = []
      while i < n && !lines[i].strip.empty? &&
            lines[i] !~ /\A```/ &&
            lines[i] !~ /\A\#{1,6}\s/ &&
            lines[i] !~ /\A- / &&
            lines[i] !~ /\A\s*\|/
        para_lines << lines[i]
        i += 1
      end
      unless para_lines.empty?
        para_text = para_lines.map { |pl| inline_markup(pl) }.join(" ")
        output << "<p>#{para_text}</p>"
      end
    end

    output.join("\n")
  end

  # ── Inline markup (bold, inline code, links) ──────────────────────────────

  def inline_markup(text)
    # First escape raw HTML, then apply inline patterns.
    result = html_escape(text)

    # Bold: **text** → <strong>text</strong>
    # (already escaped so we work on the escaped string)
    result = result.gsub(/\*\*(.+?)\*\*/) { "<strong>#{$1}</strong>" }

    # Inline code: `code` → <code>code</code>
    # The backtick content is already HTML-escaped.
    result = result.gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }

    # Links: [text](url) → <a href="url">text</a>
    # url is extracted from already-escaped text; we need to unescape for scheme check.
    result = result.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
      link_text = $1
      href_escaped = $2
      # Unescape to check scheme (html_escape only escapes &, <, >, ")
      href_raw = href_escaped.gsub('&amp;', '&').gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"')
      if href_raw =~ /\Ajavascript:/i
        raise SiteCompilerSafetyError,
              "Safety violation: javascript: scheme link detected in content: #{href_raw[0, 40].inspect}"
      end
      if href_raw =~ /\Afile:\/\//i
        raise SiteCompilerSafetyError,
              "Safety violation: file:// URI detected in content link: #{href_raw[0, 40].inspect}"
      end
      "<a href=\"#{href_escaped}\">#{link_text}</a>"
    end

    result
  end

  # ── HTML escape ───────────────────────────────────────────────────────────

  def html_escape(text)
    text.to_s
      .gsub('&', '&amp;')
      .gsub('<', '&lt;')
      .gsub('>', '&gt;')
      .gsub('"', '&quot;')
  end

  # ── Table row parser ──────────────────────────────────────────────────────

  def parse_table_row(line)
    # Strip leading/trailing pipes and whitespace, split on |
    cells = line.strip.sub(/\A\|/, '').sub(/\|\s*\z/, '').split('|')
    cells.map(&:strip)
  end

  # ── SiteArtifact page lookup ───────────────────────────────────────────────

  def find_artifact_page(canonical_path)
    # Primary: find by canonical_path exact match
    page = @pages.find { |p| p['canonical_path'] == canonical_path }
    return page if page

    # Secondary: find by hreflang value match (for localized paths)
    @pages.find do |p|
      hreflang = p['hreflang'] || {}
      hreflang.values.include?(canonical_path)
    end
  end

  # ── HTML page emitter ─────────────────────────────────────────────────────

  def emit_html(locale:, title:, canonical_path:, hreflang:, body_html:,
                fallback_locale:, show_fallback_banner:)
    safe_locale   = html_escape(locale)
    safe_title    = html_escape(title)
    safe_canonical = html_escape(canonical_path)

    hreflang_tags = hreflang.map do |lang, path|
      safe_lang = html_escape(lang)
      safe_path = html_escape(path)
      "  <link rel=\"alternate\" hreflang=\"#{safe_lang}\" href=\"#{safe_path}\">"
    end.join("\n")

    fallback_banner_html = ''
    if show_fallback_banner && fallback_locale
      safe_fb = html_escape(fallback_locale.to_s)
      fallback_banner_html = <<~HTML.chomp
        <div class="iglab-fallback-banner" data-fallback-locale="#{safe_fb}">
          This page is not yet available in the requested locale.
          You are viewing the #{safe_fb} version.
        </div>
      HTML
    end

    <<~HTML
      <!DOCTYPE html>
      <html lang="#{safe_locale}">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{safe_title} — Igniter</title>
        <link rel="canonical" href="#{safe_canonical}">
      #{hreflang_tags}
      </head>
      <body>
      #{fallback_banner_html}#{fallback_banner_html.empty? ? '' : "\n"}#{body_html}
      </body>
      </html>
    HTML
  end

  # ── Safety checks ─────────────────────────────────────────────────────────

  UNSAFE_PATH_PATTERNS = [
    /\/Users\//,
    /\/home\//,
    /C:\\Users\\/i
  ].freeze

  def run_safety_checks!(content, context: 'content')
    UNSAFE_PATH_PATTERNS.each do |pat|
      if content.match?(pat)
        raise SiteCompilerSafetyError,
              "Safety violation in #{context}: absolute local path detected (pattern: #{pat.inspect})"
      end
    end

    if content.include?('file://')
      raise SiteCompilerSafetyError,
            "Safety violation in #{context}: file:// URI detected"
    end

    if content =~ /href\s*=\s*["']?javascript:/i
      raise SiteCompilerSafetyError,
            "Safety violation in #{context}: javascript: scheme in href detected"
    end
  end
end
