# igniter-lab/igniter-view-engine/fixtures/malicious_page.rb

require_relative '../lib/parser_builder'

module IgniterView
  module Fixtures
    def self.malicious_page(diagnostics)
      builder = ParserBuilder.new(diagnostics)
      
      builder.instance_eval do
        div(class: "malicious-test p-6 border border-line bg-ink-2") do
          h2 "Security Hardening Specimen", class: "text-grey-3 font-mono text-lg mb-4"
          
          # 1. Blocked tags (VCON-6): script and iframe
          script "alert('XSS execution blocked!')", type: "text/javascript"
          iframe(src: "https://malicious-site.example.com", class: "w-full border-none h-32")
          
          # 2. Blocked event handlers (VCON-6): onclick
          button "Click me (Trigger event)", onclick: "alert('Click event hijacked!')", class: "bg-no text-grey-3 font-mono text-xs px-3 py-1 rounded"
          
          # 3. Blocked javascript: URLs (VCON-6)
          a "Trigger JS Redirect Link", href: "javascript:window.location='http://evil.com'", class: "text-no underline text-xs block mt-2"
          
          # 4. Multi-child style block with spaced/mixed-case url and @import (VEDGE-1, VEDGE-2)
          style do
            # First child
            @children << HtmlNode.new("text", {}, ["body { background: red !important; }"])
            # Second child: remote css import with mixed case
            @children << HtmlNode.new("text", {}, ["@ImPoRt UrL('https://evil.com/leak.css');"])
            # Third child: spaced and mixed case url() function
            @children << HtmlNode.new("text", {}, ["h1 { background: URL   ('javascript:alert(1)'); }"])
          end
          
          # 5. JavaScript in CSS url inside style attribute with spaced url (VEDGE-2)
          div "Div with style injection", style: "background-image: UrL   ('javascript:alert(1)')", class: "my-2"
          
          # 6. Reverse Tabnabbing target='_blank' links (VEDGE-4)
          # Link 6a: no rel attribute
          a "External Link (No Rel)", href: "https://external.com/a", target: "_blank", class: "text-amber underline text-xs block mt-2"
          # Link 6b: pre-existing rel="nofollow" (should merge to "nofollow noopener noreferrer")
          a "External Link (With Rel)", href: "https://external.com/b", target: "_blank", rel: "nofollow", class: "text-amber underline text-xs block mt-2"
          
          # 7. Nested blocked tags (VCON-5/VCON-6): script tag nested inside a safe span
          span(class: "nested-script-container text-xs block mt-2") do
            span "Safe prefix text"
            script "console.log('nested xss')"
          end

          # 8. Nested document-level tag in invalid position (VCON-5): head inside nested div
          div(class: "nested-head-container mt-2") do
            head do
              title "Nested head title"
            end
          end

          # 9. Suspicious protocol URLs and malformed attributes (VEDGE-3)
          a "Suspicious Data URL", href: "data:text/html,<script>alert(1)</script>", class: "text-no block mt-2"
          a "Suspicious VBScript URL", href: "vbscript:msgbox(1)", class: "text-no block mt-2"
          a "Suspicious File URL", href: "file:///etc/passwd", class: "text-no block mt-2"
          a "Link with malformed attributes", href: "https://safe.com", :"xml:lang" => "en-us", class: "text-grey block mt-2"

          # 10. Safe data URI (should NOT be blocked) (VEDGE-3)
          img(src: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==", alt: "Safe Red Dot", class: "mt-2 block")
          
          # Dynamic control showing allowed elements still render
          span "This sibling element is safe and must render normally.", class: "text-grey text-xs block mt-4"
        end
      end
      
      builder.get_nodes.first
    end
  end
end
