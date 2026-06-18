# Card: LAB-IGNITER-PACKAGE-ROUND1-OPUS-VALIDATION-P2 — validate Gemini package-manager research round one

**Lane:** standard / validation-readiness  
**Status:** CLOSED (validation packet)  
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18  
**Delegate label:** OPUS-PACKAGES-VALIDATION-A  
**Skill:** idd-agent-protocol  
**Authority:** Lab validation only. No code. No package spec authority. No canon. No implementation card
may be opened by this card unless clearly marked as a recommendation.

## Why this card exists

Gemini produced a broad first research round for `LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`, then
Codex curated it into:

`lab-docs/lang/lab-igniter-package-manager-research-round1-v0.md`

The consensus looks promising:

```text
local workspace packages
  + explicit path dependencies
  + content-addressed lock/provenance
  + projection dialects as pure lowering inputs
  + generated artifacts inspectable
  + no install scripts / no hidden hooks
  + host-owned capabilities and secrets
  + registry and version solver deferred
```

But Gemini research is evidence, not authority. This card asks Opus to validate, revise, or reject the
round-one conclusions against live Igniter surfaces and primary-source ecosystem facts.

## Read first

- `lab-docs/lang/lab-igniter-package-manager-research-round1-v0.md`
- `lab-docs/lang/lab-igniter-package-research-synthesis-gemini-p1-v0.md`
- all five Gemini shard reports:
  - `lab-igniter-package-research-cargo-go-gemini-p1-v0.md`
  - `lab-igniter-package-research-js-py-deno-gemini-p1-v0.md`
  - `lab-igniter-package-research-ruby-rails-gemini-p1-v0.md`
  - `lab-igniter-package-research-oci-wasm-terraform-gemini-p1-v0.md`
  - `lab-igniter-package-research-igniter-artifacts-gemini-p1-v0.md`
- parent card: `.agents/work/cards/lang/LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1.md`
- projection-dialects packet: `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`

## Verify-first live Igniter surfaces

Before judging the conclusions, verify current code/docs:

- `igniter-compiler/src/project.rs`
- `igniter-compiler/src/main.rs`
- `igniter-compiler/src/igweb.rs`
- `igniter-ui-kit/src/igv.rs` if present in checkout
- `igniter-web/src/lib.rs`
- `igniter-server/src/protocol.rs`
- `igniter-machine/IMPLEMENTED_SURFACE.md` if present in this checkout
- any current implemented-surface/status file that mentions package, workspace, projection dialect,
  lockfile, project-root, or overlay.

Live code wins over reports/cards.

## External fact validation

Use official or primary sources where practical. Do not over-browse; validate the claims that matter:

- Cargo build scripts/features/workspaces/lock behavior.
- Go modules MVS and `go.sum`.
- npm/pnpm lifecycle scripts and lockfile/provenance risk.
- Deno/JSR install-script stance and permissions model.
- RubyGems/Bundler install/native extension and lock behavior.
- OCI digest/tag/provenance model.
- WASM component/WIT interface model if relevant.

If a claim cannot be verified quickly, mark it `unverified`, not true.

## Questions to answer

For each strong design signal in Round 1, mark one of:

```text
ACCEPT
REVISE
REJECT
NEEDS MORE EVIDENCE
```

Signals:

1. Package identity should be two-layered: human name + digest anchor.
2. Package contents should distinguish source, projection source, generated output, compiled artifact.
3. Lockfile should eventually pin dependency content, compiler, stdlib, lowerer, generated hashes.
4. Install scripts absent in v0.
5. Capabilities are declarations, not credentials.
6. Registry is later.
7. Version solving is later; local v0 avoids SAT and MVS.

Also answer:

8. What did Gemini miss?
9. What did Gemini overstate?
10. What is the smallest safe implementation slice after validation?
11. What must be explicitly deferred?

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-package-round1-opus-validation-p2-v0.md`

Then update only this card with a closing report.

## Required report sections

1. Executive verdict.
2. Evidence sources checked.
3. Live Igniter surface check.
4. Ecosystem claim validation table.
5. Design signal verdict table (`ACCEPT/REVISE/REJECT/NEEDS MORE EVIDENCE`).
6. Gemini mistakes / overstatements.
7. Gemini strong insights to keep.
8. Recommended next implementation card, with acceptance sketch.
9. Deferred surfaces.

## Closed surfaces

- No code.
- No package spec.
- No lockfile format as authority.
- No registry.
- No CLI implementation.
- No canon claim.
- Do not edit Gemini reports unless correcting a factual broken link would be tiny and explicitly
  listed in the closing report.
- Do not touch parallel `igniter-web` P12 work.

## Acceptance

- [x] Report validates all seven Round-1 design signals.
- [x] Report cites which live Igniter surfaces were checked.
- [x] Report distinguishes verified external facts from assumptions.
- [x] Report identifies at least three Gemini overstatements or misses.
- [x] Report recommends exactly one next implementation card, or explicitly says "no implementation yet".
- [x] No code changed.

---

## Closing report — 2026-06-18

**Outcome:** Round-1 direction VALIDATED. Verdict: **6 ACCEPT (signals 1,2,4,5,6,7), 1 REVISE (3 —
lockfile timing/grounding), 0 REJECT.** A local-first, workspace-driven, content-addressed,
no-install-script model fits Igniter's live shape.

**Deliverable:** `lab-docs/lang/lab-igniter-package-round1-opus-validation-p2-v0.md` (9 required
sections).

**Live surfaces checked:** `project.rs` (only `source_roots`; modules by in-file `module` decl;
`resolve_entry`→`compile_units`; `stdlib.*` reserved; overlay; `OOF-IMP4`/`OOF-IMP2`/`OOF-PROJ-ENTRY`;
NO `[dependencies]`/lockfile), `main.rs`+emitter (already emits content-addressed `sha256` `source_hash`),
`igweb.rs`/`igv.rs` (deterministic projection-dialect lowering, inspectable), `igniter-web/src/lib.rs`
(build = pure lower+load, no install hooks), `igniter-server/src/protocol.rs` (no effect identity in
decisions), `igniter-machine` (capability_bindings = declarations; passports/secrets host-owned; blake3),
crate layout (sibling `path=../x` deps = lived local-path model).

**External facts:** validated against established primary-source documentation knowledge (NOT freshly
fetched); one ⚠ flagged (pnpm default lifecycle-script blocking is version-sensitive); one framing fix
(npm doesn't *ban* scripts — that's the lesson, not npm behavior). No claim false.

**Gemini misses/overstatements (5):** (1) missed the existing `source_hash`/`blake3` digest mechanism —
the lockfile should REUSE it, not invent; (2) overstated `[dependencies]` path-dep readiness (it's a NEW
surface vs current `source_roots`); (3) premature `version` field / "mutable tags during resolution" in a
path-only v0 (re-imports the deferred version concept); (4) internal inconsistency on
generated-committed-vs-cache (deterministic lowering → committing optional); (5) proposed two next cards
(+ a P-number collision) where one suffices.

**Recommended next card (exactly one):** `LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3` — local path
dependencies + module-ownership validation built on `project.rs` (`[dependencies] x = { path }`, fold
into compile set, enforce `OOF-IMP4` + declared-vs-owned; NO lockfile/registry/version-solver/install
hooks/new dep). Lockfile/provenance = a separate later card (reuse `source_hash`, drop `version`).

**No code changed.** (No Gemini reports edited — no broken links needed fixing.)
