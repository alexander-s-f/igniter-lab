# LAB-PACKAGE-MODEL-P1 (a2) — Package Identity / Distribution Boundary Research

**Track:** package-identity-distribution-and-authority-boundary-v0
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Branch:** a2 (parallel to a1; written independently, a1 not read before close)
**Status:** CLOSED — OPEN-with-SPLIT
**Date:** 2026-06-11

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Research doc | `igniter-lab/lab-docs/governance/lab-package-identity-distribution-boundary-v0-a2.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-PACKAGE-MODEL-P1-a2.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Headline Findings

1. **The package identity primitive already shipped.** The multi-file composite
   `source_hash` rule (IMPORT-P5: `sha256(canonical_json(sorted source units))`) IS a
   package digest — order-independence proved twice (IMPORT-P5 99/99; TYPED-REF-P5 I-02).
   `package_digest` = verbatim formula reuse.

2. **Cross-boundary reference evidence is live as of today.** TYPED-REF-P5 (71/71)
   `dependency_edges` with `from_module`/`to_module`/`resolution_kind` are exactly the
   mechanism by which consumer code references package contracts — the P2 proof can
   assert against them directly.

3. **One package-hostile blocker found (empirical, from P5 implementation):**
   `OOF-DECL-DUP-CONTRACT` makes contract names a GLOBAL namespace across the merged
   universe. Two packages exporting same-named contracts cannot co-compile (hit directly
   in P5 fixture work). Resolution layer is attribution-aware (`per_contract_module`);
   declaration layer is not. Routed as prerequisite study LANG-CONTRACT-NAMESPACE-P1.

4. **v0 package = layered (E):** source (truth) + manifest (claims index) + optional
   receipts. Governing rule: *source is the truth, manifest is an index of claims,
   recomputation is the check.*

5. **Authority boundary — all answers NO by mechanism, not policy:** no capability via
   dependency (consumer-side binding; grant fields are schema-absent — smuggling is a
   schema violation), no profile binding, no runtime effect, no install/import-time
   execution (no hook surface exists + PROP-038 §16). Effect contracts exposed as inert
   declarations only. Capability granted by app/host at composition root (RES-003 A4).
   One-liner: authority flows downward from the composition root, never upward from a
   dependency.

6. **Four-layer separation:** acquisition (outside compiler) → module import (OOF-IMP*,
   unchanged) → typed refs (P5 evidence) → runtime invocation (gated, closed).
   `compile_sources(source_paths:)` is the only seam packages touch.

7. **Lockfile = resolution receipt** (analogous to compilation_report): digest pins,
   origin, `verification.status: recomputed|claim_only` first-class, capability census as
   evidence (never grants), `graph_digest` over flattened set. Deterministic.

8. **Registry: v0 = local path workspace (C);** design center = untrusted
   content-addressed catalog (B) — registry holds claims, not truth; compromise degrades
   to availability. Trusted central registry rejected. Git = transport only.

9. **Transitive deps: allow + flatten** into the receipt with full census; consumer's
   effect/capability census includes transitive census (P20 applied to authority);
   approval = committing the receipt.

10. **Stdlib = the package the compiler vouches for** (pinned via compiler_profile_id;
    RES-001 inventory hash) — same mechanism, different trust position. Lab proof
    fixtures never packaged.

---

## Verdict

**OPEN — with SPLIT** (substrate sufficient, no HOLD):

1. **LANG-CONTRACT-NAMESPACE-P1** — prerequisite study: per-module vs global contract
   name uniqueness; inventory of name-keyed surfaces (dup rule, `call_contract` string
   callees, same_module_registry, manifest contracts list). Blocking for any two-package
   proof. Research route, no implementation.
2. **LAB-PACKAGE-MODEL-P2** — proof-local: two local packages (`pkg_core`/`pkg_app`)
   through real `compile_sources`; igpack manifests generated + recompute-verified;
   resolution receipt with tamper-negative check; cross-package `dependency_edges`
   asserted (`resolution_kind: qualified/imported`); no-authority-fields assertions;
   determinism checks.
3. Proposal authoring (PROP-PACKAGE-MODEL) only after P2 evidence.

---

## Closed Surfaces (unchanged)

Package manager / registry / lockfile / import implementation / parser / compiler / VM /
runtime / public package API / stdlib promotion / capability-profile granting through
dependencies. Package signing design-only. Automatic capability grants closed permanently
(schema-absent by design).
