# frozen_string_literal: true
# LayoutEngine — Layout primitives for Igniter Web Framework
# Card: LAB-WEB-FRAMEWORK-P4
# Surface: lab-only · proof-local · no canon claim · no stable API
#
# Provides:
#   - Named layout slot model (header, nav, content, sidebar, footer)
#   - Slot filling with SiteContentCompiler safety integration
#   - Layout validation (required slots, unknown slot detection)
#   - Layout composition: 2-level inheritance (parent wraps child)

require_relative 'site_content_compiler'

# Extend SiteContentCompiler with a class-level compile convenience method
# that sanitizes plain markdown/HTML without requiring a site artifact path.
# Returns { html: String, errors: Array<String> }.
unless SiteContentCompiler.respond_to?(:compile)
  class SiteContentCompiler
    # Class-level compile: sanitize and convert raw markdown or HTML fragment.
    # No frontmatter or site artifact required. Used by LayoutEngine.fill_slot.
    # Returns { html: String, errors: Array<String> }.
    def self.compile(raw_content)
      errors = []
      # Use a minimal instance with no artifact data to access safe_markdown_to_html
      instance = new(nil)
      begin
        html = instance.safe_markdown_to_html(raw_content.to_s)
        instance.run_safety_checks!(html, context: 'layout slot content')
        { html: html, errors: errors }
      rescue SiteCompilerSafetyError => e
        { html: '', errors: [e.message] }
      rescue => e
        { html: '', errors: ["Compilation error: #{e.message}"] }
      end
    end

    # Allow nil artifact path for class-level compile usage
    alias_method :_orig_initialize, :initialize
    def initialize(site_artifact_path)
      if site_artifact_path.nil?
        @artifact = {}
        @pages = []
      else
        _orig_initialize(site_artifact_path)
      end
    end
  end
end

module LayoutEngine
  # Known slot names for a page layout
  SLOT_NAMES = %w[header nav content sidebar footer].freeze

  # Only 'content' is required; others are optional
  REQUIRED_SLOTS = %w[content].freeze

  # Default slot content (used when an optional slot is not explicitly filled)
  SLOT_DEFAULTS = {
    'header'  => '',
    'nav'     => '',
    'content' => '',
    'sidebar' => '',
    'footer'  => ''
  }.freeze

  # ── Layout definition ───────────────────────────────────────────────────────

  # Define a layout descriptor.
  # @param name        [String]       Layout identifier
  # @param slots       [Array<String>] Slot names this layout exposes (subset of SLOT_NAMES)
  # @param template    [String]       HTML template with {{slot_name}} insertion points
  # @param parent_layout [String,nil] Name of the parent layout for 2-level inheritance
  # @return [Hash] layout descriptor
  def self.define_layout(name, slots:, template:, parent_layout: nil)
    unknown = slots - SLOT_NAMES
    raise ArgumentError, "Unknown slot(s): #{unknown.inspect}" unless unknown.empty?
    { name: name, slots: slots, template: template, parent_layout: parent_layout }
  end

  # ── Slot filling ────────────────────────────────────────────────────────────

  # Fill a named slot with raw content (markdown or plain text).
  # Content is sanitized through SiteContentCompiler before use.
  # @param layout     [Hash]   Layout descriptor (from define_layout)
  # @param slot_name  [String] Name of the slot to fill
  # @param raw_content [String] Raw markdown / text to compile and sanitize
  # @return [Hash] { slot: String, content: String, layout: String }
  def self.fill_slot(layout, slot_name, raw_content)
    raise ArgumentError, "Unknown slot: #{slot_name}" unless SLOT_NAMES.include?(slot_name)
    compiled = SiteContentCompiler.compile(raw_content)
    raise "Content compilation failed: #{compiled[:errors].join(', ')}" if compiled[:errors]&.any?
    { slot: slot_name, content: compiled[:html], layout: layout[:name] }
  end

  # ── Layout rendering ────────────────────────────────────────────────────────

  # Render a layout by substituting slot values into its template.
  # @param layout       [Hash]              Layout descriptor
  # @param filled_slots [Hash<String,String>] Map of slot_name → compiled HTML content
  # @return [Hash] { ok: Boolean, html: String, layout: String, filled_slots: Array } on success
  #               { ok: Boolean, errors: Array<String> } on failure
  def self.render(layout, filled_slots = {})
    errors = []

    # Validate required slots
    REQUIRED_SLOTS.each do |req|
      if layout[:slots].include?(req) && !filled_slots.key?(req)
        errors << "required slot '#{req}' not filled in layout '#{layout[:name]}'"
      end
    end
    return { ok: false, errors: errors } if errors.any?

    # Merge with defaults for any unfilled optional slots
    effective_slots = SLOT_DEFAULTS.merge(filled_slots)

    # Substitute {{slot_name}} markers in the template
    html = layout[:template].dup
    layout[:slots].each do |slot|
      html = html.gsub("{{#{slot}}}", effective_slots[slot] || '')
    end

    { ok: true, html: html, layout: layout[:name], filled_slots: filled_slots.keys }
  end

  # ── Layout inheritance (2-level max) ────────────────────────────────────────

  # Render a child layout, then inject its output as the 'content' slot of a parent layout.
  # This is the maximum supported depth — no deeper nesting.
  # @param parent_layout      [Hash] Parent layout descriptor
  # @param child_layout       [Hash] Child layout descriptor
  # @param child_filled_slots  [Hash] Slots filled in the child layout
  # @param parent_filled_slots [Hash] Additional slots filled in the parent layout
  # @return [Hash] render result from parent (or child error if child fails)
  def self.render_inherited(parent_layout, child_layout, child_filled_slots = {}, parent_filled_slots = {})
    # Render child layout first
    child_result = render(child_layout, child_filled_slots)
    return child_result unless child_result[:ok]

    # Child's rendered HTML becomes the 'content' slot of the parent
    merged_parent_slots = parent_filled_slots.merge('content' => child_result[:html])
    render(parent_layout, merged_parent_slots)
  end

  # ── Layout validation ───────────────────────────────────────────────────────

  # Validate a layout descriptor for structural correctness.
  # @param layout [Hash] Layout descriptor to validate
  # @return [Hash] { valid: Boolean, errors: Array<String> }
  def self.validate_layout(layout)
    errors = []
    errors << 'name must be a non-empty string' unless layout[:name].is_a?(String) && !layout[:name].empty?
    errors << 'slots must be an array' unless layout[:slots].is_a?(Array)
    unknown = (layout[:slots] || []) - SLOT_NAMES
    errors << "unknown slots: #{unknown.inspect}" unless unknown.empty?
    errors << 'template must be a string' unless layout[:template].is_a?(String)
    { valid: errors.empty?, errors: errors }
  end
end
