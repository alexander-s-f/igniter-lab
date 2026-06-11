# PROP-IMPORT-RESOLUTION-P3

**Card:** PROP-IMPORT-RESOLUTION-P3
**Track:** import-resolution-multifile-compiler-driver-implementation-v0
**Status:** CLOSED - ACCEPT (83/83)
**Route:** BOUNDED IMPLEMENTATION / RUST-LAB FIRST
**Skill:** IDD Agent Protocol
**Agent:** [Rust-Lab Compiler Implementation Agent]
**Role:** bounded-implementation-agent
**Category:** lang / proof
**Date:** 2026-06-11

---

## Goal

Implement bounded Rust-lab import resolution and multi-file compilation-unit
support using PROP-IMPORT-RESOLUTION-P1/P2/P2A and
LAB-MULTIFILE-COMPILATION-P1 as the specification/evidence base.

This is Rust-lab implementation, not Ruby canon implementation and not public
API.

---

## Decision

**ACCEPT.**

The Rust lab compiler now accepts N source files before `--out`:

```text
igniter_compiler compile SOURCE [SOURCE ...] --out OUT.igapp
```

Single-source behavior is preserved. Multi-source behavior runs a compiler-driver
pre-pass that builds a source-unit inventory, validates module/import/duplicate
rules, computes a composite source hash, and then feeds one deterministic merged
universe into the existing compiler path.

---

## Delivered

| Artifact | Path | Status |
|---|---|---|
| Multi-file resolver | `igniter-compiler/src/multifile.rs` | DONE |
| CLI integration | `igniter-compiler/src/main.rs` | DONE |
| Module export | `igniter-compiler/src/lib.rs` | DONE |
| Manifest evidence | `igniter-compiler/src/assembler.rs` | DONE |
| Fixtures | `igniter-view-engine/fixtures/multifile_compilation_p3/` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_prop_import_resolution_p3.rb` | DONE - 83/83 PASS |
| Lab doc | `lab-docs/lang/lab-import-resolution-multifile-rust-implementation-v0.md` | DONE |
| Portfolio update | `.agents/portfolio-index.md` | DONE |

---

## Diagnostic Mapping Proven

| Case | Code |
|---|---|
| circular import | `OOF-IMP1` |
| unknown module import | `OOF-IMP2` |
| missing selective import name | `OOF-IMP3` |
| duplicate module declaration | `OOF-IMP4` |
| missing module declaration in N>1 unit | `OOF-IMP5` |
| duplicate contract across universe | `OOF-DECL-DUP-CONTRACT` |
| duplicate type across universe | `OOF-DECL-DUP-TYPE` |

No old import candidate `OOF-M1/M2/M3` codes are emitted by the P3 multi-file
pre-pass.

---

## Proof Results

| Section | Checks |
|---|---:|
| IMP3-COMPILE | 9/9 |
| IMP3-IMPORT | 10/10 |
| IMP3-IDENTITY | 13/13 |
| IMP3-DIAGNOSTICS | 20/20 |
| IMP3-AUTHORITY | 8/8 |
| IMP3-COPYPASTE | 8/8 |
| IMP3-CLOSED | 10/10 |
| IMP3-REGRESSION | 5/5 |

Total: **83/83 PASS**.

Regression:

```text
LAB-MULTIFILE-COMPILATION-P1 PASS (60/60)
```

---

## Closed Surfaces

- no Ruby canon implementation
- no package registry/distribution/semver/trust store
- no public/internal visibility
- no stdlib-as-import
- no runtime loading or dynamic imports
- no capability/profile import
- no VM changes
- no public/stable API

---

## Next Route

Recommended:

```text
PROP-IMPORT-RESOLUTION-P4 - Ruby/canon implementation planning or parity decision
```

Independent:

```text
PROP-ENTRYPOINT-P3
```

Module visibility remains deferred.
