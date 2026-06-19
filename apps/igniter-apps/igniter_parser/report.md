# Igniter Self-Hosted Parser: Architecture & Pressure Report

Building the metacircular parser for Igniter exposed the challenges of writing compiler infrastructure in a language lacking loops and recursive data types.

## 1. Flat AST Arena Pattern
Because Igniter relies strictly on finite structural type sizes, deeply nested recursive types (`type AstNode { children: Collection[AstNode] }`) are structurally problematic and generally unsupported across similar languages without pointer indirection.
- **Solution**: We implemented an **Arena-based AST**. All nodes are stored sequentially in a flat `Collection[AstNode]` inside `ParserState`, and relationships are maintained via `children_ids: Collection[String]`. This is extremely memory-safe, aligns with data-oriented design (DOD) principles, and successfully compiled (`parse: ok`).

## 2. Simulating Loops in Lexical Analysis
Lexers and Parsers typically rely on tight `while` loops to consume characters. Igniter has absolutely no looping constructs (only mapping over Collections and tail recursion).
- **Finding**: We had to architect `LexerState` and `ParserState` to be passed immutably into discrete single-step contracts (`LexNextToken`, `ParseModuleDecl`). In a real implementation, `api.ig` would need to map over a pre-allocated collection (e.g., an array of indices `[0..length(source)]`) to repeatedly fold the state and consume the string, or use deep contract recursion.

## 3. String Manipulation
As observed, Igniter currently completely lacks string manipulation operations. We bypassed this by asserting the future existence of `char_at` and `substring`. For a fully self-hosted compiler, a robust `stdlib.string` package with byte-level access is absolutely mandatory.

## 4. `call_contract` Locality strictness
Our attempt to `call_contract("empty")` in `api.ig` yielded `unknown callee 'empty' — not found in this module` during typechecking. This confirms that `call_contract` string resolution enforces strict lexical locality. If a module does not define or explicitly import the named contract, it cannot be invoked dynamically! This is a fantastic safety guarantee.
