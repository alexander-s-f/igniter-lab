# igniter-lab/igniter-view-engine/fixtures/data_driven_list.rb

require_relative '../lib/parser_builder'

module IgniterView
  module Fixtures
    def self.data_driven_list(diagnostics, items)
      builder = ParserBuilder.new(diagnostics)
      
      builder.instance_eval do
        div(class: "list-container space-y-4 my-8") do
          h2 "Contract Verification List", class: "text-grey-3 font-mono text-xl mb-4"
          
          render_each(items) do |item|
            div(class: "contract-card reg p-4 bg-ink-2 mb-4") do
              div(class: "tr")
              div(class: "bl")
              
              div(class: "flex justify-between items-center") do
                span item[:name], class: "text-ignite font-bold font-mono text-lg"
                span "ID: ##{item[:id]}", class: "text-grey font-mono text-xs"
              end
              
              p item[:description], class: "text-grey-2 text-sm my-2"
              
              # Escaped content check (VDSL-5)
              div(class: "my-2 p-2 bg-ink-1 rounded border border-line") do
                span "Escaped string test (default): ", class: "text-grey text-xs block"
                span item[:escaped_test], class: "text-no font-mono text-xs"
              end
              
              # Raw HTML content check (VDSL-6)
              div(class: "my-2 p-2 bg-ink-1 rounded border border-line") do
                span "Raw HTML string test (explicit): ", class: "text-grey text-xs block"
                span item[:raw_test], class: "text-ok font-mono text-xs"
              end
            end
          end
        end
      end
      
      builder.get_nodes.first
    end
  end
end
