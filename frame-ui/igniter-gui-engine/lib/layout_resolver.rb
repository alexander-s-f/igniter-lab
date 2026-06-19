# igniter-lab/igniter-gui-engine/lib/layout_resolver.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require_relative "scene_tree"

module IgniterGui
  class LayoutResolver
    attr_reader :scene, :computed_boxes

    SUPPORTED_LAYOUT_KEYS = %w[type direction gap align alignment overflow x y weight].freeze
    SUPPORTED_STYLE_KEYS = %w[
      width height w h margin padding z_index opacity transform
      transform_translate_x transform_translate_y transform_scale
      font font_family font_size size fill stroke border_width
      border_color rx ry r weight align alignment
      x y visible active text_color color background focus_target focusable focused
    ].freeze

    def initialize(scene)
      @scene = scene
      @computed_boxes = {} # node_id -> { x:, y:, w:, h: }
    end

    def resolve!
      @computed_boxes = {} # root-down layout recalculation guard
      # 0. Validate layout constraints and formats
      validate_layout_constraints!

      # 1. Build hierarchy map (parent_id -> children_nodes) and find root nodes
      nodes_by_id = {}
      @scene.nodes.each { |n| nodes_by_id[n["id"]] = n }

      parent_to_children = Hash.new { |h, k| h[k] = [] }
      roots = []

      @scene.nodes.each do |node|
        parent_id = node["parent"]
        if parent_id.nil? || parent_id.to_s.strip.empty?
          roots << node
        else
          parent_to_children[parent_id] << node
        end
      end

      # 2. Check for parent cycles via DFS traversal
      detect_cycles!(roots, parent_to_children, nodes_by_id)

      # 3. Resolve bounds from roots down
      roots.each do |root|
        resolve_node_and_descendants!(root, nil, parent_to_children)
      end

      # 4. Construct result structure
      result = {
        "view_id" => @scene.view_id,
        "scene_digest" => @scene.digest,
        "canvas" => @scene.canvas,
        "resolved_nodes" => @scene.nodes.map do |n|
          box = @computed_boxes[n["id"]]
          if box.nil? && (n["visible"] == false || n["active"] == false)
            box = { "x" => 0, "y" => 0, "w" => 0, "h" => 0 }
          end
          {
            "id" => n["id"],
            "type" => n["type"],
            "parent" => n["parent"],
            "computed_bounds" => box
          }
        end,
        "non_claims" => @scene.non_claims
      }

      result
    end

    private

    def validate_layout_constraints!
      # Check node count
      if @scene.nodes.size > 100
        raise ValidationError.new("Excessive node count detected", check_id: "NGUI-P8-14")
      end

      # Check node depths and cycles
      nodes_by_id = {}
      @scene.nodes.each { |n| nodes_by_id[n["id"]] = n }
      @scene.nodes.each do |node|
        depth = 0
        curr = node
        visited_in_chain = {}
        while curr
          if visited_in_chain[curr["id"]]
            raise ValidationError.new("Cyclic parent reference detected involving node '#{curr["id"]}'", check_id: "NGUI-P1-6")
          end
          visited_in_chain[curr["id"]] = true

          parent_id = curr["parent"]
          break if parent_id.nil? || parent_id.to_s.strip.empty?
          parent_node = nodes_by_id[parent_id]
          break unless parent_node
          depth += 1
          if depth >= 10
            raise ValidationError.new("Excessive node depth detected", check_id: "NGUI-P8-14")
          end
          curr = parent_node
        end
      end

      # Validate layout keys and parameter formats
      @scene.nodes.each do |node|
        id = node["id"]
        layout = node["layout"]
        style = node["style"] || {}

        if style.is_a?(Hash)
          style.each_key do |k|
            unless SUPPORTED_STYLE_KEYS.include?(k.to_s)
              raise ValidationError.new("Unsupported style key '#{k}' in node '#{id}'", check_id: "NGUI-P9-11")
            end
          end
        end

        if layout.is_a?(Hash)
          # NGUI-P8-10: Reject unsupported constraint keys
          layout.each_key do |k|
            unless SUPPORTED_LAYOUT_KEYS.include?(k.to_s)
              raise ValidationError.new("Unsupported constraint key '#{k}' in layout of node '#{id}'", check_id: "NGUI-P8-10")
            end
          end

          # Validate layout type
          if layout.key?("type")
            l_type = layout["type"]
            unless %w[absolute flex row column].include?(l_type)
              raise ValidationError.new("Unsupported layout mode '#{l_type}' on node '#{id}'", check_id: "NGUI-P8-9")
            end
          end

          # Validate layout direction
          if layout.key?("direction")
            dir = layout["direction"]
            unless %w[horizontal vertical].include?(dir)
              raise ValidationError.new("Unsupported layout direction '#{dir}' on node '#{id}'", check_id: "NGUI-P8-9")
            end
          end

          # Validate gap
          if layout.key?("gap")
            gap = layout["gap"]
            unless gap.is_a?(Numeric)
              raise ValidationError.new("Non-numeric gap value on node '#{id}'", check_id: "NGUI-P8-7")
            end
            if gap < 0
              raise ValidationError.new("Negative gap value on node '#{id}'", check_id: "NGUI-P8-8")
            end
          end

          # Validate weight
          if layout.key?("weight")
            w = layout["weight"]
            unless w.is_a?(Numeric)
              raise ValidationError.new("Non-numeric weight value on node '#{id}'", check_id: "NGUI-P8-7")
            end
            if w < 0
              raise ValidationError.new("Negative weight value on node '#{id}'", check_id: "NGUI-P8-8")
            end
          end

          # Validate align/alignment
          %w[align alignment].each do |k|
            if layout.key?(k)
              val = layout[k]
              unless %w[start center end].include?(val.to_s)
                raise ValidationError.new("Unsupported alignment value '#{val}' on node '#{id}'", check_id: "NGUI-P8-9")
              end
            end
          end

          # Validate x/y in layout
          %w[x y].each do |k|
            if layout.key?(k)
              val = layout[k]
              unless val.is_a?(Numeric)
                raise ValidationError.new("Non-numeric layout offset '#{k}' on node '#{id}'", check_id: "NGUI-P8-7")
              end
            end
          end
        end

        # Validate style bounds and weights
        %w[width height w h].each do |k|
          if style.key?(k)
            val = style[k]
            if val.is_a?(String)
              unless val.match?(/\A\d+(?:\.\d+)?%\z/)
                raise ValidationError.new("Non-numeric dimension format '#{val}' on node '#{id}'", check_id: "NGUI-P8-7")
              end
            elsif val.is_a?(Numeric)
              if val < 0
                raise ValidationError.new("Negative dimension value on node '#{id}'", check_id: "NGUI-P8-8")
              end
            else
              raise ValidationError.new("Non-numeric dimension value on node '#{id}'", check_id: "NGUI-P8-7")
            end
          end
        end

        %w[padding margin].each do |k|
          if style.key?(k)
            val = style[k]
            if val.is_a?(Hash)
              val.each do |sub_k, sub_val|
                unless %w[top bottom left right].include?(sub_k.to_s)
                  raise ValidationError.new("Unsupported constraint key '#{sub_k}' in style #{k} on node '#{id}'", check_id: "NGUI-P8-10")
                end
                unless sub_val.is_a?(Numeric)
                  raise ValidationError.new("Non-numeric #{k} value in sub-key '#{sub_k}' on node '#{id}'", check_id: "NGUI-P8-7")
                end
                if sub_val < 0
                  raise ValidationError.new("Negative #{k} value in sub-key '#{sub_k}' on node '#{id}'", check_id: "NGUI-P8-8")
                end
              end
            elsif val.is_a?(Numeric)
              if val < 0
                raise ValidationError.new("Negative #{k} value on node '#{id}'", check_id: "NGUI-P8-8")
              end
            else
              raise ValidationError.new("Non-numeric #{k} value on node '#{id}'", check_id: "NGUI-P8-7")
            end
          end
        end

        if style.key?("weight")
          w = style["weight"]
          unless w.is_a?(Numeric)
            raise ValidationError.new("Non-numeric style weight on node '#{id}'", check_id: "NGUI-P8-7")
          end
          if w < 0
            raise ValidationError.new("Negative style weight on node '#{id}'", check_id: "NGUI-P8-8")
          end
        end
      end
    end

    def detect_cycles!(roots, parent_to_children, nodes_by_id)
      visited = {}
      visiting = {}

      dfs = lambda do |node_id|
        visiting[node_id] = true
        
        parent_to_children[node_id].each do |child|
          child_id = child["id"]
          if visiting[child_id]
            raise ValidationError.new("Cyclic parent reference detected involving node '#{child_id}'", check_id: "NGUI-P1-6")
          end
          dfs.call(child_id) unless visited[child_id]
        end

        visiting.delete(node_id)
        visited[node_id] = true
      end

      roots.each do |root|
        dfs.call(root["id"])
      end

      unvisited = nodes_by_id.keys - visited.keys
      unless unvisited.empty?
        raise ValidationError.new("Cyclic parent reference detected involving node '#{unvisited.first}'", check_id: "NGUI-P1-6")
      end
    end

    def resolve_node_and_descendants!(node, parent_box, parent_to_children)
      id = node["id"]
      style = node["style"] || {}
      
      width_val = style["width"] || style["w"]
      height_val = style["height"] || style["h"]

      if @computed_boxes[id]
        x = @computed_boxes[id][:x]
        y = @computed_boxes[id][:y]
        w = @computed_boxes[id][:w]
        h = @computed_boxes[id][:h]
      else
        if parent_box
          w = resolve_dimension(width_val, parent_box[:w])
          h = resolve_dimension(height_val, parent_box[:h])
        else
          w = resolve_dimension(width_val, @scene.canvas["width"])
          h = resolve_dimension(height_val, @scene.canvas["height"])
        end
        x = 0
        y = 0
      end

      @computed_boxes[id] = { x: x, y: y, w: w, h: h }

      children = parent_to_children[id]
      return if children.nil? || children.empty?

      visible_children = children.select { |c| c["visible"] != false && c["active"] != false }
      return if visible_children.empty?

      layout = node["layout"] || { "type" => "absolute" }
      layout_type = layout["type"] || "absolute"

      padding = style["padding"] || 0
      pl = padding.is_a?(Hash) ? (padding["left"] || 0) : padding
      pr = padding.is_a?(Hash) ? (padding["right"] || 0) : padding
      pt = padding.is_a?(Hash) ? (padding["top"] || 0) : padding
      pb = padding.is_a?(Hash) ? (padding["bottom"] || 0) : padding

      inner_x = x + pl
      inner_y = y + pt
      inner_w = [0.0, w - (pl + pr)].max
      inner_h = [0.0, h - (pt + pb)].max

      if layout_type == "flex" || layout_type == "row" || layout_type == "column"
        direction = layout_type == "row" ? "horizontal" : (layout_type == "column" ? "vertical" : (layout["direction"] || "vertical"))
        gap = (layout["gap"] || style["gap"] || 0).to_f
        
        c_margins = {}
        total_weight = 0.0
        visible_children.each do |c|
          c_style = c["style"] || {}
          margin = c_style["margin"] || 0
          ml = margin.is_a?(Hash) ? (margin["left"] || 0) : margin
          mr = margin.is_a?(Hash) ? (margin["right"] || 0) : margin
          mt = margin.is_a?(Hash) ? (margin["top"] || 0) : margin
          mb = margin.is_a?(Hash) ? (margin["bottom"] || 0) : margin
          c_margins[c["id"]] = { ml: ml, mr: mr, mt: mt, mb: mb }
          
          weight = c["layout"]&.[]("weight") || c_style["weight"]
          total_weight += weight.to_f if weight
        end

        n_children = visible_children.size

        if direction == "horizontal"
          non_weight_space = 0.0
          visible_children.each do |c|
            ml = c_margins[c["id"]][:ml]
            mr = c_margins[c["id"]][:mr]
            weight = c["layout"]&.[]("weight") || c["style"]&.[]("weight")
            if weight.nil?
              cw = resolve_dimension(c["style"]&.[]("width") || c["style"]&.[]("w"), inner_w)
              non_weight_space += ml + cw + mr
            else
              non_weight_space += ml + mr
            end
          end
          non_weight_space += (n_children - 1) * gap

          weight_space = [0.0, inner_w - non_weight_space].max

          child_sizes = {}
          visible_children.each do |c|
            weight = c["layout"]&.[]("weight") || c["style"]&.[]("weight")
            if weight
              cw = total_weight > 0 ? (weight.to_f / total_weight) * weight_space : 0.0
            else
              cw = resolve_dimension(c["style"]&.[]("width") || c["style"]&.[]("w"), inner_w).to_f
            end
            ch = resolve_dimension(c["style"]&.[]("height") || c["style"]&.[]("h"), inner_h).to_f
            child_sizes[c["id"]] = { w: cw, h: ch }
          end

          total_main_size = 0.0
          visible_children.each do |c|
            total_main_size += c_margins[c["id"]][:ml] + child_sizes[c["id"]][:w] + c_margins[c["id"]][:mr]
          end
          total_main_size += (n_children - 1) * gap

          extra_space = inner_w - total_main_size
          parent_align = layout["align"] || layout["alignment"] || style["align"] || style["alignment"] || "start"

          start_x = case parent_align.to_s
                    when "center" then inner_x + extra_space / 2.0
                    when "end" then inner_x + extra_space
                    else inner_x
                    end

          curr_x = start_x
          visible_children.each do |c|
            id = c["id"]
            cw = child_sizes[id][:w]
            ch = child_sizes[id][:h]
            ml = c_margins[id][:ml]
            mr = c_margins[id][:mr]
            mt = c_margins[id][:mt]
            mb = c_margins[id][:mb]

            cx = curr_x + ml
            
            c_align = c["layout"]&.[]("align") || c["layout"]&.[]("alignment") || c["style"]&.[]("align") || c["style"]&.[]("alignment") || parent_align
            avail_cross = [0.0, inner_h - (mt + mb)].max
            if layout_type == "row" || layout_type == "column"
              ch = [ch, avail_cross].min
            end
            cy = case c_align.to_s
                  when "center" then inner_y + mt + (avail_cross - ch) / 2.0
                  when "end" then inner_y + mt + (avail_cross - ch)
                  else inner_y + mt
                  end

            @computed_boxes[id] = { x: cx.round, y: cy.round, w: cw.round, h: ch.round }
            resolve_node_and_descendants!(c, @computed_boxes[id], parent_to_children)

            curr_x += ml + cw + mr + gap
          end

        else # vertical direction
          non_weight_space = 0.0
          visible_children.each do |c|
            mt = c_margins[c["id"]][:mt]
            mb = c_margins[c["id"]][:mb]
            weight = c["layout"]&.[]("weight") || c["style"]&.[]("weight")
            if weight.nil?
              ch = resolve_dimension(c["style"]&.[]("height") || c["style"]&.[]("h"), inner_h)
              non_weight_space += mt + ch + mb
            else
              non_weight_space += mt + mb
            end
          end
          non_weight_space += (n_children - 1) * gap

          weight_space = [0.0, inner_h - non_weight_space].max

          child_sizes = {}
          visible_children.each do |c|
            weight = c["layout"]&.[]("weight") || c["style"]&.[]("weight")
            if weight
              ch = total_weight > 0 ? (weight.to_f / total_weight) * weight_space : 0.0
            else
              ch = resolve_dimension(c["style"]&.[]("height") || c["style"]&.[]("h"), inner_h).to_f
            end
            cw = resolve_dimension(c["style"]&.[]("width") || c["style"]&.[]("w"), inner_w).to_f
            child_sizes[c["id"]] = { w: cw, h: ch }
          end

          total_main_size = 0.0
          visible_children.each do |c|
            total_main_size += c_margins[c["id"]][:mt] + child_sizes[c["id"]][:h] + c_margins[c["id"]][:mb]
          end
          total_main_size += (n_children - 1) * gap

          extra_space = inner_h - total_main_size
          parent_align = layout["align"] || layout["alignment"] || style["align"] || style["alignment"] || "start"

          start_y = case parent_align.to_s
                    when "center" then inner_y + extra_space / 2.0
                    when "end" then inner_y + extra_space
                    else inner_y
                    end

          curr_y = start_y
          visible_children.each do |c|
            id = c["id"]
            cw = child_sizes[id][:w]
            ch = child_sizes[id][:h]
            ml = c_margins[id][:ml]
            mr = c_margins[id][:mr]
            mt = c_margins[id][:mt]
            mb = c_margins[id][:mb]

            cy = curr_y + mt
            
            c_align = c["layout"]&.[]("align") || c["layout"]&.[]("alignment") || c["style"]&.[]("align") || c["style"]&.[]("alignment") || parent_align
            avail_cross = [0.0, inner_w - (ml + mr)].max
            if layout_type == "row" || layout_type == "column"
              cw = [cw, avail_cross].min
            end
            cx = case c_align.to_s
                  when "center" then inner_x + ml + (avail_cross - cw) / 2.0
                  when "end" then inner_x + ml + (avail_cross - cw)
                  else inner_x + ml
                  end

            @computed_boxes[id] = { x: cx.round, y: cy.round, w: cw.round, h: ch.round }
            resolve_node_and_descendants!(c, @computed_boxes[id], parent_to_children)

            curr_y += mt + ch + mb + gap
          end
        end

      else # absolute layout
        visible_children.each do |child|
          child_layout = child["layout"] || {}
          child_style = child["style"] || {}
          
          ox = child_layout["x"] || 0
          oy = child_layout["y"] || 0

          c_margin = child_style["margin"] || 0
          c_margin_left = c_margin.is_a?(Hash) ? (c_margin["left"] || 0) : c_margin
          c_margin_top = c_margin.is_a?(Hash) ? (c_margin["top"] || 0) : c_margin

          cw = resolve_dimension(child_style["width"] || child_style["w"], w)
          ch = resolve_dimension(child_style["height"] || child_style["h"], h)

          cx = x + pl + c_margin_left + ox
          cy = y + pt + c_margin_top + oy

          @computed_boxes[child["id"]] = { x: cx.round, y: cy.round, w: cw.round, h: ch.round }
          resolve_node_and_descendants!(child, @computed_boxes[child["id"]], parent_to_children)
        end
      end
    end

    def resolve_dimension(val, parent_dim)
      case val
      when Numeric
        val
      when String
        if val.end_with?("%")
          percent = val.to_f / 100.0
          (parent_dim * percent).round
        else
          parent_dim
        end
      else
        parent_dim
      end
    end
  end
end
