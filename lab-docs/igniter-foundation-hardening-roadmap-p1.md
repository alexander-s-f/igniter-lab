# IGNITER FOUNDATION HARDENING — unified prioritized roadmap (across 8 audits)

Status: planning artifact (synthesis of the 2026-06-26 foundation-audit sweep)
Lane: igniter-lab / cross-crate / foundation-hardening
Type: report packet / roadmap
Date: 2026-06-26
Skill: idd-agent-protocol

## Source audits (all 2026-06-26)

| # | Crate | Doc |
|---|---|---|
| 1 | igniter-tbackend | `igniter-home-lab/cards/LAB-TBACKEND-CORE-FOUNDATION-AUDIT-P1.md` |
| 2 | igniter-compiler | `lab-docs/igniter-compiler-core-foundation-audit-p1.md` |
| 3 | igniter-stdlib | `lab-docs/igniter-stdlib-core-foundation-audit-p1.md` |
| 4 | igniter-vm | `lab-docs/igniter-vm-core-foundation-audit-p1.md` |
| 5 | igniter-machine | `lab-docs/igniter-machine-core-foundation-audit-p1.md` |
| 6 | web (igniter-web + render-html) | `lab-docs/igniter-web-core-foundation-audit-p1.md` |
| 7 | igniter-server | `lab-docs/igniter-server-core-foundation-audit-p1.md` |
| 8 | frame-ui (frame/3d/gui/ui-kit/console) | `lab-docs/igniter-frame-ui-foundation-audit-p1.md` |

## Status refresh - 2026-06-27

This roadmap remains the 2026-06-26 prioritization artifact. The tiers below are
kept for historical sequencing, but current routing should start from this
refresh table, the package-local `IMPLEMENTED_SURFACE.md` files, and
`lab-docs/lang/lab-audit-foundation-status-refresh-p2-v0.md`.

| Finding family | Current status | Route now |
|---|---|---|
| Compiler parser depth + float literal crash-safety | CLOSED by `LAB-IGNITER-COMPILER-INPUT-ROBUSTNESS-P1`: parser depth is budgeted and non-finite/overflowing float literals return diagnostics. | Do not route new work to parser-depth/float-panic blockers. Remaining compiler foundation gaps are type-IR soundness, interprocedural effects, default lock policy, and deeper emitter/assembler hardening. |
| Compiler lock-on-build + dep-path containment | PARTLY CLOSED by `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2` and `LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P3`: `compile --project-root ... --locked` / `--frozen` fails missing, stale, or integrity-bad locks before emit, and local dependency paths are contained under the workspace trust root. | Remaining supply-chain work is policy/default-on choice plus registry/signing/remote-source readiness, not "lock is computed but never build-enforced" or uncontained local dep paths. |
| VM checked arithmetic, eval depth, collection budget, and step budget | CLOSED by `LAB-IGNITER-VM-EVAL-DEPTH-AND-COLLECTION-BUDGET-P2` plus the checked arithmetic sweep. | Do not cite old VM overflow, `eval_ast` native-stack, huge-range allocation, or non-progress bytecode-loop blockers as open. |
| Decimal money arithmetic + comparison | CLOSED by `LAB-STDLIB-DECIMAL-MONEY-CONTRACT-READINESS-P1` and `LAB-STDLIB-DECIMAL-MONEY-SAFE-P2`: checked i128 arithmetic, exact-only division, bounded scale, and scale-normalized comparison are implemented. | Remaining Decimal adoption blocker is host-config typed field-kind syntax for product routes, not arithmetic safety. |
| stdlib IO sandbox, render-html `safe_url`, frame-ui empty leads | CLOSED locally by `lab-stdlib-io-sandbox-hardening-p1`, `lab-igniter-web-render-html-output-safety-p1`, and `LAB-FRAME-UI-EMPTY-LEADS-PANIC-P1`. | Later IO work can focus on host-routed capability readiness. Do not re-open symlink escape, C0-control URL bypass, or empty-leads panic from the audit snapshot alone. |
| Machine signed passport data-plane | CLOSED for signed data-plane entrypoints by `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`: signed service/write paths and negative forged-passport tests exist. | Legacy unsigned entrypoints remain compatibility surfaces. New production wiring should choose signed entrypoints explicitly rather than assuming every old caller is signed. |
| IgWeb signed effect passport | CLOSED by `LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27`: IgWeb effect host signs effect passports and verifies them on the write bridge. | v0 uses a process-local signing key. Durable/operator-provided signing key configuration remains future work. |
| Inbound read hardening + loopback/live bind gate | CLOSED for body cap/read-timeout/auth composition by `lab-igniter-server-inbound-hardened-read-p28`; CLOSED for server gate API by `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`; IgWeb pre-bind wiring is live in source and indexed by `server/igniter-web/IMPLEMENTED_SURFACE.md` (`P32`). | Public bind remains closed. Remaining live-gate work is TLS/checklist/operator config, not unbounded reads or missing pre-bind refusal. |
| MCP local auth/checkpoint sandbox | CLOSED by `lab-machine-mcp-auth-checkpoint-sandbox-p30`: `tools/call` requires local authority token, checkpoint paths are root-confined, and reserved stores are refused. | This is a local stdio/env-token gate, not a signed-passport or network-auth story. |
| VM map-lambda `call_contract`, `variant_construct`, and machine fleet | CLOSED for covered parity: `lab-vm-map-lambda-callcontract-parity-p1-v0.md` and `LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5`; live recheck `cargo test --manifest-path igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep -- --nocapture` is 13/13 OK on 2026-06-27. | `rule_engine` dynamic dispatch remains governance-gated; recursive self-call/TCO and source-to-run/REPL remain separate missing surfaces. |

### Current verified next cards

- `LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS` — shared operator-config blocker for typed `Bool` Todo `done` and Decimal money routes.
- `LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P*` — replace stringly/type-name IR surfaces with an enum type model.
- `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P*` — interprocedural purity/effect summary over the existing call graph.
- Compile-lock default policy — decide whether project compile should require a current lock by default.
- `LAB-IGNITER-SERVER-LIVE-BIND-TLS-CHECKLIST-P*` — TLS/checklist/operator config before any public bind.
- `LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-P*` — multi-process/durable exactly-once and replay ordering foundation.
- `LAB-IGNITER-VM-SOURCE-RUN-REPL-P*` — DX surface for direct source execution; distinct from current `.igapp` VM runtime.
- `LAB-FRAME-UI-IDE-PREVIEW-REHOME-P2` / layout vocab / render-host work — product unpause, not crash-safety.

## The two cross-cutting roots (every audit found the same shape)

- **R1 — Design/model right, enforcement thin / mislocated / UNWIRED.** The hard
  conceptual work is done and often excellent (det_* math, SQLi-clean executors,
  default-closed allowlists, render-html safe-by-construction, the protocol that
  can't carry effect authority, the signed-passport primitive). The gap is uniformly
  that the safe path isn't the one the production code takes. **Good news: this is the
  most tractable class of work — wiring and hardening, not redesign.**
- **R2 — The loopback invariant is load-bearing for the whole transport/auth blocker
  class.** machine + server + web hold most of their severe blockers dormant on
  `127.0.0.1`; the **"#7 human-gated-live"** step is where they ALL activate at once.
  → The loopback→live transition must become a **security gate gated on a checklist**,
  not a deploy.

**Prioritization axis (used below): NOW-LIVE vs LATENT-behind-loopback.** A program
or local input triggers the now-live ones today; the latent ones need a public bind.
Honest sequencing puts now-live correctness first (it isn't gated by any future
decision) and makes the loopback gate the keystone that controls the latent class.

## The leverage map — one change, many audits closed

This is the synthesis: most findings collapse into ~10 shared levers.

| Lever | Closes (audits) | Keystone change | Size |
|---|---|---|---|
| **L1 Checked arithmetic + crash guards** | VM, compiler, stdlib | `checked_*` sweep on the ~12 infix sites; parse-depth + `eval_ast`-depth RAII guards; collection/`range` budgets; panic-free float literal | small / mechanical |
| **L2 Exact i128 Decimal** | stdlib, VM | i128 checked arith + explicit rounding on div + **scale-normalized Eq/Ord** (drop the derive); fixes money AND the cross-arch Decimal compare | small-med |
| **L3 Wire signed authority** | machine, web, server, VM | swap `verify_passport` → `verify_passport_signed` at the (few) mint points + a NEGATIVE test (forged digest must be refused) | small / call-site |
| **L4 Loopback→live security gate** | machine, server, web | structural `loopback_only`; bind-non-loopback requires a checklist token {signed passport, inbound TLS, body-cap, timeout, fail-closed auth}; **owned in igniter-server** | small-med |
| **L5 Inbound transport hardening** | machine, server, web | one shared `harden_read` (body-cap + read-timeout, before alloc) + inbound TLS via the already-pinned rustls | small / shared |
| **L6 seq_id + CAS + fsync** | TBackend, machine | server-assigned monotonic `seq_id` (ordering/idempotency/replay + restores O(log N) reads); `prepared`-as-CAS via existing `pure_core::push_once` (multi-process exactly-once, delete `single_flight`); fsync group-commit | medium |
| **L7 Global step budget + termination** | VM, compiler | one `steps_executed` counter in the bytecode loop → termination becomes a real runtime property (closes compiler's "FuelBounded runtime-trusted") | small |
| **L8 det_* + qemu golden-bit PROOF** | VM, stdlib, frame-ui, emergence | route trig through `det_*`; canonicalize f64 before any digest; run the golden-bit suite under qemu aarch64/riscv64 → claim becomes proof | small-med |
| **L9 enum IgType** | compiler | replace the stringly-typed `serde_json::Value` type-IR with a real `enum IgType` → name-only soundness holes become unrepresentable | large |
| **L10 Output safety + supply chain** | web/render-html, compiler | `safe_url` C0-strip + `esc()` `"`/`'`+attribute-context; lock-on-build + dep resolver containment | tiny / small |

## TIER 0 — Now-live correctness & safety (do first; not gated by any decision)

These break real things in the current loopback lab today; most are cheap.

- **T0.1 VM crash-safety + checked arithmetic (L1+L7).** A malformed `.ig`/SIR
  aborts the VM process today (int-overflow panic, `eval_ast` SIGABRT, `range` OOM,
  `i64::MIN÷-1`); release-mode silent wrap gives wrong money answers. The
  `checked_*`/depth-guard/step-counter sweep is mechanical and the pattern already
  exists in the crate (`num_abs`/`ipow` use `checked_*`). **Highest value-per-line.**
- **T0.2 Compiler crash-safety (L1).** Reproduced parser-depth SIGABRT + float-literal
  panic from a ~6 KB `.ig` file. One depth-guard (reuse the liveness RAII) + a
  finite-or-diagnostic float helper.
- **T0.3 Exact Decimal (L2).** Money math is silently wrong today (wrap / truncate /
  `Decimal{10,1} > Decimal{5,0}`) AND it breaks cross-arch determinism (VM compares via
  f64). The i128 fix closes both stdlib and VM at once.
- **T0.4 stdlib IO sandbox (write symlink-escape) + render-html `safe_url` XSS +
  frame-ui empty-`leads` panic (L10).** Three small, reachable fixes:
  symlink-escape-on-write (`io.rs`, canonical-parent + O_NOFOLLOW), the control-char
  scheme bypass (`render-html`, strip C0 before scheme detect), and the 1-line
  empty-`leads` guard (browser-reachable WASM abort).
- **T0.5 TBackend idempotency-in-practice (client fix).** The home-lab Spark shadow
  (and the **Hub coordinator plan**, which shadows TBackend) silently double-writes on
  retry because the mirror folds wall-clock into the fact `id`. Drop wall-clock from
  the id (`tbackend_mirror.rb:171`) → idempotency holds without touching the daemon.
  Unblocks the Hub Shadow seam. (The server-side `seq_id` keystone is T2.1.)

## TIER 1 — The controlled-activation keystone (gate + authority + transport)

This is what turns "#7 human-gated-live" from a cliff into a controlled decision.
**Do all of T1 before any non-loopback bind.**

- **T1.1 Wire signed authority (L3).** The machine ships a tested keyed-MAC signed
  passport that NOTHING in production calls (prod uses the forgeable `verify_passport`);
  the web write effect, the VM capability, and the server bearer all inherit this. Swap
  the (few) mint points to `verify_passport_signed` + add the negative test. **THE
  security keystone — closes the forgeable-authority family across 4 audits with
  call-site changes.** The web layer has exactly ONE effect-passport mint point — the
  cleanest place to demonstrate the signed path end-to-end.
- **T1.2 Loopback→live security gate (L4), owned in igniter-server.** Make
  `loopback_only` structural (default-on, cover `serve_once_effect`); make a
  non-loopback bind un-constructible without a checklist token. One gate the machine,
  server, AND web audits all asked for — locate it in the crate that owns transport.
- **T1.3 Inbound transport hardening (L5).** Shared `harden_read` (body-cap + timeout
  before allocation) closes the unbounded-OOM + slowloris pair in BOTH the machine
  ingress and igniter-server; add inbound TLS (rustls already pinned). Fix the
  fail-open empty-token auth + compose() on the machine-mode effect path.
- **T1.4 MCP auth + checkpoint sandbox (machine).** The MCP server is unauthenticated
  (any local stdio client = full machine control) and `igniter_checkpoint` is an
  arbitrary-fs-write. **Can be now-live if any untrusted local agent speaks MCP** — pull
  forward to T0 if so. Passport-gate the MCP edge (reuse ingress's verified-passport
  pattern) + path-validate checkpoint + a reserved-store firewall.
- **T1.5 Compiler supply-chain (L10).** `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`
  added explicit project-build enforcement:
  `igc compile --project-root ROOT --entry MODULE --out OUT --locked` (alias
  `--frozen`) checks committed `igniter.lock` drift/toolchain plus strict
  workspace integrity before emit. `LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P3`
  closes local dep resolver escape by refusing absolute paths, lexical `..`
  escapes, and symlink escapes outside the workspace trust root. Remaining:
  default-on policy plus registry/signing/remote-source readiness.

## TIER 2 — Durability & determinism foundation (the shared substrate)

Not purely behind-loopback — these bite on power-loss / multi-process / cross-arch.

- **T2.1 seq_id + CAS + fsync (L6).** The single highest-leverage structural change for
  TBackend AND machine: server-assigned monotonic `seq_id` (fixes idempotency, ordering,
  replay determinism, and restores O(log N) reads), `prepared`-as-durable-CAS (multi-
  process exactly-once → delete in-process `single_flight`), and fsync group-commit (no
  acked-but-lost). Closes the durability family + the TBackend root.
- **T2.2 det_* trig + qemu golden-bit PROOF (L8).** Route the VM/3D trig through `det_*`,
  canonicalize f64 before digests, and run the golden-bit suite (already in the VM tests)
  under qemu aarch64/riscv64. Turns the determinism CLAIM into a PROOF — serves the
  emergence line AND the frame-ui cross-arch differentiator AND the embedded-swarm
  (riscv64/ESP32) readiness in one move.
- **T2.3 Interprocedural effect-summary (compiler).** Fixpoint over the call graph
  already built for Tarjan SCC → closes the `pure`-contract-does-IO-via-`def`
  effect-laundering hole. Real interprocedural effect system, reusing existing machinery.
- **T2.4 Non-silent recovery (TBackend, machine).** WAL recovery currently truncates
  silently on the first bad record; surface partial/corrupt with counts + quarantine.

## TIER 3 — Deep soundness + product unpause (parallel, larger)

- **T3.1 enum IgType (L9, compiler).** The type-IR refactor — makes the name-only
  soundness holes (record/variant fields, `==`, user-`def` calls) unrepresentable. The
  language's soundness keystone; large but high-value; do once the cheap correctness wins
  land.
- **T3.2 TBackend → canon promotion (PROP-008 conformance).** With seq_id (T2.1) the lab
  adapter can be aligned to the canonical `TBackend[T]` contract (read/append/replay/
  snapshot/compact/subscribe + AppendReceipt + outcome model), feeding the canon-
  promotion path and the Hub coordinator's "minimize delta toward TBackend" thesis.
- **T3.3 frame-ui unpause (4 moves).** (1) **Re-point the IDE preview off the 91k-LOC
  Ruby `igniter-view-engine` onto the Rust projector** — retires legacy + promotes the
  Rust stack into the live IDE in one move (the paused→developing lever). (2) Recursive
  container + integer layout vocab (kills the per-screen-projector tax). (3) Enrich the
  frame data model (3D pos+topology+z+material) → a wgpu/canvas RenderHost + a dt tick
  driver (makes "3D/gamedev" real). (4) Make the console an EDITOR, not just a debugger.

## Sequencing & dependencies

```text
T0 (cheap, independent, now-live)        ──> do immediately, in parallel
   └─ unblocks: Hub Shadow seam (T0.5), correct money (T0.3), uncrashable runtime (T0.1/0.2)

T1 (gate + authority + transport)        ──> REQUIRED before any non-loopback bind / live demo over a network
   └─ T1.1 signed authority is the prerequisite for T1.2 the gate checklist

T2 (durability + determinism substrate)  ──> foundation others build on
   └─ T2.1 seq_id  unblocks T3.2 (PROP-008 conformance)
   └─ T2.2 det_*+qemu  unblocks the frame-ui cross-arch differentiator (T3.3)

T3 (deep soundness + product)            ──> parallel, larger; sequence after the cheap wins
```

Ties to live work: T0.5 + T2.1 + T3.2 are the **Hub coordinator/Dispatch** track's
TBackend dependency (Hub ships on an AR ledger, shadows TBackend, swaps when hardened).
T2.2 is the **emergence/determinism** line. T1 is the **human-gated-live** gate the
machine/web/server audits all converge on.

## The honest one-paragraph verdict

Across 8 crates the ecosystem is **design-rich and enforcement-poor**: the conceptual
hard parts are done and frequently excellent, and nearly every gap is an unwired,
opt-in, or post-hoc enforcement — the most fixable class of work. A **small set of
cheap, high-leverage levers** (checked arithmetic, exact decimal, signed-authority
wiring, the loopback gate, a shared read-hardening helper, seq_id/CAS/fsync, det_*+qemu)
closes the **majority of the severe findings across multiple crates each**. Two larger
keystones (enum IgType; the frame-ui unpause) are worth real investment but should
follow the cheap wins. Do **Tier 0 now** (it isn't gated by anything and unblocks live
work), **Tier 1 before any public bind**, and let **Tier 2/3 run as the foundation +
product tracks**.
