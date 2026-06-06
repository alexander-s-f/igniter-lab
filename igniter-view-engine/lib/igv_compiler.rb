# frozen_string_literal: true

# igniter-lab/igniter-view-engine/lib/igv_compiler.rb
#
# Minimal .igv DSL → ViewArtifact compiler (lab prototype).
#
# Architecture:
#   .igv file (Ruby DSL)
#     → IgvCompiler.compile_file / compile_string
#     → IgvViewBuilder (top-level view context, instance_eval of DSL)
#         → IgvElementBuilder    (element block context)
#         → IgvCollectionBuilder (collection block context, P5)
#     → ViewArtifact (existing P1/P2 validated, content-addressed class)
#     → ViewArtifact JSON (consumed by SSRRenderer + JS micro-runtime)
#
# .igv syntax sketch (P5 addition — collection):
#
#   view "my.component" do
#     slot  :results, type: "array", from: "search.results"
#
#     collection :results_list,
#                slot:         :results,
#                item_element: :result_item,
#                item_key:     :id do
#       container_classes "results-list flex flex-col gap-2"
#       container_tag "ul"
#       item_tag "li"
#     end
#
#     element :result_item do
#       classes "result-item p-3 rounded border"
#       param :id,     type: "string"
#       param :status, type: "string"
#       display :match,
#               subject: param(:status),
#               cases:   { "ok" => { c: "border-ok" }, "err" => { c: "border-oof" } },
#               default: { c: "border-line" }
#     end
#   end
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-syntax
# Track: lab-igniter-view-dsl-to-viewartifact-sketch-v0 / P5 extension

require_relative "view_artifact"

module IgniterView
  # Raised when a .igv DSL construct is semantically invalid.
  # Distinct from Ruby SyntaxError (parse) or ArgumentError (ViewArtifact validation).
  class IgvCompileError < StandardError; end

  IGV_ALLOWED_OPCODES = %w[set_ui_state toggle_ui_state clear_ui_state].freeze
  IGV_BANNED_OPCODES  = %w[fetch dispatch boot watch persistence eval
                            innerHTML localStorage sessionStorage].freeze

  # ── Expression helpers ────────────────────────────────────────────────────
  # Included into IgvElementBuilder. Produce the same nested-array expression
  # format consumed by the JS runtime's evaluate() and by ViewArtifact.
  module IgvExpressions
    def ui_state(key)  = ["ui_state", key.to_s]
    def eq(a, b)       = ["eq",  a, b]
    def neq(a, b)      = ["neq", a, b]
    def gt(a, b)       = ["gt",  a, b]
    def lt(a, b)       = ["lt",  a, b]
    def gte(a, b)      = ["gte", a, b]
    def lte(a, b)      = ["lte", a, b]
    def and_(a, b)     = ["and", a, b]
    def or_(a, b)      = ["or",  a, b]
    def not_(a)        = ["not", a]
  end

  # ── Instruction helpers ───────────────────────────────────────────────────
  # Produce instruction arrays for `on` blocks.
  module IgvInstructions
    def set_ui_state(key, value_expr = nil) = ["set_ui_state", key.to_s, value_expr]
    def toggle_ui_state(key)                = ["toggle_ui_state", key.to_s]
    def clear_ui_state(key)                 = ["clear_ui_state", key.to_s]
  end


  # ── IgvElementBuilder ─────────────────────────────────────────────────────
  # DSL context for `element :name do ... end` blocks.
  # Provides: classes, param (declaration + expression), slot (expression only),
  # display, on, and all expression + instruction helpers.
  class IgvElementBuilder
    include IgvExpressions
    include IgvInstructions

    attr_reader :element_id, :static_classes, :node_params_schema,
                :display_rules, :interaction_rules

    def initialize(element_id)
      @element_id         = element_id.to_s
      @static_classes     = ""
      @node_params_schema = {}
      @display_rules      = []
      @interaction_rules  = []
    end

    # Set the static CSS classes for this element (always applied, SSR + client).
    def classes(str)
      @static_classes = str.to_s
    end

    # `param :key, type: "string"` → declares param in node_params_schema (returns nil).
    # `param(:key)` → expression reference `["param", "key"]` for display/interaction rules.
    def param(name, type: nil)
      if type
        @node_params_schema[name.to_s] = type.to_s
        nil
      else
        ["param", name.to_s]
      end
    end

    # `slot(:key)` → expression reference `["slot", "key"]` for display rules.
    # Declaring slots is a view-level concern (`slot :name, type:, from:` in the view block).
    # If someone mistakenly calls `slot :name, type: ...` inside an element block, raise.
    def slot(name, type: nil, from: nil)
      if type || from
        raise IgvCompileError,
              "slot declarations must be at view level (inside `view ... do`), " \
              "not inside element blocks. Found: slot :#{name} in element '#{@element_id}'."
      end
      ["slot", name.to_s]
    end

    # Add a display rule.
    #   display :style,
    #           condition: eq(ui_state(:active_tab), param(:id)),
    #           on_true:   { c: "bg-ignite", a: { selected: "true" } },
    #           on_false:  { c: "hidden" }
    #
    #   display :match,
    #           subject: ui_state(:mode),
    #           cases:   { "edit" => { c: "editable" }, "view" => { c: "read-only" } },
    #           default: { c: "unknown" }
    def display(kind, condition: nil, on_true: nil, on_false: nil,
                subject: nil, cases: nil, default: nil)
      case kind
      when :style
        raise IgvCompileError,
              "display :style in element '#{@element_id}' requires condition:" unless condition
        @display_rules << [
          "style",
          condition,
          normalise_effect(on_true),
          normalise_effect(on_false)
        ]
      when :match
        raise IgvCompileError,
              "display :match in element '#{@element_id}' requires subject:" unless subject
        normalised = (cases || {}).each_with_object({}) do |(k, v), h|
          h[k.to_s] = normalise_effect(v)
        end
        @display_rules << ["match", subject, normalised, normalise_effect(default)]
      else
        raise IgvCompileError, "Unknown display kind '#{kind.inspect}' in element '#{@element_id}'. " \
                                "Use :style or :match."
      end
    end

    # Add an interaction rule.
    #   on :click, set_ui_state(:active_tab, param(:id))
    #   on :click, set_ui_state(:x, "val"), toggle_ui_state(:y)
    def on(event, *instructions)
      instructions.each do |inst|
        unless inst.is_a?(Array)
          raise IgvCompileError,
                "Instruction in `on :#{event}` (element '#{@element_id}') must be an Array, " \
                "got #{inst.inspect}. Use set_ui_state(), toggle_ui_state(), or clear_ui_state()."
        end
        op = inst[0].to_s
        if IGV_BANNED_OPCODES.include?(op)
          raise IgvCompileError,
                "Banned opcode '#{op}' rejected in `on :#{event}` (element '#{@element_id}'). " \
                "Allowed: #{IGV_ALLOWED_OPCODES.join(", ")}."
        end
        unless IGV_ALLOWED_OPCODES.include?(op)
          raise IgvCompileError,
                "Unknown opcode '#{op}' in `on :#{event}` (element '#{@element_id}'). " \
                "Allowed: #{IGV_ALLOWED_OPCODES.join(", ")}."
        end
      end
      @interaction_rules << ["on", event.to_s, instructions]
    end

    def to_element_def
      ElementDef.new(
        element_id:         @element_id,
        static_classes:     @static_classes,
        node_params_schema: @node_params_schema,
        display_rules:      @display_rules,
        interaction_rules:  @interaction_rules
      )
    end

    private

    # Normalise effect hash: convert symbol keys → string keys.
    # Convert boolean aria values → string ("true"/"false") for HTML attribute safety.
    def normalise_effect(eff)
      return nil if eff.nil?
      eff = eff.transform_keys { |k| k.is_a?(Symbol) ? k.to_s : k }
      if eff["a"].is_a?(Hash)
        eff["a"] = eff["a"]
                   .transform_keys { |k| k.is_a?(Symbol) ? k.to_s : k }
                   .transform_values { |v| (v == true || v == false) ? v.to_s : v }
      end
      if eff["d"].is_a?(Hash)
        eff["d"] = eff["d"].transform_keys { |k| k.is_a?(Symbol) ? k.to_s : k }
      end
      eff
    end
  end


  # ── IgvCollectionBuilder (P5) ─────────────────────────────────────────────
  # DSL context for `collection :name, slot:, item_element:, item_key: do ... end` blocks.
  # Provides: container_classes, container_tag, item_tag.
  # Status: lab-only · no-stable-syntax · P5 extension
  class IgvCollectionBuilder
    attr_reader :name

    def initialize(name, slot:, item_element:, item_key: "id")
      raise IgvCompileError, "collection name must be a non-empty Symbol or String" \
        if name.to_s.empty?
      raise IgvCompileError, "collection :#{name} requires `slot:` (non-empty)" \
        if slot.to_s.empty?
      raise IgvCompileError, "collection :#{name} requires `item_element:` (non-empty)" \
        if item_element.to_s.empty?

      @name              = name.to_s
      @slot              = slot.to_s
      @item_element      = item_element.to_s
      @item_key          = item_key.to_s.then { |k| k.empty? ? "id" : k }
      @container_classes = ""
      @container_tag     = "ul"
      @item_tag          = "li"
    end

    # Set static CSS classes for the collection container element.
    def container_classes(str)
      @container_classes = str.to_s
    end

    # Set HTML tag for the collection container (default: "ul").
    def container_tag(tag)
      @container_tag = tag.to_s
    end

    # Set HTML tag for each repeated item (default: "li").
    def item_tag(tag)
      @item_tag = tag.to_s
    end

    def to_def
      {
        "slot"              => @slot,
        "item_element"      => @item_element,
        "item_key"          => @item_key,
        "container_classes" => @container_classes,
        "container_tag"     => @container_tag,
        "item_tag"          => @item_tag
      }
    end
  end


  # ── IgvViewBuilder ────────────────────────────────────────────────────────
  # DSL context for the top-level `view "id" do ... end` block.
  # Provides: state, slot, element, collection (P5).
  class IgvViewBuilder
    NON_CLAIMS_DEFAULT = %w[
      lab-only experimental no-canon no-public-api no-stable-syntax
      no-production-readiness no-reference-runtime no-portability-guarantee
      no-stable-schema
    ].freeze

    attr_reader :view_id, :ui_states, :slots, :element_defs, :collection_defs, :diagnostics

    def initialize(view_id)
      @view_id         = view_id.to_s
      @ui_states       = {}
      @slots           = {}
      @element_defs    = []
      @collection_defs = {}
      @diagnostics     = []
    end

    # Declare a UIState field.
    #   state :active_tab, type: "string", default: "overview"
    def state(name, type: "string", default: nil)
      @ui_states[name.to_s] = { "type" => type.to_s, "default" => default }
    end

    # Declare a read-only slot (injected from contract execution receipt by host page).
    #   slot :has_warnings, type: "boolean", from: "diagnostics.has_warnings"
    def slot(name, type: "string", from: nil)
      raise IgvCompileError, "slot :#{name} requires `from:` (contract_ref path)" unless from
      @slots[name.to_s] = {
        "type"         => type.to_s,
        "contract_ref" => from.to_s,
        "mode"         => "read_only"
      }
    end

    # Define an element with its display and interaction rules.
    #   element :tab_btn do
    #     classes "..."
    #     param :id, type: "string"
    #     display :style, condition: eq(ui_state(:x), param(:id)), on_true: {...}, on_false: {...}
    #     on :click, set_ui_state(:x, param(:id))
    #   end
    def element(name, &block)
      elem_builder = IgvElementBuilder.new(name)
      elem_builder.instance_eval(&block) if block
      @element_defs << elem_builder.to_element_def
    end

    # Declare a collection — a named set of repeated element instances.
    # (P5 — lab-only · no-stable-syntax)
    #
    #   collection :results_list,
    #              slot:         :results,
    #              item_element: :result_item,
    #              item_key:     :id do
    #     container_classes "results-list flex flex-col gap-2"
    #     container_tag "ul"
    #     item_tag "li"
    #   end
    #
    # slot:         name of the slot providing the items array
    # item_element: name of the element_def used as the repeated template
    # item_key:     field name in each item used as a stable unique key (default: "id")
    def collection(name, slot:, item_element:, item_key: "id", &block)
      builder = IgvCollectionBuilder.new(name, slot: slot,
                                               item_element: item_element,
                                               item_key: item_key)
      builder.instance_eval(&block) if block
      @collection_defs[name.to_s] = builder.to_def
    end

    # Build the ViewArtifact from accumulated DSL state.
    # Raises IgvCompileError for semantic violations caught at DSL level.
    # Raises ArgumentError for ViewArtifact validation failures (banned opcodes, slot mutation, etc.).
    def build_artifact
      collect_slot_ref_warnings!

      ViewArtifact.new(
        view_id:     @view_id,
        ui_states:   @ui_states,
        slots:       @slots,
        elements:    @element_defs,
        collections: @collection_defs,
        non_claims:  NON_CLAIMS_DEFAULT
      )
    end

    private

    # Walk display rules and warn on references to undeclared slots.
    # These are warnings (not errors): at runtime, the P2 filterSlotValues guard
    # drops undeclared slot values, so the expression evaluates as nil → falsy branch.
    def collect_slot_ref_warnings!
      declared = @slots.keys
      @element_defs.each do |elem|
        collect_slot_refs(elem.display_rules).each do |key|
          next if declared.include?(key)
          @diagnostics << {
            type:    "undeclared_slot_reference",
            element: elem.element_id,
            key:     key,
            message: "Element '#{elem.element_id}' display rule references " \
                     "slot '#{key}' which is not declared in the view's `slot ...` " \
                     "declarations. At runtime this will evaluate nil (falsy branch). " \
                     "Add `slot :#{key}, type: ..., from: ...` to silence this warning."
          }
        end
      end
    end

    # Recursively collect all ["slot", key] leaf references in a nested expression/rule array.
    def collect_slot_refs(rules)
      refs = []
      walk = lambda do |node|
        return unless node.is_a?(Array)
        if node[0] == "slot" && node.length >= 2 && node[1].is_a?(String)
          refs << node[1]
          return
        end
        node.each { |sub| walk.call(sub) }
      end
      rules.each { |rule| walk.call(rule) }
      refs
    end
  end


  # ── IgvCompiler ──────────────────────────────────────────────────────────
  # Entry point. Compiles a .igv source string or file to a ViewArtifact.
  #
  # Usage:
  #   result = IgvCompiler.compile_file("fixtures/tabs.igv")
  #   result.success?           # → true
  #   result.artifact.to_json  # → ViewArtifact JSON
  #   result.diagnostics        # → [] (or warnings/errors)
  #
  # On compile failure:
  #   result.success?    → false
  #   result.artifact    → nil
  #   result.diagnostics → [{ type: "compile_error", message: "...", source: "..." }, ...]
  class IgvCompiler
    attr_reader :artifact, :diagnostics, :source_path

    def initialize
      @artifact    = nil
      @diagnostics = []
      @source_path = "(igv)"
    end

    def self.compile_file(path)
      new.compile_file(path)
    end

    def self.compile_string(source, source_path: "(igv)")
      new.compile_string(source, source_path: source_path)
    end

    def compile_file(path)
      @source_path = path
      source = File.read(path, encoding: "utf-8")
      compile_string(source, source_path: path)
    rescue Errno::ENOENT => e
      @diagnostics << { type: "file_not_found", source: path, message: e.message }
      self
    end

    def compile_string(source, source_path: "(igv)")
      @source_path = source_path
      view_builder = nil

      # Wrapper object: provides the top-level `view` DSL keyword.
      # Evaluating the source via wrapper.instance_eval means the source can call `view`.
      wrapper = Object.new
      wrapper.define_singleton_method(:view) do |id, &block|
        raise IgvCompileError, "`view` id must be a non-empty String, got #{id.inspect}" \
          unless id.is_a?(String) && !id.empty?
        vb = IgvViewBuilder.new(id)
        vb.instance_eval(&block) if block
        view_builder = vb
      end

      wrapper.instance_eval(source, source_path)

      if view_builder.nil?
        raise IgvCompileError, "No `view \"...\" do ... end` declaration found in #{source_path}"
      end

      # Merge view-builder diagnostics (warnings from slot ref check etc.)
      @diagnostics.concat(view_builder.diagnostics)

      # Build the artifact (may raise IgvCompileError or ArgumentError)
      @artifact = view_builder.build_artifact

      # Merge any warnings accumulated during build
      @diagnostics.concat(view_builder.diagnostics - @diagnostics)
      self

    rescue IgvCompileError => e
      @artifact = nil
      @diagnostics << { type: "compile_error", source: source_path, message: e.message }
      self
    rescue ArgumentError => e
      @artifact = nil
      @diagnostics << { type: "validation_error", source: source_path, message: e.message }
      self
    rescue SyntaxError => e
      @artifact = nil
      @diagnostics << { type: "syntax_error", source: source_path, message: e.message }
      self
    rescue NameError => e
      @artifact = nil
      @diagnostics << {
        type:    "name_error",
        source:  source_path,
        message: "Unknown identifier '#{e.name}' in .igv source. " \
                 "Check DSL method names (state, slot, element, collection, classes, param, " \
                 "display, on, ui_state, eq, neq, set_ui_state, toggle_ui_state, ...)."
      }
      self
    rescue StandardError => e
      @artifact = nil
      @diagnostics << {
        type:    "unknown_error",
        source:  source_path,
        message: "#{e.class}: #{e.message}"
      }
      self
    end

    # True if compilation succeeded with no error-level diagnostics.
    # Warnings (undeclared_slot_reference, etc.) do not cause failure.
    def success?
      return false if @artifact.nil?
      error_types = %w[compile_error validation_error syntax_error name_error
                       unknown_error file_not_found]
      @diagnostics.none? { |d| error_types.include?(d[:type].to_s) }
    end

    def to_json
      @artifact&.to_json
    end
  end
end
