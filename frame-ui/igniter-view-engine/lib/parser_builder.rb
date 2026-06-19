# igniter-lab/igniter-view-engine/lib/parser_builder.rb

require_relative 'igniter_view_engine'

module IgniterView
  class ParserBuilder
    def initialize(diagnostics = nil)
      @children = []
      @diagnostics = diagnostics || DiagnosticsTracker.new
      @trace_ctx = []
      @building_nodes = []
    end

    def get_nodes
      @children
    end

    # Conditional rendering (VDSL-7)
    def render_if(condition, &block)
      @diagnostics.log_event("conditional_check", "Evaluating conditional block", { condition: !!condition })
      if condition
        @trace_ctx << "then"
        instance_eval(&block)
        @trace_ctx.pop
      else
        @trace_ctx << "else"
        @diagnostics.log_event("conditional_skip", "Conditional block skipped", { condition: false })
        @trace_ctx.pop
      end
    end

    # Loops / Collections (VDSL-8)
    def render_each(collection, &block)
      @diagnostics.log_event("loop_execution", "Starting loop over collection", { size: collection.size })
      collection.each_with_index do |item, index|
        @trace_ctx << "loop_index_#{index}"
        block.call(item)
        @trace_ctx.pop
      end
    end

    # Standard tags & Component calls
    def p(*args, &block)
      method_missing(:p, *args, &block)
    end

    def select(*args, &block)
      method_missing(:select, *args, &block)
    end

    def method_missing(name, *args, &block)
      # Check if this name represents a component contract
      if name.to_s.end_with?("_component") || name.to_s =~ /^[A-Z]/
        component_name = name.to_s.gsub("_component", "")
        return invoke_component(component_name, args.first || {}, &block)
      end

      tag_name = name.to_s
      attributes = {}
      content = nil

      args.each do |arg|
        if arg.is_a?(Hash)
          attributes.merge!(arg)
        else
          content = arg
        end
      end

      # Track token usage (VDSL-4)
      if attributes[:class]
        @diagnostics.track_classes(attributes[:class])
      end

      node = HtmlNode.new(tag_name, attributes, [], trace_metadata: { context: @trace_ctx.dup })

      @building_nodes ||= []
      @building_nodes.push(node)

      parent_children = @children
      @children = []

      # Add text node if content is present
      if content
        @children << HtmlNode.new("text", {}, [content], trace_metadata: { context: @trace_ctx.dup })
      end

      if block_given?
        instance_eval(&block)
      end

      node.children.concat(@children)
      @children = parent_children

      @building_nodes.pop

      @children << node
      node
    end

    # Forms-assisted component invocation (VDSL-9)
    def form(component_sym, args = {}, &block)
      @diagnostics.log_event("forms_assisted_invocation", "Forms-assisted dispatch sugar invoked", { form: component_sym })
      invoke_component(component_sym.to_s, args, forms_assisted: true, &block)
    end

    def invoke_component(name, args, forms_assisted: false, &block)
      @diagnostics.log_event("component_invocation", "Invoking component contract", { name: name, args: args, forms_assisted: forms_assisted })
      
      node = HtmlNode.new(
        "component", 
        args, 
        [], 
        is_component: true, 
        component_name: name,
        trace_metadata: { 
          context: @trace_ctx.dup, 
          forms_assisted: forms_assisted 
        }
      )

      @building_nodes ||= []
      @building_nodes.push(node)

      parent_children = @children
      @children = []

      if block_given?
        instance_eval(&block)
      end

      node.children.concat(@children)
      @children = parent_children

      @building_nodes.pop

      @children << node
      node
    end

    def bind_slot(slot_id, contract_output_ref, value_kind, render_policy, fallback)
      target_node = @building_nodes&.last || @children.last
      if target_node.is_a?(HtmlNode)
        target_node.state_slots ||= []
        target_node.state_slots << {
          slot_id: slot_id.to_s,
          contract_output_ref: contract_output_ref.to_s,
          value_kind: value_kind.to_s,
          render_policy: render_policy.to_s,
          fallback: fallback
        }
      end
    end

    def ui_state(key, default_value)
      current_node = @building_nodes&.last
      if current_node
        current_node.ui_states ||= {}
        current_node.ui_states[key.to_s] = default_value
      else
        last_node = @children.last
        if last_node.is_a?(HtmlNode)
          last_node.ui_states ||= {}
          last_node.ui_states[key.to_s] = default_value
        end
      end
    end

    def display_rule(rule)
      current_node = @building_nodes&.last
      if current_node
        current_node.display_rules ||= []
        current_node.display_rules << rule
      else
        last_node = @children.last
        if last_node.is_a?(HtmlNode)
          last_node.display_rules ||= []
          last_node.display_rules << rule
        end
      end
    end

    def interaction_rule(event, instructions)
      current_node = @building_nodes&.last
      target_node = current_node || @children.last

      # Validate instructions to reject banned/unwhitelisted opcodes (VDSL-IR-5)
      instructions.each do |inst|
        op = inst[0].to_s
        if %w[fetch dispatch boot watch persistence].include?(op)
          @diagnostics.log_event("safe_renderer_warning", "Interaction Security Violation: Blocked banned side-effect opcode '#{op}'")
          raise "Interaction Security Violation: Blocked banned side-effect opcode '#{op}'"
        end

        unless %w[set_ui_state toggle_ui_state clear_ui_state].include?(op)
          @diagnostics.log_event("safe_renderer_warning", "Interaction Security Violation: Banned/Unknown opcode '#{op}'")
          raise "Interaction Security Violation: Banned/Unknown opcode '#{op}'"
        end

        # TMX-P2-2 / TMX-P2-5: Target must be in UIState, SlotValue mutation target is read-only
        target_key = inst[1].to_s
        is_slot = target_node.is_a?(HtmlNode) && target_node.state_slots && target_node.state_slots.any? { |s| s[:slot_id] == target_key }
        if is_slot
          @diagnostics.log_event("safe_renderer_warning", "Interaction Security Violation: Attempted mutation of read-only SlotValue '#{target_key}'")
          raise "Interaction Security Violation: Attempted mutation of read-only SlotValue '#{target_key}'"
        end
      end

      if target_node.is_a?(HtmlNode)
        target_node.interaction_rules ||= []
        target_node.interaction_rules << [event.to_s, instructions]
      end
    end

    def node_param(key, value)
      current_node = @building_nodes&.last
      if current_node
        current_node.node_params ||= {}
        current_node.node_params[key.to_s] = value
      else
        last_node = @children.last
        if last_node.is_a?(HtmlNode)
          last_node.node_params ||= {}
          last_node.node_params[key.to_s] = value
        end
      end
    end
  end
end
