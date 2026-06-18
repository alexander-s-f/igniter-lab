# Card: LAB-IGNITER-TRANSPILING-RESEARCH-ARCHITECTURE-GEMINI-P1 — Projection dialect transpiling architecture survey

**Lane:** background / research  
**Status:** CLOSED (Research report delivered)  
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-TRANSPILING-A`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Lab research only. No code. No canon. No implementation plan unless explicitly framed as a future card idea.

## Why this card exists

`LAB-IGNITER-PROJECTION-DIALECTS-P0` named `.ig*` files as **Projection Dialects**: authoring
surfaces that deterministically lower into existing inspectable artifacts. We need deeper
transpiling research before turning this into tooling, so this background Gemini agent studies the
architecture of lowerers and target artifacts.

## Read first

- `.agents/work/cards/lang/LAB-IGNITER-PROJECTION-DIALECTS-P0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `igniter-ui-kit/src/igv.rs`
- `igniter-compiler/src/igweb.rs`
- `lab-docs/lang/lab-frame-igv-binding-syntax-p1-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md`

## Goal

Produce one research packet that answers: **what is the right architecture for Igniter projection
dialect lowerers as transpilers, without creating a second language runtime?**

## Questions to research

1. What lowerer shapes exist today in `.igv` and `.igweb`?
2. What should be common across all lowerers: parse phase, AST/IR, validation, lowering, formatting,
   source map, target validation?
3. Should a dialect lower directly to target text/JSON, or through a small dialect-local AST first?
4. What target artifact kinds are legitimate v0 targets: `.ig`, ViewArtifact JSON, manifest JSON,
   capsule metadata?
5. What generated artifact policy is safest: committed generated files, temp generated files, or
   build-cache only?
6. What makes a lowerer deterministic and byte-stable?
7. What invariants should be shared by helper APIs if a future `igniter-dialect` crate exists?
8. What should remain per-dialect and never be centralized?

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-transpiling-research-architecture-gemini-p1-v0.md`

Then update only this card with a closing report.

## Closed surfaces

- Do not edit `.igv`, `.igweb`, compiler, UI, server, machine, VM, or docs other than the one report
  and this card.
- Do not modify P0/P4/P1 proof docs.
- Do not add CLI/config/code.
- Do not claim canon status.
- Do not produce a giant framework proposal; keep it a research packet with concrete future card ideas.

## Acceptance

- [x] Report distinguishes architecture facts from recommendations.
- [x] Report anchors on live `.igv` and `.igweb` lowerers.
- [x] Report proposes a minimal shared lowerer pipeline.
- [x] Report names what should stay dialect-local.
- [x] Report includes 3-5 future card ideas, clearly marked as ideas.
- [x] No code or canon files changed.

---

## Closing report — 2026-06-18

**Outcome:** Completed the architecture survey on Igniter Projection Dialect lowerers, capturing the live implementations (`igv.rs` and `igweb.rs`) and structuring the common pipeline invariants. 

**Deliverable:** `lab-docs/lang/lab-igniter-transpiling-research-architecture-gemini-p1-v0.md`

**Key findings:**
- **Pipeline:** Proposed a 4-phase standard pipeline (Lexer/Tokenizer -> Dialect AST -> Transformation -> Target Emit) with standardized line-positioned diagnostics.
- **Dialect AST:** Recommended that lowerers construct dialect-local AST representations before code generation rather than emitting raw strings/JSON during parsing.
- **Targets:** Legitimate v0 targets verified as `.ig` source code, `ViewArtifact` JSON, and `Manifest/ServiceRecipe` JSON.
- **Generated Code Policy:** Recommended committing generated artifacts directly into source repositories to allow human review, with build caches reserved for ephemeral runtimes.
- **Tooling Backlog (Ideas):** Proposed three future cards: `LAB-IGNITER-DIALECT-CRATE-P1` (shared tokenizer and errors), `LAB-IGNITER-TRANSPILER-SOURCE-MAP-P2` (line tracing), and `LAB-IGNITER-DIALECT-PROJECT-CLI-P3` (workspace compile CLI).

**Verification:** No compiler, server, VM, or UI kit code files were modified. The research report has been written exactly to the specified path.
