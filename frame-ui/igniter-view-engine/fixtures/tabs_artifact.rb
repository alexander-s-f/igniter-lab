# frozen_string_literal: true

# igniter-lab/igniter-view-engine/fixtures/tabs_artifact.rb
#
# Minimal ViewArtifact fixture: Tabs component.
# Demonstrates: one UIState, one SlotValue, one node_param,
#               one display rule (style), one interaction rule (on click).
#
# This fixture is the primary lab proof specimen for IVF-P1-11.
# Status: experimental · lab-only · no-canon · no-public-api

require_relative "../lib/view_artifact"
require_relative "../lib/ssr_renderer"

module IgniterView
  module Fixtures
    # Build the ViewArtifact definition for the Tabs component.
    # Returns a frozen ViewArtifact instance (content-addressed).
    def self.tabs_artifact
      ViewArtifact.new(
        view_id: "igniter.lab.tabs_panel",

        # One UIState: which tab is active
        ui_states: {
          "active_tab" => { "type" => "string", "default" => "overview" }
        },

        # One SlotValue: read-only flag from a (hypothetical) contract output
        slots: {
          "has_warnings" => {
            "type"         => "boolean",
            "contract_ref" => "diagnostics.has_warnings",
            "mode"         => "read_only"
          }
        },

        elements: [
          # ── Element: tab_btn ───────────────────────────────────────────────
          # One node_param (id), one display rule, one interaction rule.
          ElementDef.new(
            element_id:         "tab_btn",
            static_classes:     "tab-btn px-4 py-2 text-xs font-mono rounded-t transition-colors",
            node_params_schema: { "id" => "string" },
            display_rules: [
              # style: active tab gets ignite colour + aria-selected=true
              ["style",
               ["eq", ["ui_state", "active_tab"], ["param", "id"]],
               { "c" => "bg-ignite text-ink-1 font-bold",      "a" => { "selected" => "true" } },
               { "c" => "text-grey hover:text-grey-2",          "a" => { "selected" => "false" } }]
            ],
            interaction_rules: [
              # on click: set active_tab to this tab's param.id
              ["on", "click", [["set_ui_state", "active_tab", ["param", "id"]]]]
            ]
          ),

          # ── Element: tab_panel ────────────────────────────────────────────
          # Visibility controlled by UIState.
          ElementDef.new(
            element_id:         "tab_panel",
            static_classes:     "tab-panel p-4 bg-ink-1 border border-line rounded mt-2",
            node_params_schema: { "id" => "string" },
            display_rules: [
              ["style",
               ["eq", ["ui_state", "active_tab"], ["param", "id"]],
               { "c" => "block" },
               { "c" => "hidden" }]
            ],
            interaction_rules: []
          ),

          # ── Element: warning_banner ───────────────────────────────────────
          # Driven by a read-only SlotValue (contract output reference).
          ElementDef.new(
            element_id:         "warning_banner",
            static_classes:     "warning-banner text-xs font-mono px-3 py-2 rounded",
            node_params_schema: {},
            display_rules: [
              ["style",
               ["slot", "has_warnings"],
               { "c" => "block border border-oof bg-oof-5 text-oof" },
               { "c" => "hidden" }]
            ],
            interaction_rules: []
          )
        ],

        non_claims: [
          "lab-only",
          "experimental",
          "no-canon",
          "no-public-api",
          "no-stable-syntax",
          "no-production-readiness",
          "no-reference-runtime",
          "no-portability-guarantee"
        ]
      )
    end

    # Render the Tabs component to a complete, self-contained HTML fragment
    # ready for browser hydration.
    #
    # slot_values:    injected by host (read-only in the view runtime)
    # active_tab:     override initial UIState for SSR (e.g. server-determined)
    def self.tabs_ssr_html(slot_values: { "has_warnings" => false },
                           active_tab: "overview")
      artifact = tabs_artifact
      renderer = SSRRenderer.new(artifact, slot_values: slot_values)
                            .with_ui_state("active_tab" => active_tab)

      tabs    = [{ id: "overview", label: "Overview" },
                 { id: "logs",     label: "Execution Logs" }]
      content = [{ id: "overview", body: "Contract graph: 3 nodes. Cache hits: 98%. No failures." },
                 { id: "logs",     body: "No recent errors. Invalidation triggers: 0." }]

      # Inline artifact JSON so JS runtime needs no network fetch
      artifact_script = renderer.artifact_script_tag

      component_html = renderer.render_root(
        tag: "div",
        extra_attrs: { "class" => "tabs-component p-6 bg-ink-2 border border-line rounded-lg" }
      ) do
        # Tab button bar
        tab_bar = "<div class=\"tabs-list flex gap-2 border-b border-line pb-2\">"
        tabs.each do |tab|
          tab_bar += renderer.render_element(
            "tab_btn",
            node_params: { "id" => tab[:id] },
            tag: "button",
            content: tab[:label]
          )
        end
        tab_bar += "</div>"

        # Warning banner (slot-driven, read-only)
        banner = renderer.render_element("warning_banner", tag: "div",
                                         content: "⚠ Contract output has warnings.")

        # Tab panel content
        panels = ""
        content.each do |pane|
          panels += renderer.render_element(
            "tab_panel",
            node_params: { "id" => pane[:id] },
            tag: "div",
            content: pane[:body]
          )
        end

        tab_bar + banner + panels
      end

      # Return artifact script + component HTML as one fragment
      artifact_script + "\n" + component_html
    end
  end
end
