# Ch2 Appendix: EBNF Grammar Specification

This appendix defines the formal EBNF (Extended Backus-Naur Form) grammar for `igniter-lang`, extracted directly from the parser implementation of the reference compiler toolchain.

---

## 1. Syntax Notation

- Symbols in double quotes `""` represent literal terminal tokens (keywords, operators).
- Syntax options are separated by the pipe character `|`.
- Optional constructs are enclosed in parentheses followed by a question mark `()?` or brackets `[]`.
- Zero-or-more repetitions are enclosed in parentheses followed by an asterisk `()*`.
- One-or-more repetitions are enclosed in parentheses followed by a plus `()+`.

---

## 2. Program Structure

```ebnf
SourceFile      ::= ModuleDecl? ImportDecl* TopDecl*

ModuleDecl      ::= "module" ModPath
ImportDecl      ::= "import" ModPath ("." "{" Name ("," Name)* "}")?
ModPath         ::= Name ("." Name)*

TopDecl         ::= AssumptionsDecl
                  | ContractDecl
                  | TypeDecl
                  | FunctionDecl
                  | ExternalDecl
                  | TraitDecl
                  | ImplDecl
                  | ContractShapeDecl
                  | PipelineDecl
                  | OlapPointDecl
```

---

## 3. Top-Level Declarations

### 3.1 Traits & Polymorphism
```ebnf
TraitDecl         ::= "trait" Name ("[" TypeParams "]")? "{" TraitMethod* "}"
TypeParams        ::= Name ("," Name)*
TraitMethod       ::= "def" Name "(" Params? ")" "->" TypeRef

ImplDecl          ::= "impl" QualifiedRef "[" TypeRef "]" "using" QualifiedRef
QualifiedRef      ::= Name ("." Name)*

ContractShapeDecl ::= "contract_shape" Name ("[" TypeParams "]")? "{" ShapeBodyDecl* "}"
ShapeBodyDecl     ::= InputDecl | OutputDecl
```

### 3.2 Assumptions
```ebnf
AssumptionsDecl   ::= "assumptions" "{" AssumptionDecl* "}"
AssumptionDecl    ::= "assumption" Name "{" AssumptionField* "}"
AssumptionField   ::= "kind" ":" AssumptionKind
                    | "statement" StrLiteral
                    | "strength" FloatLit
                    | "source" StrLiteral
AssumptionKind    ::= ":heuristic" | ":empirical" | ":synthetic" | ":calibrated"
```

### 3.3 Pipelines & OLAP
```ebnf
PipelineDecl      ::= "pipeline" Name "[" TypeRef "," TypeRef "," TypeRef "]" "{" StepDecl* "}"
StepDecl          ::= "step" Name ":" QualifiedRef

OlapPointDecl     ::= "olap_point" Name "{" OlapClause* "}"
OlapClause        ::= "dimensions" ":" "{" (Name ":" TypeRef ("," Name ":" TypeRef)*)? "}"
                    | "measure" ":" TypeRef
                    | "granularity" ":" "{" (Name ":" Symbol ("," Name ":" Symbol)*)? "}"
                    | "source" ":" RawExpr
                    | "indexed" ":" "{" (Name ("," Name)*)? "}"
```

### 3.4 Contracts
```ebnf
ContractDecl      ::= "contract" Name ("[" ContractTypeParams "]")? ("implements" QualifiedRef ("[" TypeRef "]")?)? "{" BodyDecl* "}"
ContractTypeParams::= ContractTypeParam ("," ContractTypeParam)*
ContractTypeParam ::= Name ":" QualifiedRef
```

---

## 4. Contract Body Declarations

```ebnf
BodyDecl          ::= InputDecl
                    | OutputDecl
                    | ReadDecl
                    | ComputeDecl
                    | SnapshotDecl
                    | WindowDecl
                    | UsesAssumptionsDecl
                    | EscapeDecl
                    | InvariantDecl
                    | StreamDecl
                    | FoldStreamDecl

InputDecl         ::= "input" Name ":" TypeRef
OutputDecl        ::= "output" Name ":" TypeRef LifecycleAnn? EvidenceAnn?
ReadDecl          ::= "read" Name ":" TypeRef "from" StrLiteral ReadModifier*
ComputeDecl       ::= "compute" Name "=" Expr
SnapshotDecl      ::= "snapshot" Name "=" Expr LifecycleAnn?
WindowDecl        ::= "window" StrLiteral "{" WindowOpt* "}"
UsesAssumptionsDecl::= "uses" "assumptions" Name
EscapeDecl        ::= "escape" Name
InvariantDecl     ::= "invariant" Name "{" InvariantAttr* "}"
StreamDecl        ::= "stream" Name ":" TypeRef
FoldStreamDecl    ::= "fold_stream" Name "=" Expr StreamBound?

ReadModifier      ::= "lifecycle" LifecycleClass
                    | "scoped_by" Name
                    | "cardinality" Cardinality
                    | "schema_version" StrLiteral
                    | "tenant_free"

Cardinality       ::= IntLit ".." IntLit
LifecycleAnn      ::= "lifecycle" LifecycleClass
LifecycleClass    ::= ":local" | ":session" | ":window" | ":durable" | ":audit"
EvidenceAnn       ::= "evidence" "[" Name ("," Name)* "]"

WindowOpt         ::= ("kind" | "unit" | "on_close") ":" Name
StreamBound       ::= "@window_bounded" | "@count_bounded" "(" IntLit ")"

InvariantAttr     ::= "predicate" ":" Name
                    | "severity" ":" Symbol
                    | "label" ":" (StrLiteral | Name)
                    | "message" ":" (StrLiteral | Name)
                    | "overridable_with" ":" (Symbol | Name)
```

---

## 5. Types & Signatures

```ebnf
TypeRef           ::= "Integer" | "Float" | "String" | "Bool" | "Timestamp" | "Date" | "Symbol"
                    | Name
                    | "Collection[" TypeRef "]"
                    | "Option[" TypeRef "]"
                    | "Result[" TypeRef "," TypeRef "]"
                    | "Map[" TypeRef "," TypeRef "]"
```

---

## 6. Expressions

```ebnf
Expr              ::= Literal
                    | Ref
                    | BinOp
                    | Call
                    | IfExpr
                    | BlockExpr
                    | FieldAccess
                    | IndexAccess
                    | Lambda
                    | ArrayLit
                    | RecordLit
                    | LetExpr

Literal           ::= IntLit | FloatLit | StrLiteral | BoolLit | NilLit
Ref               ::= Name
BinOp             ::= Expr Op Expr
Op                ::= "+" | "-" | "*" | "/" | "==" | "!=" | "<" | ">" | "<=" | ">="
                    | "&&" | "||" | "++"
Call              ::= Name "(" (Expr ("," Expr)*)? ")"
IfExpr            ::= "if" Expr BlockExpr ("else" BlockExpr)?
BlockExpr         ::= "{" Stmt* Expr "}"
Lambda            ::= "(" Params? ")" "->" Expr | Name "->" Expr
FieldAccess       ::= Expr "." Name
IndexAccess       ::= Expr "[" Expr "]"
ArrayLit          ::= "[" (Expr ("," Expr)*)? "]"
RecordLit         ::= "{" (Name ":" Expr ("," Name ":" Expr)*)? "}"
LetExpr           ::= "let" Name "=" Expr

Stmt              ::= "let" Name "=" Expr
Params            ::= Param ("," Param)*
Param             ::= Name ":" TypeRef
```
