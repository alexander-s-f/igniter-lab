# igniter-lab: Portfolio Index

**Maintained by:** Portfolio Architect Supervisor
**Last updated:** 2026-06-07
**Scope:** Cross-repo state map for igniter-lab ↔ igniter-lang

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
| PROP-035: capability/effect_binding grammar | igniter-lang | ✅ experiment-pass | 64/64 |
| `lab-docs/lang/lab-igniter-lang-io-capability-grammar-v0.md` | igniter-lab | ✅ | — |

**Next:** Runtime injection design; PROP-033 (via profile binding)

### Contract Modifiers (PROP-031 / PROP-035)

| Artifact | Repo | Status |
|---|---|---|
| PROP-031: pure/observed/effect/privileged/irreversible | igniter-lang | ✅ experiment-pass |
| PROP-035: Effect Surface (capability/effect_binding, OOF-M2/M4/M5) | igniter-lang | ✅ experiment-pass |
| PROP-040: profile declarations | igniter-lang | queued; not authored |

### HTTP-Types / Rack

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-LANG-HTTP-TYPES-P1 (ContractRef, middleware compose, IgniterFailure) | igniter-lab | ✅ DONE | ~41/41 |
| Grammar analog | igniter-lang | ❌ not planned yet | — |

### Web Framework / View Engine

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-WEB-FRAMEWORK-P4 (LayoutEngine, fill_slot, render, inheritance) | igniter-lab | ✅ DONE | ~45/45 |
| Grammar analog | igniter-lang | ❌ lab-only for now | — |

---

## Proposal Queue (igniter-lang Stage 3)

| PROP | Name | Status | Priority |
|---|---|---|---|
| PROP-031 | Contract modifiers | experiment-pass | — |
| PROP-032 | Assumptions block | experiment-pass (bounded) | — |
| PROP-033 | via profile binding | queued | 🔥 High |
| PROP-034 | output evidence syntax | queued | 🟡 Medium |
| PROP-035 | Effect Surface / IO.Capability | experiment-pass | — |
| PROP-036 | compiler_profile_id manifest | accepted; partial-impl | — |
| PROP-037 | External progression svc liveness | accepted proposal-only | 🟡 Medium |
| PROP-038 | Compiler profile contract | accepted; partial-impl | 🟡 Medium |
| PROP-039 | Managed local recursion/loops | authored-pending-review | 🟢 Lab-backed |
| PROP-040 | Profile declarations | queued | 🔥 High |

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
| NET-P2..P6 → lang | Lab algebra has no grammar analog (beyond PROP-035) | Runtime injection — Phase 2 |
| HTTP-TYPES → lang | ContractRef not in grammar | Separate PROP when HTTP track matures |
| Web Framework → lang | LayoutEngine is lab-only | Separate PROP when view track matures |
| experiments/ archive | ~150 experiments, Stage 1/2 closed | DA-005: archive pass (low priority) |

---

## Delegated Cards (session 2026-06-07)

| ID | Task | Complexity | Status |
|---|---|---|---|
| DA-001 | current-status.md PROP-035/PROP-040 rows | Low | ✅ DONE |
| DA-002 | PROP-031..039 status audit + §12 renumbering | Low | ✅ DONE |
| DA-003 | lab-docs/lang IO capability grammar doc | Medium | ✅ DONE |
| DA-004 | portfolio-index.md | Low | ✅ DONE (this file) |
| DA-005 | experiments/ archive pass (Stage 1/2) | Medium | ⏳ Queued — not urgent |
