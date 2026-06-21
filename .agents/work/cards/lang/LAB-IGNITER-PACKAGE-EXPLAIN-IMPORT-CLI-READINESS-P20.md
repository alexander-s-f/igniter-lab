# LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-READINESS-P20 — proactive import explanation command

Status: CLOSED
Lane: standard / package DX
Type: readiness / design
Delegation code: OPUS-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-READINESS-P20
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends conceptually on P18 and should be informed by P19 if P19 is already closed.

P19 diagnostic details should make **denied** imports actionable. It does not answer proactive or allowed
questions such as: "why is `App.Main` allowed to import `Mid.Public`?" or "would `Mid.M` be allowed to import
`Leaf.Private`?". P18 deferred a command for that case.

This card designs that command only. Do not implement it here.

## Goal

Decide whether and how to add a proactive import explanation CLI. The command must stay local-only and must not
become a solver, linter, or auto-fixer.

## Verify first

- P18 readiness doc and P19 implementation if present.
- Current `ProjectDiagnostic.details` shape if P19 exists.
- `igc package graph` shape if P18 implementation exists.
- `project.rs` graph/index integrity internals.
- Existing `OOF-IMP2`, `OOF-IMP4`, `OOF-IMP6`, `OOF-IMP7` behavior.

## Questions to answer

1. Is a proactive command still needed after P19 diagnostic details?
2. What is the exact command shape?
   - `igc package explain-import --from <module> --to <module>`
   - `igc package explain --module <module> --import <module>`
   - another shape?
3. Should it answer only current authored imports, or hypothetical imports too?
4. Should allowed imports return reasons: same package, declared edge, exported surface?
5. How should denied imports reuse P19 detail schema?
6. How should unresolved imports (`OOF-IMP2`) be reported without guessing?
7. How should duplicate module declarations (`OOF-IMP4`) be handled?
8. Should the command scan all modules, or take exact module names only?
9. Should it use the graph-only accessor or full module index?
10. What JSON schema and exit codes should v0 use?

## Bias

Prefer **not** implementing this command unless P19 details leave a real gap. If it is implemented later, prefer
one explicit JSON-only command:

```text
igc package explain-import --project-root <dir> --from Mid.M --to Leaf.Private
```

## Required deliverable

- Readiness packet: `lab-docs/lang/lab-igniter-package-explain-import-cli-readiness-p20-v0.md`
- Closing report in this card.
- Clear go/no-go recommendation.
- If go: exact implementation card name and acceptance matrix.

## Acceptance

- [x] Live P19/P18/P16 behavior verified.
- [x] At least three command/API shapes compared.
- [x] JSON schema and exit-code policy drafted if command is recommended.
- [x] Allowed, denied, unresolved, duplicate-module cases addressed.
- [x] Solver/auto-fix boundary stated clearly.
- [x] No production code changes.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-igniter-package-explain-import-cli-readiness-p20-v0.md` — readiness
packet, no production code (`git diff --check` clean).

**Recommendation: qualified GO (small, lower-priority).** Verify-first confirmed P19 explains only
*denied-authored* imports; **allowed** ("why is this import allowed?") and **hypothetical** ("would X be
allowed?") remain genuinely unanswerable — `igc package graph` exposes data but not a verdict (an agent would
have to re-implement OOF-IMP6/7 client-side). A one-edge command running the *real* rule server-side closes
that gap; the card's own closed scope explicitly permits "explaining one requested import edge".

**Design:** `igc package explain-import --project-root <dir> --from <module> --to <module>`, JSON-only,
hypothetical (any from/to pair). `decision` ∈ allowed/denied/unresolved; **denied reuses the P19 `details`
block** (single rule source); unresolved = no provider, no guessing; duplicate/missing = structured error.
Exit 0 for any successful explanation, exit 1 for command/assembly errors. Solver/auto-fix boundary: explains
one edge + the static P19 fix, nothing else.

**Next:** `LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-P21` (impl) — key invariant: factor the per-edge scope +
export predicates out of `index_integrity` so `explain_import_value` and the diagnostics share one rule
(behavior-preserving refactor). 9-point acceptance matrix in §7. Priority note: lower than the
remote/registry wave; ready to run when the user wants it.

## Closed scope

- No implementation.
- No registry/remote/semver.
- No auto-fix.
- No module rename/refactor tooling.
- No package linter beyond explaining one requested import edge.
