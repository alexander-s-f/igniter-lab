module ParserApi
import ParserTypes
import ParserLexer
import ParserCore

contract ParseSource {
  input source : String
  
  compute initial_tokens = call_contract("empty")
  
  compute initial_lexer = {
    source: source,
    pos: 0,
    line: 1,
    tokens: initial_tokens
  }
  
  -- Step 1: Lex a single token
  compute lex_state_1 = call_contract("LexNextToken", initial_lexer)
  
  compute initial_nodes = call_contract("empty")
  
  compute initial_parser = {
    tokens: lex_state_1.tokens,
    pos: 0,
    nodes: initial_nodes,
    root_id: ""
  }
  
  -- Step 2: Parse the tokens into AST Arena
  compute parse_state_1 = call_contract("ParseModuleDecl", initial_parser)
  
  -- Step 3: Extract and return the final AST node collection
  compute final_ast = parse_state_1.nodes
  
  output final_ast : Collection[AstNode]
}
