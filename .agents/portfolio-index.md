# igniter-lab: Portfolio Index

**Maintained by:** Portfolio Architect Supervisor
**Last updated:** 2026-06-07
**Scope:** Cross-repo state map for igniter-lab ↔ igniter-lang

---

## Canon Boundary Rules (igniter-lang)

| Rule | Statement | Adopted |
|------|-----------|---------|
| CR-001 | Canon type opacity: IO.* types are opaque identifiers; schema is lab-only | 2026-06-07 |
| CR-002 | Lab diagnostic boundary: E-NET-* codes are lab-local; OOF promotion requires PROP+grammar review | 2026-06-07 |
| CR-003 | Profile binding is intent record only — not validated authority until PROP-040 OOF-M7/M8 active | 2026-06-07 (closed by PROP-040) |

---

## Tracks and Status

### IO.NetworkCapability

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-STDLIB-NET-P2 (schema, delegation algebra) | igniter-lab | ✅ DONE | 53/53 |
| LAB-STDLIB-NET-P3 (FFI surface, stub mode) | igniter-lab | ✅ DONE | 61/61 |
| LAB-STDLIB-NET-P4 (compiler escape classification, E-NET-* codes) | igniter-lab | ✅ DONE | 42/42 |
| LAB-STDLIB-NET-P5 (hardening: glob, chains, bind-address, wildcard) | igniter-lab | ✅ DONE | 44/44 |
| LAB-STDLIB-NET-P6 (dead grant, compose bind_address) | igniter-lab | ✅ DONE | ~36/36 |
| PROP-035: capability/effect_binding grammar + OOF-M2/M4/M5 | igniter-lang | ✅ experiment-pass | 64/64 |
| `lab-docs/lang/lab-igniter-lang-io-capability-grammar-v0.md` | igniter-lab | ✅ bridge doc | — |

**Boundary:** Canon grammar names IO types as opaque identifiers (CR-001). Schema, delegation
algebra, FFI, E-NET-* codes remain lab-only. Runtime injection is Phase 2.

### Profile System (PROP-033 / PROP-040)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| PROP-033: `via <profile>` binding on contract declarations | igniter-lang | ✅ experiment-pass | 52/52 |
| PROP-040: module-level `profile <name> { authority: <modifier> }` declarations | igniter-lang | ✅ experiment-pass | 63/63 |
| OOF-M7 (modifier below profile authority) / OOF-M8 (unknown profile) | igniter-lang | ✅ active in classifier | — |
| CR-003 closed by PROP-040 | igniter-lang | ✅ | — |

**Profile chain:** `profile_binding` (PROP-033) + `profile_authority` (PROP-040) propagate through
all four pipeline stages (parser → classifier → typechecker → SemanticIR). Via references
to undeclared profiles now trigger OOF-M8 at classify time.

### Contract Modifiers (PROP-031 / PROP-035)

| Artifact | Repo | Status |
|---|---|---|
| PROP-031: pure/observed/effect/privileged/irreversible | igniter-lang | ✅ experiment-pass |
| PROP-035: Effect Surface (capability/effect_binding, OOF-M2/M4/M5) | igniter-lang | ✅ experiment-pass |

### Assumptions Block (PROP-032)

| Artifact | Repo | Status |
|---|---|---|
| PROP-032: `assumptions {}` + `uses assumptions NAME` | igniter-lang | ✅ experiment-pass (bounded compiler surface) |

### Managed Recursion and Loop Classes (PROP-039)

| Artifact | Repo | Status |
|---|---|---|
| PROP-039: loop-class vocabulary + recursion design | igniter-lang | ✅ accepted; proposal-only |
| FiniteLoop / BudgetedLocalLoop / StructuralRecursion / FuelBoundedRecursion | igniter-lang | vocabulary accepted |
| OOF-L1..L5 / OOF-R1..R5 | igniter-lang | candidates only — not OOF registry authority |
| ServiceLoop | → PROP-037 exclusive | excluded from PROP-039 |
| Parser / TypeChecker / runtime implementation | igniter-lang | **closed** (7 gates before impl auth) |

**Boundary:** Lab/R248 fixture grammar is pressure evidence only. Rust/alternate implementations
are not language authority. All implementation surfaces remain closed.

### External Progression / Service Liveness (PROP-037)

| Artifact | Repo | Status |
|---|---|---|
| PROP-037: Progression, ProgressionSource, ProgressionEvent | igniter-lang | accepted; proposal-only |
| clock.every, tick.time bindings | igniter-lang | PROP-037 scope |
| OOF-SL* codes | igniter-lang | PROP-037 companion territory |

### HTTP-Types / Rack (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-LANG-HTTP-TYPES-P1 (ContractRef, middleware compose, IgniterFailure) | igniter-lab | ✅ DONE | ~41/41 |
| Grammar analog | igniter-lang | ❌ lab pressure only (CR-001 applies) | — |

**Boundary:** HTTP types may not enter canon grammar without a cross-repo PROP + governance review.
Rack/middleware vocabulary is lab-only.

### Web Framework / View Engine (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-WEB-FRAMEWORK-P4 (LayoutEngine, fill_slot, render, inheritance) | igniter-lab | ✅ DONE | ~45/45 |
| Grammar analog | igniter-lang | ❌ lab-only for now | — |

---

## Proposal Queue (igniter-lang Stage 3)

| PROP | Name | Status | Notes |
|---|---|---|---|
| PROP-031 | Contract modifiers | ✅ experiment-pass | Base modifier grammar |
| PROP-032 | Assumptions block | ✅ experiment-pass (bounded) | Compiler surface only |
| PROP-033 | via profile binding | ✅ experiment-pass | profile_binding in contract_ir |
| PROP-034 | output evidence syntax | ✅ experiment-pass | OOF-M9; evidence in IR output ports |
| PROP-035 | Effect Surface / IO.Capability | ✅ experiment-pass | OOF-M2/M4/M5 |
| PROP-036 | compiler_profile_id manifest | accepted; partial-impl | CLI B1..B9 closed |
| PROP-037 | External progression svc liveness | ✅ accepted; all OOF-PR1..9 closed | ServiceLoop auth; OOF-PR6/8 + schema ownership closed 2026-06-07 |
| PROP-038 | Compiler profile contract | accepted; partial-impl | schema + validator |
| PROP-039 | Managed local recursion/loops | ✅ accepted; proposal-only | Vocabulary only; impl closed |
| PROP-040 | Profile declarations | ✅ experiment-pass | OOF-M7/M8; closes CR-003 |

**Next queue:**
1. ✅ PROP-039 gate 1: loop_class_semantics_proof — 66/66 PASS (2026-06-07)
2. ✅ PROP-039 gate 3: loop_class_parser_proof — 60/60 PASS (2026-06-07)
3. ✅ DA-005: archive pass complete — 12 dirs moved, 164 unknown intact
4. PROP-039 gate 4: TypeChecker proof (requires separate auth to open)

---

## Workspace Repo Map

| Repo | Authority | Boundary |
|---|---|---|
| `igniter-lang` | Language canon: spec, proposals, grammar, compiler proof | Language meaning only |
| `igniter-lab` | Lab frontier: experiments, proofs, prototypes | Evidence only; not canon |
| `igniter-ruby` | Ruby Framework gem umbrella | Framework impl; not language spec |
| `igniter-org` | Public site (`igniter-lang.org`) | Projects current truth from lang/lab |
| `igniter-archive` | Recovery bucket from monorepo split | Not a default dependency |

**Monorepo note:** Workspace split from the `/igniter` monorepo. `igniter-archive` is the
quarantine bucket. Nothing there is a default dependency — review explicitly before pulling.

---

## Alignment Gaps

| Gap | Description | Action |
|---|---|---|
| NET-P2..P6 → lang | Lab delegation algebra has no grammar analog beyond PROP-035 | Runtime injection — Phase 2 |
| HTTP-TYPES → lang | ContractRef not in grammar; lab pressure only | Separate PROP when HTTP track matures |
| Web Framework → lang | LayoutEngine is lab-only; lab pressure only | Separate PROP when view track matures |
| PROP-039 loop impl | Gates 1+3 closed; parser surface live | Gate 4 (TypeChecker) next — requires separate auth |
| experiments/ archive | ~150 experiments, Stage 1/2 closed | DA-005: archive pass (low priority) |

---

## Delegated Cards

| ID | Task | Status |
|---|---|---|
| DA-001 | current-status.md PROP-035/PROP-040 rows | ✅ DONE |
| DA-002 | PROP-031..039 status audit + §12 renumbering | ✅ DONE |
| DA-003 | lab-docs/lang IO capability grammar doc | ✅ DONE |
| DA-004 | portfolio-index.md | ✅ DONE (this file) |
| DA-005 | experiments/ archive pass (Stage 1/2) | ✅ DONE 2026-06-07 — 5→stage1, 7→stage2, 164 unknown left, 1 error (typechecker dir absent) |

---

## Meta Notes

**MFN-001 (Portfolio Meta-Architect → Portfolio Architect Supervisor, 2026-06-07):**
- PROP-040 queued before PROP-039 → both now closed
- CR-001/002/003 firewall rules adopted in language-covenant.md
- Rack/Web/Ruby pressure stays lab-only (CR-001)
- PROP-039 accepted as vocabulary authority; parallel track confirmed; implementation closed
