# LAB-PARSER-LABEL-IDENTIFIER-P1 — Parser Keyword Collision Readiness Proof

**Track:** parser-label-identifier-keyword-collision-v0
**Route:** LAB PROOF / READINESS / NO PARSER IMPLEMENTATION
**Status:** CLOSED — PROVED 60/60 PASS
**Date:** 2026-06-12
**Triggered by:** APP-RECHECK-WAVE-P1 (decision_tree DT-P02 — `input label : String` blocked)
**Successor:** LANG-PARSER-CONTEXTUAL-KEYWORDS-P1 (implementation; not yet authorized)

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_parser_label_identifier_p1.rb` | 60/60 PASS |
| Governance doc | `igniter-lab/lab-docs/lang/lab-parser-keyword-collision-label-identifier-readiness-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/lang/LAB-PARSER-LABEL-IDENTIFIER-P1.md` | Written |
| Portfolio | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Headline Findings

1. **`label` is a keyword in BOTH parsers** — Ruby parser.rb:48 and Rust lexer.rs:62, same invariant-attributes group (`invariant predicate severity label message overridable_with`).

2. **Ruby-only parse failure** — Ruby raises a hard `ParseError` exception in 5 binding positions (input, output, compute, function param, let binding) plus lambda dispatch. Rust parser accepts `label` in ALL positions (parse=ok).

3. **Root cause is inconsistent call sites** — Ruby `name_token!` has two call patterns: `%i[ident keyword]` (permissive, used for type fields / record keys / dotted access) and `%i[ident]` (ident-only, used for binding positions). The ident-only sites reject `:keyword` tokens.

4. **Not a label-specific bug** — 6+ sibling keywords (`message`, `from`, `match`, `profile`, `authority`, `lead`, `step`) have the exact same failure pattern. Any of these used as an input/output/compute/param name in Ruby would raise `ParseError`.

5. **Narrow fix rejected** — `LANG-PARSER-LABEL-IDENTIFIER-P2` (label-only) would unblock `label` but leave all siblings broken. The correct scope is `LANG-PARSER-CONTEXTUAL-KEYWORDS-P1`.

---

## Position Matrix

| Position | Ruby | Rust | Line |
|---|---|---|---|
| `input label :` | **ParseError** | parse=ok | 950 |
| `output label :` | **ParseError** | parse=ok | 957 |
| `compute label =` | **ParseError** | parse=ok | 1031 |
| `def f(label: T)` | **ParseError** | parse=ok | 1358 |
| `lambda label ->` | parse error in errors[] | — | 1781 |
| `type T { label : }` | OK | parse=ok | 1323 |
| `{ label: val }` | OK | parse=ok | 2018 |
| `.label` dotted | OK | parse=ok | 1736 |

---

## Sibling Keyword Risk

All fail in Ruby binding positions: `message`, `from`, `match`, `profile`, `authority`, `lead`, `step`, `type`.
Safe (not keywords): `kind`, `state`, `name`, `when`, `action`.

---

## Proof Sections

| Section | Checks | Result |
|---------|--------|--------|
| A INVENTORY | 6 | PASS |
| B FAILING POSITIONS | 8 | PASS |
| C WORKING POSITIONS | 6 | PASS |
| D RUST BEHAVIOR | 8 | PASS |
| E ROOT CAUSE | 6 | PASS |
| F SIBLING RISK | 8 | PASS |
| G APP PRESSURE | 4 | PASS |
| H RECOMMENDED ROUTE | 6 | PASS |
| I AUTHORITY CLOSED | 4 | PASS |
| J DECISION | 4 | PASS |
| **Total** | **60** | **60/60 PASS** |

---

## Recommended Route

**LANG-PARSER-CONTEXTUAL-KEYWORDS-P1** — change 6 ident-only `name_token!(%i[ident])` call sites
in parser.rb to `name_token!(%i[ident keyword])`, plus fix lambda dispatch at line 1781 to also
check `peek_type?(:keyword)`. This achieves Ruby/Rust parity. Mechanical change (~7 lines).

---

## Closed Surfaces

- No parser implementation (parser.rb, lexer.rs untouched)
- No keyword escape syntax
- No keyword set changes
- No decision_tree source edits
- No semantic / typechecker changes
- No canon keyword policy change beyond recommendation
