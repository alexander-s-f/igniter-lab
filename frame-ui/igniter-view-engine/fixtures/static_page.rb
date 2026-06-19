# igniter-lab/igniter-view-engine/fixtures/static_page.rb

require_relative '../lib/parser_builder'

module IgniterView
  module Fixtures
    def self.static_page(diagnostics)
      builder = ParserBuilder.new(diagnostics)
      
      # We evaluate the DSL block to build a static view tree
      builder.instance_eval do
        div(class: "ig-field p-8 border-line rounded-lg") do
          div(class: "reg p-6 bg-ink-1") do
            # Corner ticks for registration frame
            div(class: "tr")
            div(class: "bl")
            
            span(class: "kicker") do
              text "STATIC SPECIMEN"
              span(".", class: "text-ignite")
            end
            
            h1 "A language that shows its work", class: "text-grey-3 font-mono text-3xl my-4"
            bind_slot(:title_slot, "namespaces/axioms/title", :string, :text, "A language that shows its work")
            
            p "Igniter contracts define business logic as immutable dependency graphs. Every execution produces a cryptographically verified evidence receipt.", class: "text-grey-2 text-sm leading-relaxed"
            bind_slot(:description_slot, "namespaces/axioms/desc", :string, :text, "Fallback text for description")
            
            div(class: "mt-6 border-t border-line pt-4") do
              span "Core Axiom 1 — Honesty", class: "text-amber font-mono text-xs block"
              span "A program is an honest account of what it does to the world.", class: "text-grey text-xs"
            end
          end
        end
      end
      
      builder.get_nodes.first
    end
  end
end
