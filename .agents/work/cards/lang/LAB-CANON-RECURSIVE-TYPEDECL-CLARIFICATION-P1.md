# LAB-CANON-RECURSIVE-TYPEDECL-CLARIFICATION-P1

Status: CLOSED (clarification packet delivered 2026-06-25)
Route: standard / canon clarification
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-canon-recursive-typedecl-clarification-p1-v0.md`.

**Canon/lab answer:** Canon settles **computation** recursion — no free recursion, managed repetition only
(Covenant law `language-covenant.md:135-138,473`; Ch13 `recur()`/`decreases`; `def` `OOF-F1` `ch2:343`); the
lab enforces it (`OOF-TY0` self-recursion closed). Canon is **SILENT** on **data-shape** recursion (recursive
`TypeDecl`) — `OOF-F1` is computation-only; TypeDecl §2.5 says nothing. **Empirical probe (live lab compiler,
/tmp fixtures): recursive record types are ALREADY ACCEPTED** — `type Node { children:Collection[Node] }` +
field-read → `status: ok`; nested literal construction → `status: ok`; only self-recursive *traversal* →
`status: oof` (`OOF-TY0` "use recur()"). `build_type_shapes` stores shallow refs (no expansion/loop), bounded
by a `tc_infer` depth budget (1000/fatal). So recursive *shapes* work today; recursive *walks* are the closed
computation axis.

**Path correction:** card's canon path `/Users/alex/dev/projects/igniter` has only `docs/{research,current-waves}`
— NO covenant/spec. Real canon = `igniter-workspace/igniter-lang` (cited throughout).

**Recommendation: C now → B as the canon ask.** C (allow host-owned recursive descriptors, `.ig` traversal
closed) is **already de-facto true + bounded** → zero lab change, exact ViewArtifact/HTML fit. B (allow
recursive TypeDecl, traversal managed `recur()`/`decreases` OR bounded host walker) = the principled canon
ratification that unifies data + computation recursion under "declared, bounded, auditable." Rejected A
(breaks working/needed shapes) and D (question recurs; now have clarity).

**Impact on view-engine:** the recursion "collision" is **softer than thought** — recursive types are already
expressible/constructible; the missing piece is the *engine* (deferred `LAB-IGNITER-WEB-VIEW-ENGINE-MODEL-READINESS`),
NOT the type system. **Flat ViewArtifact work continues unchanged** (link node done; bounded list/item next);
a future recursive descriptor is not blocked by the language.

**Next canon-facing action:** route the §7 PROP wording to canon (Ch2 §2.5 + Ch13 addendum) — ratify B, specify
host-walker depth-bound + the `decreases node.children` structural lift. Lab stays evidence-only until canon rules.

**Boundary honored.** No lab/compiler/ViewArtifact change; no spec rewrite (only a proposed wording snippet);
no canon-authority claim. Probes in /tmp (uncommitted). `git diff --check` clean.

## Goal

Clarify canon policy for **recursive data types** (`TypeDecl` self-reference), without changing lab code.

This card exists because recent ViewArtifact / HTML-engine discussions keep touching "recursion", but there
are two different axes:

```text
recursion as computation   -> self-call / loop / repetition
recursion as data shape    -> tree/AST/view node with children
```

Canon already has a strong position on the first axis: no free recursion, no unbounded loop, managed
repetition only. The second axis is the open one.

## Current Authority

Verify first in the canon repo and lab:

- `/Users/alex/dev/projects/igniter`
- `/Users/alex/dev/projects/igniter/docs/language-covenant.md`
- `/Users/alex/dev/projects/igniter/docs/spec/ch13-managed-recursion.md`
- `/Users/alex/dev/projects/igniter/docs/spec/ch2-source-surface.md`
- `/Users/alex/dev/projects/igniter/source/loops_and_recursion.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-render-html`

Live source and current canon docs win over older proof packets.

## Questions To Answer

1. Does canon explicitly forbid, allow, or omit self-referential `type` definitions?
2. Is OOF-F1 scoped only to recursive `def` / computation, or also to `TypeDecl`?
3. Does managed recursion (Ch13) apply only to computation, or can it govern structural traversal of recursive
   data?
4. How does lab currently behave if given:

   ```ig
   type Node {
     label : String
     children : Collection[Node]
   }
   ```

   Does it parse, typecheck, reject, loop, or silently mis-model?
5. What would ViewArtifact / HTML need in practice:
   - recursive `HtmlNode.children`;
   - bounded non-recursive layout records;
   - host-owned tree traversal over JSON;
   - flat descriptor plus helper conventions?
6. Which answer best preserves Igniter's law: "declared, bounded, auditable repetition"?

## Alternatives To Compare

### A. Forbid recursive `TypeDecl` explicitly

Add a canon-facing OOF rule: self-referential data types are closed in v0.

Pros: simplest; prevents accidental recursive runtime/typechecker traps.

Cons: view trees, ASTs, and graph-like descriptors must use flattened or bounded encodings.

### B. Allow recursive `TypeDecl` only with managed structural traversal

Recursive shape may exist, but any traversal must be through managed structural recursion / bounded host
walkers.

Pros: aligns data recursion with Ch13; unlocks trees without free computation recursion.

Cons: larger type-system/spec commitment; needs careful finite-construction and traversal semantics.

### C. Allow host-owned recursive descriptors, keep `.ig` records flat

`.ig` authors produce finite JSON/record descriptors; host projectors may traverse nested JSON with depth
bounds, but `TypeDecl` itself remains non-recursive.

Pros: good fit for ViewArtifact/HTML; keeps language simpler.

Cons: less type safety for deeply nested authored views unless another descriptor layer lands.

### D. Defer; keep bounded non-recursive ViewArtifact vocabulary

Continue with flat `HtmlNode`, `link`, `select`, helper contracts, and optional one-level layout records.

Pros: matches current incremental path; no canon decision needed now.

Cons: does not answer the recurring question; agents will rediscover it.

## Boundary

Allowed:

- Write a clarification packet.
- Run small parser/typechecker probes in temp fixtures if useful.
- Cite canon and lab source paths.
- Recommend one canon-facing follow-up PROP/card.
- Update this card with closing report.

Closed:

- No compiler implementation.
- No spec rewrite beyond a proposed wording snippet.
- No ViewArtifact schema change.
- No `.ig.html` / view-engine implementation.
- No claim that lab evidence changes canon authority.

## Required Packet

Create:

`lab-docs/lang/lab-canon-recursive-typedecl-clarification-p1-v0.md`

Include:

- explicit distinction between computation recursion and data-shape recursion;
- canon evidence for managed computation recursion;
- canon evidence or silence around recursive `TypeDecl`;
- lab behavior probe for recursive record type;
- recommendation among A/B/C/D;
- exact wording for a future canon/proposal question.

## Verification

Suggested commands:

```bash
cd /Users/alex/dev/projects/igniter
rg -n "recursion|recursive|recur|decreases|OOF-F1|TypeDecl|type .*children|children : Collection" docs source

cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
rg -n "recursive|recur|decreases|OOF-F1|TypeDecl|type_defs|children : Collection|HtmlNode|ViewArtifact" \
  lang/igniter-compiler server/igniter-web frame-ui/igniter-render-html lab-docs/lang .agents/work/cards/lang
```

If you create temp fixtures, keep them under `/tmp` unless the card explicitly needs a committed proof.

## Acceptance

- [x] Packet exists.
- [x] It separates computation recursion from recursive data types.
- [x] It cites canon managed-recursion evidence.
- [x] It states whether canon currently governs recursive `TypeDecl` or is silent.
- [x] It probes or precisely characterizes lab behavior for recursive record types.
- [x] It recommends A/B/C/D or a tighter variant.
- [x] It names the impact on ViewArtifact / HTML engine direction.
- [x] It makes no lab implementation change.
- [x] `git diff --check` clean.

## Reporting

Close with:

- the canon/lab answer in one paragraph;
- the chosen recommendation;
- whether current flat ViewArtifact work should continue unchanged;
- the next canon-facing action, if any.
