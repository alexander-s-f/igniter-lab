module ParserTypes

type Token {
  kind : String
  text : String
  line : Integer
}

-- Arena-based AST Node
type AstNode {
  id : String
  kind : String
  text : String
  children_ids : Collection[String]
}

type LexerState {
  source : String
  pos : Integer
  line : Integer
  tokens : Collection[Token]
}

type ParserState {
  tokens : Collection[Token]
  pos : Integer
  nodes : Collection[AstNode]
  root_id : String
}
