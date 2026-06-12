module ParserCore
import ParserTypes

contract ParseModuleDecl {
  input state : ParserState
  
  -- Simulates parsing a "module Name" declaration from tokens
  -- We create a flat AST Node and insert it into the arena.
  
  compute empty_children = call_contract("empty")
  
  compute module_node = {
    id: "node-1",
    kind: "ModuleDecl",
    text: "ParsedModule",
    children_ids: empty_children
  }
  
  compute new_nodes = call_contract("append", state.nodes, module_node)
  
  compute new_state = {
    tokens: state.tokens,
    pos: state.pos + 2,
    nodes: new_nodes,
    root_id: "node-1"
  }
  
  output new_state : ParserState
}
