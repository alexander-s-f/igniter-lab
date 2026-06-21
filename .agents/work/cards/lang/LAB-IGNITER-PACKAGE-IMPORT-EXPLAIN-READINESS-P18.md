# LAB-IGNITER-PACKAGE-IMPORT-EXPLAIN-READINESS-P18 — explain why an import is allowed or denied

Status: CLOSED
Lane: standard / package DX
Type: readiness / design
Delegation code: OPUS-IGNITER-PACKAGE-IMPORT-EXPLAIN-READINESS-P18
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P7/P10/P12/P14 created strong import governance:

- package scope (`OOF-IMP6`): importer may import provider only through same-package or a declared edge;
- exports (`OOF-IMP7`): provider must export the imported module across package edges;
- cycle (`OOF-IMP8`) and soon missing dep path (`OOF-IMP9`).

This is correct but can be opaque. Users and agents need a way to ask: "why can't `Mid.M` import
`Leaf.Private`?" without re-reading graph internals.

This card is intentionally separate from P17. P17 designs graph/status introspection; P18 focuses on the import
explanation UX.

## Goal

Design a minimal, local-only import explanation surface. It may become a CLI command, a JSON diagnostic helper,
or just richer structured diagnostics. Pick the smallest shape that makes `OOF-IMP6`/`OOF-IMP7` actionable.

## Verify first

- Current diagnostic fields emitted by `ProjectDiagnostic` and `index_integrity`.
- Existing structured strict output for integrity diagnostics.
- Current tests around `OOF-IMP6` and `OOF-IMP7`.
- P14/P15 docs around graph-edge scope and exports.

## Questions to answer

1. Is a new command needed, or should existing `OOF-IMP6`/`OOF-IMP7` diagnostics gain enough structured fields?
2. If a command is useful, what is the minimal form?
   - `igc package explain-import --from Mid.M --to Leaf.Private`
   - `igc package explain --module Mid.M --import Leaf.Private`
   - other?
3. How does the user select a module when duplicate module declarations exist (`OOF-IMP4`)?
4. What should the explanation include?
   - importer package label/path
   - provider package label/path
   - declared edge present/missing
   - provider exports mode/surface
   - root closed-default policy
   - suggested fix
5. Should explanations work for allowed imports too?
6. How should unresolved imports (`OOF-IMP2`) be explained without guessing providers?
7. How do we keep this from becoming a package solver or linter?

## Bias

Prefer structured diagnostic enrichment if that solves 80% of the pain. Add a CLI only if live verification shows
that users cannot get enough context from failed compile/strict verify output.

## Required deliverable

- Readiness packet: `lab-docs/lang/lab-igniter-package-import-explain-readiness-p18-v0.md`
- Closing report in this card.
- Recommendation: diagnostic enrichment vs CLI command vs both.
- If implementation is recommended, provide the exact next card and tests.

## Acceptance

- [x] Current `OOF-IMP6`/`OOF-IMP7` diagnostics characterized from live code/tests.
- [x] At least three UX shapes compared.
- [x] Recommendation preserves local-only package semantics and does not introduce solving.
- [x] Actionable field/schema proposal included.
- [x] No production code changes.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-igniter-package-import-explain-readiness-p18-v0.md` — readiness packet, no
production code (`git diff --check` clean).

**Verify-first:** `ProjectDiagnostic` is generic (P11 forbade package-specific fields). OOF-IMP6/7 already
carry rule, importer module, importer→imported `node`, importer `source_paths`, severity — but provider
**path**, exports **surface**, declared-edge **bool**, active **policy**, and a **fix** live only in the
prose `message`. Allowed imports produce **no** diagnostic.

**Recommendation: diagnostic enrichment** (shape A over B command / C prose / D both) — add ONE generic
`details: Option<Value>` escape-hatch to `ProjectDiagnostic` (P11-safe), populated for OOF-IMP6/7 with
`{kind, importer{module,package,path}, provider{...}, declared_edge, provider_exports{mode,modules},
exports_default, fix}`. `fix` = static per-rule template (evidence, not a solver). Auto-surfaces in compile +
`verify --strict`. Solves the *denied* case (80%). A proactive `igc package explain-import` for *allowed*/
hypothetical (Q5) is **deferred** — enrichment can't explain a passing import, but a command is only worth it
if v0 proves insufficient. Q3 (duplicates→OOF-IMP4 blocks first), Q6 (OOF-IMP2 unresolved = no provider, no
guessing), Q7 (static fix = no solver) answered.

**Next:** `LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19` (implement the `details` enrichment) — 8-point
acceptance matrix in §6; key invariant: non-package diagnostics (IMP4/8/9) stay byte-unchanged. Optional later:
`…-EXPLAIN-IMPORT-CLI-P20`.

## Closed scope

- No implementation.
- No registry/remote/semver.
- No auto-fix.
- No module rename/refactor tooling.
- No new package authority; explanations are evidence only.
