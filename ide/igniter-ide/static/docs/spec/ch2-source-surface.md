# Ch2: Source Surface and Grammar

Source PROPs: PROP-014, PROP-015; PROP-032 (bounded assumptions surface)
Status: accepted (grammar kernel); partial (OOF rejection at parse time); PROP-032 experiment-pass for compiler surface only
Proof: experiments/parser/ ��� 61 specs, add.ig + availability_projection.ig + polymorphic_add.ig

---

## 2.1 Guiding Constraints (PROP-014 ��Guiding Constraints)

```
C-1  Syntax must map directly to SemanticIR node types.
     No syntax without a SemanticIR equivalent.
C-2  Every construct must declare its observable properties at source level.
     No implicit defaults hiding semantic choices.
C-3  The source language must be human-writable.
C-4  The source language must be agent-readable.
C-5  Parser output (ParsedProgram) is a stable JSON boundary.
     All downstream passes consume ParsedProgram, not raw source.
```

**Decision**: SemanticIR is the stable toolchain center. The parser is a frontend
pass that emits ParsedProgram. It does not own evaluation, lifecycle, or runtime.

---

## 2.2 Grammar Kernel v0 BNF (PROP-015 ��Part 4)

```text
SourceFile    := ModuleDecl? ImportDecl* TopDecl*

ModuleDecl    := "module" ModPath
ImportDecl    := "import" ModPath ("." "{" Name ("," Name)* "}")?
ModPath       := Name ("." Name)*

TopDecl       := AssumptionsDecl | ContractDecl | TypeDecl | FunctionDecl | ExternalDecl

AssumptionsDecl := "assumptions" "{" AssumptionDecl* "}"
AssumptionDecl  := "assumption" Name "{" AssumptionField* "}"
AssumptionField := "kind" ":" AssumptionKind
                 | "statement" StrLiteral
                 | "strength" FloatLit
                 | "source" StrLiteral
AssumptionKind  := ":heuristic"|":empirical"|":synthetic"|":calibrated"

ContractDecl  := "contract" Name "{" BodyDecl* "}"
BodyDecl      := EscapeDecl | InputDecl | ReadDecl | ComputeDecl
               | SnapshotDecl | WindowDecl | UsesAssumptionsDecl | OutputDecl

EscapeDecl    := "escape" Name
InputDecl     := "input" Name ":" TypeRef
ReadDecl      := "read"  Name ":" TypeRef "from" StrLiteral LifecycleAnn?
ComputeDecl   := "compute" Name "=" Expr
SnapshotDecl  := "snapshot" Name "=" Expr LifecycleAnn?
WindowDecl    := "window" StrLiteral "{" WindowOpt* "}"
WindowOpt     := ("kind" | "unit" | "on_close") ":" Name
UsesAssumptionsDecl := "uses" "assumptions" Name
OutputDecl    := "output" Name ":" TypeRef LifecycleAnn? EvidenceAnn?
EvidenceAnn   := "evidence" "[" Name ("," Name)* "]"
LifecycleAnn  := "lifecycle" LifecycleClass
LifecycleClass:= ":local"|":session"|":window"|":durable"|":audit"

TypeDecl      := "type" Name "{" FieldDecl* "}"
FieldDecl     := Name ":" TypeRef "?"?

FunctionDecl  := "def" Name "(" Params? ")" "->" TypeRef "{" Body "}"
Params        := Param ("," Param)*
Param         := Name ":" TypeRef
Body          := Stmt* Expr
Stmt          := "let" Name "=" Expr

ExternalDecl  := "external" LangId Name "{" ExternalOpt* "}"
LangId        := "ruby" | "rust" | "js" | "wasm"

TypeRef       := "Integer"|"Float"|"String"|"Bool"|"Timestamp"|"Date"|"Symbol"
               | Name
               | "Collection[" TypeRef "]"
               | "Option["     TypeRef "]"
               | "Result["     TypeRef "," TypeRef "]"
               | "Map["        TypeRef "," TypeRef "]"

Expr          := Literal | Ref | BinOp | Call | IfExpr | BlockExpr
               | FieldAccess | IndexAccess | Lambda | ArrayLit | RecordLit
               | LetExpr

Literal       := IntLit | FloatLit | StrLiteral | BoolLit | NilLit
BinOp         := Expr Op Expr
Op            := "+" | "-" | "*" | "/" | "==" | "!=" | "<" | ">" | "<=" | ">="
               | "&&" | "||" | "++"
Call          := Name "(" (Expr ("," Expr)*)? ")"
IfExpr        := "if" Expr "{" Expr "}" ("else" "{" Expr "}")?
  -- Note: the parser accepts the tolerant shape above. V0 accepted semantics
  -- require else; a missing else produces OOF-IF2, not a parse error.
  -- Branch bodies are BlockExpr-shaped (Stmt* + final Expr), not bare Expr.
  -- See ��2.2.3 for the accepted v0 source shape and required-else grammar.
BlockExpr     := "{" Stmt* Expr "}"
Lambda        := "(" Params? ")" "->" Expr | Name "->" Expr
FieldAccess   := Expr "." Name
IndexAccess   := Expr "[" Expr "]"
ArrayLit      := "[" (Expr ("," Expr)*)? "]"
RecordLit     := "{" (Name ":" Expr ("," Name ":" Expr)*)? "}"
LetExpr       := "let" Name "=" Expr   -- inside Body only
```

**Note**: This is NOT a final grammar. It is the minimal syntax kernel
sufficient to produce SemanticIR for the two canonical fixture contracts
(Add, AvailabilityProjection). Full grammar is a separate track.

## 2.2.1 Entrypoint and Section Disposition (Stage 3 Candidate)

`entrypoint` and `section` are not part of Grammar Kernel v0. They are Stage 3
proposal candidates routed by syntax-pressure review, not current canonical
syntax and not parser-supported declarations.

Current source authors and proof fixtures should treat `contract` as the
canonical computation boundary. Tooling that needs to choose what to compile or
evaluate must use explicit invocation metadata, CLI/API arguments, or fixture
metadata until an accepted PROP defines source-level entry selection.

The current parser does not reserve `entrypoint` or `section` as hard keywords.
Pressure fixtures may use those spellings to test human/agent comprehension,
but those fixtures are non-canon and are not expected to parse.

Collision risks for a future PROP:

- `entrypoint` already has package/API meaning in compiler tooling, while a
  source-level `entrypoint` could mean default contract, default output,
  evaluation target, UI route, scheduler trigger, or fixture start. A PROP must
  choose one meaning and name diagnostics around that choice.
- `section` must not accidentally become `module`, namespace, visibility,
  lifecycle, dependency, or evaluation-order syntax. If promoted, its default
  recommended semantics are grouping-only with explicit flattening into normal
  top-level declarations.
- Reserving either spelling too early would collide with ordinary identifiers
  without a proven AST shape. Keyword reservation belongs in the future PROP,
  not in this spec sync.

## 2.2.3 Expression-Level if_expr v0 (R190 Internal Compiler Support)

R190 accepts expression-level `if_expr` as internal compiler support
(TypeChecker + typed SemanticIR lowering). Parser support already existed;
no new parser syntax is added.

Accepted v0 source shape:

```igniter
compute result = if condition { then_expr } else { else_expr }
```

Accepted v0 grammar (required-else form for spec purposes):

```text
IfExpr   := "if" Expr BlockExpr "else" BlockExpr
BlockExpr := "{" BlockBody "}"
BlockBody := Stmt* Expr
```

Branch bodies are `BlockExpr`-shaped (`Stmt*` followed by a final `Expr`), not
bare expressions. The tolerant parser BNF in ��2.2 uses `BlockExpr := "{" Stmt* Expr "}"`,
which subsumes this correctly. The `Stmt* Expr` structure means branches may
contain leading `let` bindings, but the final `Expr` is the value-producing
expression that the TypeChecker reads as the branch result.

Parsed AST shape:

```json
{ "kind": "if_expr", "cond": "<condition expr>", "then": "<BlockBody>", "else": "<BlockBody>" }
```

Where each `BlockBody` is:

```json
{ "stmts": [], "return_expr": "<final Expr or null>" }
```

V0 accepted semantics:

- `else` is required; a missing `else` is not accepted source semantics
  and produces `OOF-IF2` (not a parse error ��� the parser emits `else: null`
  to allow TypeChecker rejection).
- Condition must resolve to canonical Bool `{"name":"Bool","params":[]}`.
- Then/else branch `return_expr` must both exist (non-null) and resolve to
  the same type; see Ch3 ��3.6.
- Nested `if_expr` follows the same rules at every nesting level.

Non-claims for this surface:

```text
runtime/lazy branch execution is not claimed;
else-if / multi-branch sugar is not supported;
branch-local declaration scoping beyond BlockExpr is not added;
statement-level if is not supported;
public API/CLI is not widened by this surface.
```

## 2.2.2 Assumptions Surface (PROP-032 Experiment-Pass)

PROP-032 adds a bounded compiler surface:

```igniter
assumptions {
  assumption homophily {
    kind      :heuristic
    statement "People with similar beliefs interact more often."
    strength  0.70
  }
}

observed contract ScoreInteraction {
  uses assumptions homophily
  output score: Decimal[4] evidence [homophily]
}
```

The accepted source surface is limited to:

- one top-level `assumptions {}` block per module;
- named `assumption NAME { ... }` declarations;
- body-level `uses assumptions NAME` declarations;
- passive parsing of `output ... evidence [...]` lists.

Compiler status: experiment-pass by S3-R36-C2-A for parser, classifier,
TypeChecker, and SemanticIR propagation. P28 unnamed-assumption rejection is part
of this surface. OOF-A1 undeclared-assumption detection and TASSUMP-1 strength
checks are compiler diagnostics, not runtime behavior.

Explicit exclusions: PROP-033 evidence-list validation, runtime receipt
`assumption_refs`, runtime injection of assumption values, cross-module
assumption sharing, constraints/form/effect-surface behavior, and production
RuntimeMachine behavior are not authorized by this Ch2 sync.

---

## 2.3 ParsedProgram Shape (PROP-014 ��Part 3, PROP-018 ��Part 2)

The parser emits a stable JSON structure:

```json
{
  "kind": "parsed_program",
  "grammar_version": "0.1.0",
  "source_path": "source/add.ig",
  "source_hash": "sha256:<hex>",
  "module": "Lang.Examples.Add",
  "assumptions": [],
  "imports": [],
  "types": [],
  "functions": [],
  "contracts": [
    {
      "kind": "contract",
      "name": "Add",
      "escapes": [],
      "inputs": [
        { "kind": "input_decl", "name": "a", "type": "Integer" },
        { "kind": "input_decl", "name": "b", "type": "Integer" }
      ],
      "reads": [],
      "computes": [
        { "kind": "compute_decl", "name": "sum",
          "expr": { "kind": "call", "fn": "stdlib.numeric.add",
                    "args": [{"kind":"ref","name":"a"}, {"kind":"ref","name":"b"}] } }
      ],
      "outputs": [
        { "kind": "output_decl", "name": "result", "type": "Integer",
          "expr": { "kind": "ref", "name": "sum" } }
      ]
    }
  ]
}
```

**ParsedProgram is a stable boundary**: all downstream passes (classifier,
typechecker, emitter) consume ParsedProgram JSON, never raw source.

PROP-032-compatible ParsedProgram adds top-level `assumptions: []` when no
assumptions are declared, `uses_assumptions` body nodes for explicit assumption
dependencies, and parsed-only `evidence: [...]` on output nodes when present.
Validation of evidence-list membership and runtime receipt propagation remain
PROP-033 or later work.

---

## 2.4 def Blocks (PROP-015 ��Part 1)

User-defined functions via `def`:

```
def clamp(value: Float, lo: Float, hi: Float) -> Float {
  if value < lo { lo }
  else { if value > hi { hi } else { value } }
}
```

**Semantic rules**:
- Non-recursive (self-reference is OOF-F1)
- Pure: no reads, no effects, no ambient state
- Inlined at the call site in SemanticIR (no lambda node in emitted IR)
- Scope: module-level or contract-local

---

## 2.5 TypeDecl (PROP-015 ��Part 2)

User-defined structural record types:

```
type ProductRef {
  id:   Integer
  sku:  String
  name: String?
}
```

**Semantic rules**:
- Structural (not nominal): two types with identical fields are compatible
- Optional fields (`?`) map to `Option[T]` in TypeEnv
- TypeDecl produces a named entry in the program's TypeEnv

---

## 2.6 Module System (PROP-015 ��Part 3)

```
module Lang.Examples.Add
import Lang.Stdlib.{ fold, map, filter }
```

**Resolution rules**:
- Module path = dotted name, no filesystem path inference
- Import resolution is compile-time only
- Circular imports are OOF-M1
- Unknown import is OOF-M2

---

## 2.7 OOF Rules at Parse Stage

```
OOF-G1  Unrecognized keyword at top level
OOF-G2  Missing type annotation on input/output
OOF-G3  Malformed lifecycle class (not in LifecycleClass set)
OOF-F1  Recursive def (self-reference)
OOF-M1  Circular import
OOF-M2  Unknown import path
```

**Implementation gap**: The current parser (experiments/parser/) does not
yet reject all OOF-G constructs at parse time. This is a known Stage 1 gap.
