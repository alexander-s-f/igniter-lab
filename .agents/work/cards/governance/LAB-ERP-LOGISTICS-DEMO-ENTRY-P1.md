# LAB-ERP-LOGISTICS-DEMO-ENTRY-P1

**Status:** CLOSED (PARTIAL) — RUST+VM ENTRY GREEN / RUBY + VM-FLOAT-COMPARE RESIDUALS PINNED (2026-06-15)
**Route:** lab / app pressure / erp_logistics
**Date:** 2026-06-15
**Authority:** app fixture/entrypoint work only; no compiler or VM changes

## Goal

Classify and, if safe, add a zero-input demo/orchestrator entry for `erp_logistics` so
runtime checks can exercise the app without requiring external `routes` / `shipment`
inputs.

After homogeneous numeric ops were fixed, `erp_logistics` no longer appears blocked on
numeric typechecking. The remaining blocker is entry/UX: contracts execute, but the
chosen runtime entry needs inputs.

## Gate

Start after:

- `LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1` cluster 1 DONE.
- Current `erp_logistics` compile/runtime evidence available.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/erp_logistics/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/erp_logistics/`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/dev-tutorial.md`
- Existing companion app entrypoint patterns: `air_combat`, `lead_router`, `call_router`, `trade_robot`.

## Work

1. Confirm current Ruby/Rust compile status for `erp_logistics`.
2. Confirm runtime failure shape and exact missing inputs.
3. Find the intended orchestrator contract and whether a natural demo fixture contract already exists.
4. If safe, add a named `entrypoint` demo contract with inline sample records and no external IO.
5. Keep production-like contracts untouched; the demo entry is a companion runtime fixture, not an authority model.
6. Re-run Ruby/Rust compile and VM run.
7. Update pressure registry and write baseline/proof artifacts.

## Deliverables

- Minimal app source edit only if needed under `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/erp_logistics/`.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_erp_logistics_demo_entry_p1.rb`, target at least 80 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-erp-logistics-demo-entry-p1-v0.md`.
- Update app `PRESSURE_REGISTRY.md`, this card, and portfolio index.

## Acceptance

- Ruby compile ok/0 and Rust compile ok/0.
- VM run succeeds through the demo entry if app semantics permit.
- Source hash/count changes documented.
- No external IO, clock, scheduler, database, or queue authority introduced.
- The entrypoint is clearly demo/orchestrator fixture, not production service-loop semantics.

## Closed Surfaces

- No compiler changes.
- No VM changes.
- No numeric coercion changes.
- No storage/HTTP/queue integration.
- No broad app refactor.
- No migration of other apps.

## Agent Recommendation

Give this to **Sonnet 4.6** or **Codex GPT 5.5**. It is app-shaping plus baseline proof, not language design.

---

## Closure Summary — CLOSED (PARTIAL) 2026-06-15

**Source hash (5-file closure, absolute paths):**
`sha256:dafbf1eb358fc7e13e1458b12c5e7f81a61f514017ea714cd548ae23b52d3041`
(Rust and Ruby agree on the closure hash; status differs.)

Added one source unit — `example.ig` (`module ErpExample`): a zero-input companion
fixture with a bare `entrypoint RunBestRoute`, three `Make*` typed-record factories,
and three `Run*` scenarios. Production contracts (`CheckCapacity`,
`CalculateBestRoute`, `DispatchShipment`) and the type model are **untouched**.

### Done (within authority)

- **Rust ok/0** (9 contracts); entrypoint `RunBestRoute` resolved in manifest + SIR.
- **VM runs the demo entry `RunBestRoute` → `2437.5`** (= 3.25 × 750.0), exercising
  filter + fold + Float comparison (in-fold) + Float multiply. The entry/UX blocker
  ("contracts execute but need `routes`/`shipment` inputs") is **resolved for
  Rust+VM**.

### Residuals pinned (out of this card's authority)

- **Ruby oof/4** — all four diagnostics in the pre-existing production contracts
  (`CalculateBestRoute` ×3, `CheckCapacity` ×1); the demo entry adds **zero** new
  diagnostics. Root cause = Ruby typechecker Float-operator over-restriction; the
  numeric-dispatch relaxation was **Rust-only** with no Ruby parity. Fixing it needs
  a **compiler change** → **Closed Surface**. Acceptance criterion "Ruby compile
  ok/0" is therefore **not reachable under this card**; routed to a Ruby
  numeric-parity follow-up.
- **ERP-P11 (new)** — `RunCapacity` / `RunDispatchDemo` compile dual-closure-clean
  but trap at the VM on a direct (non-fold) `Float < Float`
  (`Expected Integer, got: Float`). VM gap, not an app defect; **Closed Surface**
  (no VM change). Routed to a VM Float-comparison opcode parity follow-up. This is
  why `RunBestRoute`, not the capacity orchestrator, was chosen as the entry.

### Acceptance reconciliation

- Ruby ok/0 — **NOT MET**: blocked by an out-of-authority Ruby numeric-parity gap.
- Rust ok/0 — **MET** (9 contracts, 0 diagnostics).
- VM run succeeds through the demo entry "if app semantics permit" — **MET** via
  `RunBestRoute`; capacity entries pinned as ERP-P11.
- Source hash/count changes documented — **MET**.
- No external IO/clock/scheduler/DB/queue — **MET** (pure core, empty
  effects/capabilities).
- Entry is clearly demo/orchestrator fixture, not a production service loop — **MET**.

### Artifacts

- Proof: `igniter-view-engine/proofs/verify_lab_erp_logistics_demo_entry_p1.rb`
- Lab doc: `lab-docs/governance/lab-erp-logistics-demo-entry-p1-v0.md`
- Registry: `igniter-apps/erp_logistics/PRESSURE_REGISTRY.md` (ERP-P09/P10/P11 + Demo
  Entry Baseline section)
- App source: `igniter-apps/erp_logistics/example.ig`
