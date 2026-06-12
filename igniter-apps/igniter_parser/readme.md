# Igniter Parser (Self-Hosted)

This application is an architectural prototype for a self-hosted Igniter Parser, written entirely in Igniter itself.

## Architecture

1. **`types.ig`**: Defines the `Token`, `AstNode`, `LexerState`, and `ParserState` structures. Due to strict constraints on recursive types, the AST is modeled as a flat "Arena" where `children_ids` point to other nodes in the state array.
2. **`lexer.ig`**: Implements `LexNextToken`, simulating a state machine step without standard `while` loops.
3. **`parser.ig`**: Implements `ParseModuleDecl`, demonstrating how to allocate a new `AstNode` and append it to the `ParserState` arena.
4. **`api.ig`**: The primary entry point (`ParseSource`), orchestrating the lexical and parser contracts in sequence.

## Compilation Test

```bash
cargo run -- compile types.ig lexer.ig parser.ig api.ig
```
