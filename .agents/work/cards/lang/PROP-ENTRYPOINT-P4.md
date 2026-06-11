# PROP-ENTRYPOINT-P4

**Card:** PROP-ENTRYPOINT-P4
**Track:** explicit-entrypoint-rust-lab-parity-and-tooling-consumer-v0
**Route:** LAB PARITY + MANIFEST CONSUMER PROOF
**Status:** CLOSED - PROVED
**Authority:** lab parity / consumer proof only
**Date:** 2026-06-11
**Category:** lang / lab parity

---

## Goal

Prove that explicit `entrypoint ContractName` metadata from
PROP-ENTRYPOINT-P3 can be produced and consumed outside the Ruby single-file
pipeline without becoming execution authority.

---

## Selected Scope

Selected **Option C**:

- Rust-lab parser/typechecker/SemanticIR/manifest parity;
- minimal manifest consumer proof.

This is broader than consumer-only proof, but still bounded: no runner behavior
changed.

---

## Result

**CLOSED / PROVED** with:

```text
PROP-ENTRYPOINT-P4 PASS (64/64)
```

Proof runner:

```text
igniter-view-engine/proofs/verify_prop_entrypoint_p4.rb
```

Fixtures:

```text
igniter-view-engine/fixtures/entrypoint_p4/
```

Lab doc:

```text
lab-docs/lang/lab-entrypoint-rust-parity-and-manifest-consumer-proof-v0.md
```

---

## Proven Behavior

- Rust parser accepts top-level `entrypoint ContractName`.
- Qualified target text is preserved and resolves by module-qualified
  `contract_id` in the current Rust lab compiler.
- Duplicate entrypoint fails closed with `OOF-EP1`.
- Unknown target fails closed with `OOF-EP2`.
- Detectable type target fails closed with `OOF-EP5`.
- Zero-entrypoint library module remains valid.
- Effect-contract entrypoint is accepted as metadata.
- SemanticIR emits program-level entrypoint metadata.
- `.igapp` manifest emits `entrypoint` metadata when present and omits it when
  absent.
- Manifest consumer resolves display label, contract path, and contract ref
  without executing VM behavior.

---

## Non-Authority Proof

The proof checks:

- no `igniter-vm` source changed;
- compiler CLI source does not consume manifest entrypoint;
- no scheduler/main loop/app framework fields appear;
- no visibility/package/import authority is opened;
- no capability tokens are granted by entrypoint metadata;
- consumer projection is `metadata_only` and `would_execute=false`.

---

## Closed Surfaces

Still closed:

- CLI behavior changes;
- VM behavior changes;
- automatic run behavior;
- app framework;
- scheduler/main loop;
- package system;
- public/internal visibility;
- capability authority;
- public/stable API;
- live runner launch behavior.

---

## Decision

The entrypoint track can pause after P4.

Recommended next route:

```text
Continue PROP-IMPORT-RESOLUTION-P3 if separately authorized.
```

Optional later:

```text
Manifest/IDE consumer hardening if a real IDE surface needs richer display rules.
```
