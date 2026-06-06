# igniter-lab/igniter-view-engine/lib/igniter_view_engine.rb

require 'json'
require 'cgi'

module IgniterView
  # Represents an immutable or structured piece of raw HTML that should NOT be escaped.
  class SafeString < String
    def html_safe?
      true
    end
  end

  # Helper to mark text as unsafe/raw HTML (VDSL-6)
  def self.raw(html)
    SafeString.new(html.to_s)
  end

  # Node representing an HTML element, component, or text in the view tree.
  class HtmlNode
    attr_reader :tag, :attributes, :children, :is_component, :component_name, :trace_metadata
    attr_accessor :state_slots, :ui_states, :display_rules, :interaction_rules, :node_params

    def initialize(tag, attributes = {}, children = [], is_component: false, component_name: nil, trace_metadata: {})
      @tag = tag.to_s
      @attributes = attributes || {}
      @children = children || []
      @is_component = is_component
      @component_name = component_name
      @trace_metadata = trace_metadata
      @state_slots = nil
      @ui_states = nil
      @display_rules = nil
      @interaction_rules = nil
      @node_params = nil
    end

    # HTML string representation (VDSL-5, VDSL-6)
    def to_html
      if @tag == "text"
        content = @children.first.to_s
        if @children.first.respond_to?(:html_safe?) && @children.first.html_safe?
          return content
        else
          return CGI.escapeHTML(content)
        end
      end

      attrs_str = @attributes.map do |k, v|
        escaped_val = CGI.escapeHTML(v.to_s)
        " #{k}=\"#{escaped_val}\""
      end.join

      if self.class.self_closing?(@tag) && @children.empty?
        "<#{@tag}#{attrs_str}/>"
      else
        children_html = @children.map(&:to_html).join
        "<#{@tag}#{attrs_str}>#{children_html}</#{@tag}>"
      end
    end

    # Serializes the view tree structure to a detailed inspectable hash (VDSL-4)
    def to_h
      h = {
        tag: @tag,
        attributes: @attributes,
        is_component: @is_component,
        component_name: @component_name,
        trace_metadata: @trace_metadata,
        children: @children.map { |c| c.respond_to?(:to_h) ? c.to_h : c.to_s }
      }
      h[:state_slots] = @state_slots if @state_slots
      h[:ui_states] = @ui_states if @ui_states
      h[:display_rules] = @display_rules if @display_rules
      h[:interaction_rules] = @interaction_rules if @interaction_rules
      h[:node_params] = @node_params if @node_params
      h
    end

    def self.self_closing?(tag)
      %w[area base br col embed hr img input link meta param source track wbr].include?(tag.to_s.downcase)
    end
  end

  # Tracks diagnostics, warnings, errors, and rendering traces (VDSL-7, VDSL-8)
  class DiagnosticsTracker
    attr_reader :events, :token_usage

    def initialize
      @events = []
      @token_usage = Hash.new(0)
    end

    def log_event(kind, message, metadata = {})
      @events << {
        timestamp: Time.now.to_s,
        kind: kind,
        message: message,
        metadata: metadata
      }
    end

    def track_classes(classes_str)
      return unless classes_str
      classes_str.split(/\s+/).each do |cls|
        @token_usage[cls] += 1
      end
    end
  end
end
