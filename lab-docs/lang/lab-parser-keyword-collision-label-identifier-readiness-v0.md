# LAB-PARSER-LABEL-IDENTIFIER-P1 — Parser Keyword Collision Readiness Proof

**Track:** parser-label-identifier-keyword-collision-v0
**Route:** LAB PROOF / READINESS / NO PARSER IMPLEMENTATION
**Status:** CLOSED — PROVED 60/60 PASS
**Date:** 2026-06-12
**Triggered by:** APP-RECHECK-WAVE-P1 decision_tree gap DT-P02

---

## 1. Research Question

Is `label` a reserved keyword in the Ruby parser, the Rust parser, or both?
Which source positions fail? Does Ruby/Rust behavior diverge?
What is the correct recommended fix route?

**Verdict: ACCEPT — keyword collision in BOTH parsers; Ruby binding positions raise ParseError
(pre-semantic); Rust parses all positions successfully (divergence confirmed).**

---

## 2. Findings

### 2.1 Keyword Registration

`label` is registered in BOTH parsers, in the **invariant-attributes keyword group**:

| Parser | File | Line | Group |
|--------|------|------|-------|
| Ruby | `lib/igniter_lang/parser.rb` | 48 | `invariant predicate severity label message overridable_with` |
| Rust | `igniter-compiler/src/lexer.rs` | 62 | same group |

Both parsers produce token type `:keyword` / `TokenType::Keyword` for `label`.

### 2.2 Ruby–Rust Divergence: `name_token` Design

The root cause is a structural difference between the two parsers' name-reading functions:

**Ruby `name_token!(types)` (parser.rb:378):**
```ruby
def name_token!(types = %i[ident keyword])
  tok = peek
  raise ParseError.new("Expected name, got #{tok.type}(#{tok.value})", ...)
    unless types.include?(tok.type)
  advance.value
end
```
Default is permissive (`%i[ident keyword]`), but **binding-position call sites pass `%i[ident]` only**.

**Rust `name_token()` (parser.rs:720):**
```rust
fn name_token(&mut self) -> Result<String, String> {
  let tok = self.advance()...;
  if tok.token_type == TokenType::Ident || tok.token_type == TokenType::Keyword {
    Ok(tok.value.clone())
  } else { Err(...) }
}
```
Uniformly accepts **both Ident and Keyword in ALL positions**. No restricted call sites.

### 2.3 Position Matrix

| Position | Ruby result | Rust parse stage | Notes |
|---|---|---|---|
| `input label : String` | **ParseError exception** | `ok` | Ruby raises before typechecker |
| `output label : String` | **ParseError exception** | `ok` | Ruby raises before typechecker |
| `compute label = "..."` | **ParseError exception** | `ok` | Ruby raises before typechecker |
| `def f(label: String)` | **ParseError exception** | `ok` | parse_params:1358 |
| `lambda label -> expr` | parse error in errors[] | — | dispatch peek at :ident only |
| `type T { label : String }` | OK | `ok` | parse_type_decl:1323 uses `%i[ident keyword]` |
| `{ label: "x" }` (record literal) | OK | `ok` | parse_record_or_block:2018 uses `%i[ident keyword]` |
| `node.label` (dotted access) | OK | `ok` | parse_postfix:1736 uses `%i[ident keyword]` |

Ruby parse failure mode for binding positions: **hard `raise ParseError`** (not recoverable `errors[]`).
Exception propagates out of `ParsedProgram.parse` — no typechecker is reached.

### 2.4 Ruby Call-site Analysis

Binding positions that use `name_token!(%i[ident])` (keyword-excluded):

| Method | Line | Context |
|---|---|---|
| `parse_input_decl` | 950 | `input <name> :` |
| `parse_output_decl` | 957 | `output <name> :` |
| `parse_compute_decl` | 1031 | `compute <name> =` |
| `parse_params` | 1358 | function param name |
| `parse_let_stmt` | 1388 | `let <name> =` |
| `parse_lambda` | 1816 | multi-param lambda |
| lambda dispatch | 1781 | `peek_type?(:ident) && peek(1)&.type == :arrow` |

Positions that use `name_token!(%i[ident keyword])` (permissive — keywords allowed):

| Method | Line | Context |
|---|---|---|
| `parse_type_decl` | 1323 | type field name |
| `parse_record_or_block` | 2018 | record literal key |
| `parse_postfix` | 1736 | dotted field access |
| `parse_index_slice_record` | 1769 | index slice key |

### 2.5 App Pressure: decision_tree

`igniter-lab/igniter-apps/decision_tree/builder.ig:11`:
```
input label : String
```
Ruby parser raises `ParseError: Expected name, got keyword(label)` — blocked before semantic analysis.

Rust compiler compiles the same file successfully (parse=ok; any failure is semantic only).

### 2.6 Sibling Keyword Risk Matrix

All keywords that would collide in binding positions (same root cause as `label`):

| Word | In KEYWORDS? | Ruby binding fails? |
|---|---|---|
| `label` | YES | YES — DT-P02 app pressure |
| `message` | YES | YES — invariant-attrs group |
| `from` | YES | YES — cycle group |
| `match` | YES | YES — variant group |
| `profile` | YES | YES — profile group |
| `authority` | YES | YES — profile group |
| `lead` | YES | YES — loop group |
| `step` | YES | YES — pipeline group |
| `type` | YES | YES — top-level decl (rarely used as field name) |
| `kind` | NO | Safe |
| `state` | NO | Safe |
| `name` | NO | Safe |
| `when` | NO | Safe |
| `action` | NO | Safe |

---

## 3. Root Cause Summary

Ruby `parse_input_decl`, `parse_output_decl`, `parse_compute_decl`, `parse_params`,
`parse_let_stmt`, and `parse_lambda` all call `name_token!(%i[ident])` — ident-only.
`label` tokenizes as `:keyword`, which fails this type check.

The Rust parser's `name_token()` is uniformly permissive — it accepts any word (keyword or ident)
as a name. This is not a bug in Rust; it is a deliberate "keywords are contextual" design where
the parser recognizes keywords by position rather than by restricting binding names.

---

## 4. Recommended Route

### ACCEPT: LANG-PARSER-CONTEXTUAL-KEYWORDS-P1 (broad)

**Scope:** Systematically change all binding-position `name_token!(%i[ident])` calls in parser.rb
to `name_token!(%i[ident keyword])`, and fix the lambda dispatch condition from `peek_type?(:ident)`
to `peek_type?(:ident) || peek_type?(:keyword)` at line 1781.

**Why broad, not narrow:**
- At minimum 6 sibling keywords fail in the same positions (F-01..F-06 all confirmed)
- A `LANG-PARSER-LABEL-IDENTIFIER-P2` (label-only fix) would still block `message`, `from`, `match`,
  `profile`, `authority`, `lead`, etc. as binding names
- The Rust parser already has the correct behavior — the fix is Ruby parity
- The change is mechanical: ~7 call-site changes in parser.rb

**Affected lines in parser.rb:**
- `parse_input_decl:950` — `name_token!(%i[ident])`
- `parse_output_decl:957` — `name_token!(%i[ident])`
- `parse_compute_decl:1031` — `name_token!(%i[ident])`
- `parse_params:1358` — `name_token!(%i[ident])`
- `parse_let_stmt:1388` — `name_token!(%i[ident])`
- `parse_lambda:1816` — `name_token!(%i[ident])`
- `parse_call_arg:1781` — `peek_type?(:ident)` → `peek_type?(:ident) || peek_type?(:keyword)`

### REJECT: LANG-PARSER-LABEL-IDENTIFIER-P2 (narrow)

Rejected — leaves all sibling keywords broken. Decision_tree's `input label` would work but
any contract with `input message`, `input from`, `input match`, etc. would still fail.

---

## 5. Semantic Safety

The fix is safe. The typechecker validates bindings by name (String value), not by token type.
Making the Ruby parser accept `label` as an input name does not change how the typechecker
resolves or types the binding — it just un-blocks source programs that use common English words.

Expression keywords (`if`, `else`, `let`, `true`, `false`, `nil`, `and`, `or`, `not`) would
technically become valid binding names too. This matches Rust behavior. These words are unlikely
to be used as binding names and the typechecker provides a second line of defense.

---

## 6. Proof Matrix

| Section | Checks | Focus | Result |
|---------|--------|-------|--------|
| A INVENTORY | 6 | Both parsers, keyword group, token type, name_token! signature | PASS |
| B FAILING POSITIONS | 8 | 5 hard ParseError positions + lambda dispatch | PASS |
| C WORKING POSITIONS | 6 | type field, record key, dotted access, call-site evidence | PASS |
| D RUST BEHAVIOR | 8 | Rust name_token() uniform; all 6 positions parse=ok; divergence | PASS |
| E ROOT CAUSE | 6 | ident-only call sites vs Rust uniform; exact lines named | PASS |
| F SIBLING RISK | 8 | 6 sibling keywords fail; kind/state safe | PASS |
| G APP PRESSURE | 4 | decision_tree MakeLeaf inline fixture; failure + Rust OK | PASS |
| H RECOMMENDED ROUTE | 6 | LANG-PARSER-CONTEXTUAL-KEYWORDS-P1 scope + fix description | PASS |
| I AUTHORITY CLOSED | 4 | No impl / no app edits / no policy change | PASS |
| J DECISION | 4 | Verdict / divergence / recommend / reject narrow | PASS |
| **Total** | **60** | | **60/60 PASS** |

---

## 7. Open Work

**LANG-PARSER-CONTEXTUAL-KEYWORDS-P1** (authorized separately):
- Change 6 `name_token!(%i[ident])` call sites to `name_token!(%i[ident keyword])`
- Fix lambda dispatch at line 1781 to accept `:keyword` too
- Regression proof: existing test suite + decision_tree builder.ig + sibling-keyword fixture matrix
- Ruby-first; Rust parity not required (Rust already correct)
- No keyword set changes, no semantic/typechecker changes

**DT-P02 (decision_tree):** Unblocks after LANG-PARSER-CONTEXTUAL-KEYWORDS-P1 closes.
