# igniter-lab/igniter-view-engine/fixtures/interactive_panel.rb

require_relative '../lib/parser_builder'

module IgniterView
  module Fixtures
    def self.interactive_panel(diagnostics)
      builder = ParserBuilder.new(diagnostics)

      builder.instance_eval do
        div(class: "interactive-panel-container p-6 bg-ink-2 border-line rounded-lg") do
          ui_state(:active_tab, "overview")

          div(class: "tabs-list flex gap-2 border-b border-line pb-2") do
            # Tab 1: Overview
            button(class: "tab-btn px-4 py-2 text-xs font-mono rounded-t transition-colors") do
              node_param(:id, "overview")
              display_rule([
                "style",
                ["eq", ["ui_state", "active_tab"], ["param", "id"]],
                { c: "bg-ignite text-ink-1 font-bold", a: { selected: true } },
                { c: "text-grey hover:text-warm-3", a: { selected: false } }
              ])
              interaction_rule("click", [
                ["set_ui_state", "active_tab", ["param", "id"]]
              ])
              text "Overview"
            end

            # Tab 2: Logs
            button(class: "tab-btn px-4 py-2 text-xs font-mono rounded-t transition-colors") do
              node_param(:id, "logs")
              display_rule([
                "style",
                ["eq", ["ui_state", "active_tab"], ["param", "id"]],
                { c: "bg-ignite text-ink-1 font-bold", a: { selected: true } },
                { c: "text-grey hover:text-warm-3", a: { selected: false } }
              ])
              interaction_rule("click", [
                ["set_ui_state", "active_tab", ["param", "id"]]
              ])
              text "Execution Logs"
            end
          end

          # Tab content panels
          div(class: "tab-content mt-4 p-4 bg-ink-1 border border-line rounded") do
            # Overview Panel content
            div(class: "panel-overview p-2") do
              display_rule([
                "style",
                ["eq", ["ui_state", "active_tab"], "overview"],
                { c: "block" },
                { c: "hidden" }
              ])
              h2 "Overview Panel", class: "text-amber font-mono text-sm mb-2"
              p "This is the overview of contract evaluation nodes. Everything is healthy.", class: "text-grey-2 text-xs"
            end

            # Logs Panel content
            div(class: "panel-logs p-2") do
              display_rule([
                "style",
                ["eq", ["ui_state", "active_tab"], "logs"],
                { c: "block" },
                { c: "hidden" }
              ])
              h2 "Execution Logs", class: "text-amber font-mono text-sm mb-2"
              p "No recent errors. Cache hits: 98%. Invalidation triggers: 0.", class: "text-grey-2 text-xs"
            end
          end
        end
      end

      builder.get_nodes.first
    end
  end
end
