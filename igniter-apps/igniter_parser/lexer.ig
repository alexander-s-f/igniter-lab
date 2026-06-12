module ParserLexer
import ParserTypes
import stdlib.string.{ char_at }

contract LexNextToken {
  input state : LexerState
  
  -- Simulates a single step of a state machine lexer.
  -- In a fully functional language without loops, this would be recursively called.
  compute current_char = char_at(state.source, state.pos)
  
  compute is_keyword_module = if current_char == "m" {
    true
  } else {
    false
  }
  
  compute new_token = {
    kind: "Keyword",
    text: "module",
    line: state.line
  }
  
  -- Avoid inline record parsing bug by using helper contract or direct assignment
  compute next_tokens = if is_keyword_module {
    call_contract("append", state.tokens, new_token)
  } else {
    state.tokens
  }
  
  compute new_state = {
    source: state.source,
    pos: state.pos + 1,
    line: state.line,
    tokens: next_tokens
  }
  
  output new_state : LexerState
}
