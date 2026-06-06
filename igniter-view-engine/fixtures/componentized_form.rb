# igniter-lab/igniter-view-engine/fixtures/componentized_form.rb

require_relative '../lib/parser_builder'

module IgniterView
  module Fixtures
    def self.componentized_form(diagnostics, show_admin_controls, action_submitted)
      builder = ParserBuilder.new(diagnostics)
      
      builder.instance_eval do
        div(class: "form-and-toolbar space-y-6 my-8") do
          h2 "System Control Center", class: "text-grey-3 font-mono text-xl mb-4"
          
          # Direct component invocation (VDSL-3)
          ToolbarComponent(title: "Operator Options", class: "flex items-center space-x-2") do
            button "Verify Receipts", class: "bg-line hover:bg-line-2 text-grey-3 font-mono text-xs px-3 py-1 rounded"
            button "Compile Graph", class: "bg-line hover:bg-line-2 text-grey-3 font-mono text-xs px-3 py-1 rounded"
          end
          
          # Forms-assisted component invocation (VDSL-9)
          form :ActionForm, action: "/deploy", method: "POST" do
            div(class: "form-group mb-4") do
              label "Contract Input Specification (JSON):", class: "text-grey text-xs block mb-1 font-mono"
              textarea "{ \"tenant_id\": 42 }", class: "w-full h-24 bg-ink-3 border border-line text-grey-3 p-2 font-mono text-xs rounded"
            end
            
            # Conditional rendering of admin options (VDSL-7)
            render_if(show_admin_controls) do
              div(class: "admin-panel border border-amber p-3 rounded mb-4 bg-ink-2") do
                span "Privileged Action Options", class: "text-amber font-mono text-xs block mb-2"
                div(class: "flex items-center") do
                  input(type: "checkbox", id: "skip_invariants", class: "mr-2")
                  label "Skip compile-time invariants (UNSAFE)", for: "skip_invariants", class: "text-grey-2 text-xs font-mono"
                end
              end
            end
            
            button "Execute Contract", type: "submit", class: "bg-ignite hover:bg-ember text-ink-1 font-bold font-mono text-sm px-4 py-2 rounded"
          end
          
          # Conditional rendering of success banner (VDSL-7)
          render_if(action_submitted) do
            div(class: "notification-banner border border-ok p-3 rounded bg-ink-1 text-ok text-xs font-mono") do
              text "Verification completed successfully. Trace output available in diagnostics."
            end
          end
        end
      end
      
      builder.get_nodes.first
    end
  end
end
