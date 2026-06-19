module ParserExample
import ParserTypes
import ParserApi

-- Program entry point - zero-input parser demo.
-- This fixture intentionally stays app-side: it supplies sample source text and
-- exercises ParseSource. Full VM success is gated on stdlib.string.char_at
-- runtime support, which is outside this card.
entrypoint RunParseDemo

contract RunParseDemo {
  compute ast = call_contract("ParseSource", "module Demo")
  output ast : Collection[AstNode]
}
