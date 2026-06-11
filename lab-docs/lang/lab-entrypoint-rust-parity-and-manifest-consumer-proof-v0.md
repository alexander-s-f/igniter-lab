# LAB: Entrypoint Rust Parity and Manifest Consumer Proof v0

**Card:** PROP-ENTRYPOINT-P4
**Route:** LAB PARITY + MANIFEST CONSUMER PROOF
**Track:** explicit-entrypoint-rust-lab-parity-and-tooling-consumer-v0
**Status:** CLOSED / PROVED
**Date:** 2026-06-11
**Authority:** lab parity / consumer proof only

---

## Summary

PROP-ENTRYPOINT-P4 proves that explicit `entrypoint ContractName` metadata from
PROP-ENTRYPOINT-P3 is consumable outside the Ruby single-file pipeline.

Selected scope: **Option C**.

- Rust lab compiler parity was added for parser -> classifier -> typechecker ->
  SemanticIR -> `.igapp` manifest.
- A proof-local manifest consumer reads `manifest.entrypoint`, validates the
  target contract path/ref against `contract_index`, and produces display/select
  metadata without executing VM behavior.

Entrypoint remains metadata/evidence only. It does not create runtime launch
authority.

---

## Implemented Parity

Rust lab parser:

- accepts top-level `entrypoint ContractName`;
- accepts qualified target text;
- preserves `source_span` line/col;
- rejects duplicate declarations with `OOF-EP1`.

Rust lab classifier:

- passes optional entrypoint metadata through at program level;
- does not add dependency graph nodes or edges.

Rust lab typechecker:

- resolves target by contract name or module-qualified `contract_id`;
- emits `OOF-EP2` for unknown targets;
- emits `OOF-EP5` when target is detectably a type, not a contract;
- accepts zero-entrypoint library modules;
- accepts effect-contract entrypoints as metadata;
- does not change fragment classification.

Rust lab SemanticIR:

- emits program-level `entrypoint` metadata when present;
- includes declared target, resolved contract, resolved contract id,
  source span, fragment class, and `contract_ref`;
- omits entrypoint when absent;
- does not change contract IR node shape.

Rust lab assembler:

- emits `manifest.entrypoint` when present;
- includes kind, declared target, resolved contract, contract path/ref, and
  source span/source path;
- includes entrypoint in artifact hash material before `artifact_hash` is
  computed;
- omits manifest entrypoint when absent.

---

## Consumer Proof

The proof-local consumer reads only `.igapp/manifest.json`.

It validates:

- `manifest.entrypoint.contract_path` exists;
- `manifest.entrypoint.contract_ref` matches `contract_index`;
- display label can be derived from `declared_target`;
- contract artifact can be located by path;
- no VM execution is invoked;
- no capability/profile authority is granted.

This proves tooling consumption, not runtime execution selection.

---

## Evidence

Proof runner:

```text
igniter-view-engine/proofs/verify_prop_entrypoint_p4.rb
```

Fixtures:

```text
igniter-view-engine/fixtures/entrypoint_p4/
```

Result:

```text
PROP-ENTRYPOINT-P4 PASS (64/64)
```

Proof sections:

- `EP4-COMPILE` - 8 checks;
- `EP4-DIAGNOSTICS` - 9 checks;
- `EP4-SIR` - 10 checks;
- `EP4-MANIFEST` - 13 checks;
- `EP4-CONSUMER` - 8 checks;
- `EP4-NONAUTH` - 8 checks;
- `EP4-REGRESSION` - 8 checks.

Additional verification:

- `cargo check` in `igniter-compiler`;
- proof runner invokes `cargo run -- compile ...` for all fixtures.

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
- import-resolution semantics beyond existing module-qualified contract id
  resolution;
- live runner launch behavior.

---

## Decision

**CLOSED / PROVED.**

The entrypoint track can pause. The natural next route is:

```text
Continue PROP-IMPORT-RESOLUTION-P3 if separately authorized.
```

Optional later:

```text
Manifest/IDE consumer hardening if a real IDE surface needs richer display rules.
```
