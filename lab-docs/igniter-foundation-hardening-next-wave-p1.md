# IGNITER FOUNDATION HARDENING — NEXT WAVE (curator worklist)

Status: LIVING worklist (update statuses in place; do NOT snapshot a new dated copy)
Lane: igniter-lab / cross-crate / foundation-hardening
Type: wave plan / curator menu
Date opened: 2026-06-26
Skill: idd-agent-protocol

> Companion to `igniter-foundation-hardening-roadmap-p1.md` (the why/priorities) and the
> 8 source audits in `lab-docs/` + `igniter-home-lab/cards/`. This doc is the **menu of
> focus cards** a curator agent works through — slowly, one at a time — slicing each into
> detailed, dispatchable agent cards.

---

## How the curator works this doc

You are the curator. Your job is **not** to implement — it is to turn each focus card
below into the smallest set of dispatchable agent cards, in the right order, without
rushing. Per the IDD protocol:

1. **One focus card at a time, by priority + dependency.** Tier order T0 → T1 → T2 → T3.
   Inside a tier, take the cheapest / most-unblocking first. Never open the next focus
   card until the current one's agent cards are dispatched (or explicitly parked).
2. **Verify-first before slicing.** Re-read the named source-audit anchors against LIVE
   code — the audits are 2026-06-26 point-in-time; a `file:line` may have moved, or a
   fix may already have landed. Confirm the finding still exists before writing a card.
3. **Slice into the smallest coherent agent cards.** A focus card may become 1 card or
   several (the "slice hint" suggests how many). Each agent card must carry: the exact
   change + anchors, the authority surface (what it may touch / what stays closed), an
   acceptance test, and the evidence command. Follow IDD card hygiene (whole card in one
   fenced `text` block; `Card:` line inside the fence).
4. **Respect the hard gate (see below).** T1 cards make the *human-gated-live* step safe;
   they are the PREREQUISITE for a public/non-loopback bind, not permission to cross it.
   The curator surfaces "T1 complete" as a gate decision for the human — never bundles a
   live bind into a card.
5. **Track status here, in place.** Per focus card: `todo → verifying → slicing →
   dispatched → done`. Update this doc, don't write a fresh dated one.
6. **Stop when structure stops buying clarity.** A trivial one-line fix (e.g. the
   empty-`leads` guard) can be a single card or a fast-lane receipt — don't ceremonialise.

**Suggested first sprint** (cheapest, highest-leverage, fully ungated): NW-T0-1,
NW-T0-3, NW-T0-5, NW-T0-6, NW-T0-7. These close reproduced crashes, wrong-money, the one
real XSS, a browser panic, and unblock the Hub Shadow seam — all in the now-live lab.

**HARD GATE:** ⛔ Do NOT dispatch any card that binds a non-loopback address, exposes a
public listener, or wires a real external executor until ALL of T1 is `done` AND a human
signs the loopback→live checklist. Most machine/server/web blockers are dormant on
`127.0.0.1` and go live the instant that bind happens.

---

## TIER 0 — now-live correctness & safety (start here; ungated)

| Status | Card | Lever | Size | Source anchor |
|---|---|---|---|---|

### ▢ NW-T0-1 · VM crash-safety + checked arithmetic
- **L1+L7 · S(mechanical) · vm audit §B-A1/A2/A3/A4.** A malformed `.ig`/SIR aborts the
  VM process today; release-mode silent wrap gives wrong money answers.
- Anchors: int `+/-/*` at `vm.rs:411/449/485` + eval_ast `:4108/4136/4162` + unified
  `:5909/5939/5967`; `i64::MIN÷-1` `:527`; unary neg `:2777/4355`; `eval_ast` `Box::pin`
  native-recursion (no depth guard, only `MAX_CALL_DEPTH=64` on calls); unbounded `range`
  `:1878/4580`.
- Acceptance: `i64::MAX+1`, `i64::MIN/-1`, deep-nested-expr lambda, `range(0,5e7)` each
  return a clean runtime-error Value, not a panic/SIGABRT/OOM. Pattern already exists
  (`num_abs`/`ipow` use `checked_*`).
- Slice hint: 2–3 cards (checked-arith sweep / eval_ast+from_json depth-guard /
  collection budget). Deps: none.

### ▢ NW-T0-2 · Compiler crash-safety
- **L1 · S · compiler audit §B-C1/B-C2.** Reproduced parser-depth SIGABRT + float-literal
  panic from a ~6 KB `.ig` file.
- Anchors: `parser.rs:3293/3661` (recursion, no depth guard — reuse the `liveness.rs` RAII);
  `parser.rs:3630/1256` (`from_f64().unwrap()`).
- Acceptance: `((((1))))`×6k and a 400-nines float literal each produce an `OOF-*`
  diagnostic, not a crash. Slice hint: 1–2 cards. Deps: none.

### ▢ NW-T0-3 · Exact i128 Decimal (money + cross-arch)
- **L2 · S-M · stdlib audit §B-D1..4 + vm audit §B-B1/B2.** Money math is silently wrong
  today (wrap / truncate / `Decimal{10,1} > Decimal{5,0}`) AND it breaks cross-arch
  determinism (VM compares via f64).
- Anchors: `igniter-stdlib/src/decimal.rs` (unchecked i64 add/sub/mul, truncating div→scale-0,
  derived `Ord`); VM `vm.rs:574/1823/3181/5346` (Decimal compare via `to_f64`), `:550`
  (scale-naive `==`), `decimal(v,s)` builtin `:1086`.
- Acceptance: i128 checked arith (error not wrap); explicit rounding mode on div;
  scale-normalized `Eq`/`Ord` (`1.5 == 1.50`; `1.0 < 5.0`); a single `decimal_cmp` used at
  all VM sites. Slice hint: 2 cards (stdlib Decimal type / VM compare+eq sites). Deps: none
  (do before NW-T2-2 so the determinism proof is clean).

### ▢ NW-T0-4 · stdlib IO sandbox — write symlink-escape + substring gate
- **L10 · M · stdlib audit §B-I1/B-I2.** Symlink-escape on write-to-new-file; the sandbox
  gate is a `contains("/igniter-stdlib/out")` substring on a hardcoded path.
- Anchors: `io.rs:114-128` (lexical `clean_path`, canonical re-check skipped when target
  absent), `:363` (write follows symlink), `:80` (substring gate).
- Acceptance: writing through a symlinked sandbox subdir is refused; the sandbox root is a
  capability-supplied canonical-prefix (not a substring). Consider routing `stdlib.IO`
  through the hardened `igniter-machine` executor instead. Slice hint: 1 card. Deps: none.

### ▢ NW-T0-5 · render-html safe_url XSS + esc attribute-context
- **L10 · tiny · web audit §B-A1 + PROBLEM(esc).** `safe_url` control-char scheme bypass
  (`java\nscript:` → treated relative → browser strips `\n` → executes); `esc()` lacks
  `"`/`'`.
- Anchors: `igniter-render-html/src/lib.rs:77` (safe_url), `:58` (escape); the shared `esc`
  in `gui/src/lib.rs:125`, `ui-kit/src/lib.rs:355`.
- Acceptance: `java\tscript:`/`\x01…`/`//evil` rejected by safe_url; `esc` escapes `"`/`'`
  with an attribute-vs-text distinction; a fuzz test over the scheme stays green. Slice
  hint: 1 card. Deps: none.

### ▢ NW-T0-6 · frame-ui empty-leads panic guard
- **L1 · 1-line · frame-ui audit §B-A1.** `workbench_from_value` validates `fields` not
  `leads`; `self.leads[0]` panics — browser-reachable WASM abort.
- Anchors: `ui-kit/src/view_artifact.rs:160`, `composition.rs:90`, `wasm.rs:69`.
- Acceptance: `"data":{"leads":[]}` returns a `ViewError`, not a panic. Slice hint: fast-lane
  (1 tiny card or receipt). Deps: none.

### ▢ NW-T0-7 · TBackend client id derivation (unblocks Hub Shadow)
- **(client fix) · S · tbackend audit §B1 + Hub plan.** The home-lab Spark shadow — and the
  Hub coordinator plan that shadows TBackend — silently double-write on retry because the
  mirror folds wall-clock into the fact `id`.
- Anchors: `igniter-home-lab/apps/spark-availability-ledger-lab/.../tbackend_mirror.rb:171`
  (`time_key(observed_at)` in the id).
- Acceptance: the fact `id` is a pure function of domain identity
  (`store:record:event[:lock_version]`); a retried write replays (one row), not duplicates.
  Slice hint: 1 card. Deps: none (the server-side `seq_id` keystone is NW-T2-1).

---

## TIER 1 — gate + authority + transport (do before ANY public bind — see HARD GATE)

### ▢ NW-T1-1 · Wire the signed passport (THE security keystone)
- **L3 · S(call-site) · machine §B-A1, web §B-B1, server §B5.** The machine ships a tested
  keyed-MAC signed passport that production never calls (it uses the forgeable
  `verify_passport`); web + server + VM inherit this.
- Anchors: machine prod sites `coordination.rs:304/625`, `write.rs:232`, `service_loop.rs:213`
  → `verify_passport_signed` + a `PassportVerifier` on `CoordinationHub`; web's ONE effect-
  passport mint point `host_binding.rs:414`; server `effect_host` forwarding.
- Acceptance: a hand-constructed passport with a forged `evidence_digest` is REFUSED
  everywhere (a negative test that fails today and passes after). Slice hint: 2–3 cards
  (machine wiring + negative test / web mint point / server). Deps: none — but it is the
  prerequisite for NW-T1-2's checklist.

### ▢ NW-T1-2 · Loopback→live security gate (owned in igniter-server)
- **L4 · S-M · server §I2/SUPER-COOL, machine §I3, web §I2.** Make `loopback_only` structural
  (default-on, cover `serve_once_effect`); make a non-loopback bind un-constructible without
  a checklist token {signed passport wired, inbound TLS, body-cap, timeout, fail-closed auth}.
- Acceptance: constructing a public bind without the checklist fails closed at compile/config
  time; the checklist is one named gate the machine/web reuse. Slice hint: 1–2 cards. Deps:
  NW-T1-1, NW-T1-3 (the checklist references them).

### ▢ NW-T1-3 · Inbound transport hardening (shared)
- **L5 · S(shared) · machine §B-B1/B2/B3, server §B-C1/2/3, web §B-C.** Unbounded body→OOM,
  no read-timeout→slowloris, plaintext, fail-open empty-token auth, auth not composed on the
  machine-mode effect path.
- Anchors: shared `read_request`/`read_server_request` (server `host.rs:213` + `effect_host.rs:156`;
  machine `ingress.rs:1053`); `AuthTokenApp` empty-token `middleware.rs:91`; machine-mode no
  `compose()` `igweb-serve.rs:300/328`.
- Acceptance: one `harden_read` (body-cap + read-timeout before alloc) used by all read loops;
  inbound TLS (rustls already pinned); auth fail-CLOSED on empty token + `compose()` on
  machine-mode; strip inbound `x-auth-ok`. Slice hint: 2–3 cards. Deps: none.

### ▢ NW-T1-4 · MCP auth + checkpoint sandbox + reserved-store firewall (machine)
- **machine §B-A3/B-A4 + PROBLEM(store-poison).** ⚠️ **May be NOW-LIVE** if any untrusted local
  process speaks MCP (no-auth = full machine control) — if so, pull to T0.
- Anchors: `bin/mcp.rs:922` (no auth), `:601`→`machine.rs:436` (checkpoint arbitrary-fs-write),
  client-writable `__*__`/`RECEIPTS_STORE`.
- Acceptance: MCP `tools/call` gated by a verified passport (reuse the ingress pattern) with
  per-tool scopes; `checkpoint` path-validated; writes to reserved stores refused. Slice hint:
  2 cards. Deps: NW-T1-1 (reuse the verifier).

### ▢ NW-T1-5 · Compiler supply-chain integrity
- **L10 · S · compiler §B-I1/B-I2.** The sha256 lock is computed but never enforced on the
  build path (opt-in `igc verify` only); the dep resolver has no symlink/`..` containment.
- Anchors: `main.rs:501`/`project.rs:302` (lock not read on compile); `project.rs:894/1635`
  (lexical normalize, no containment).
- Acceptance: `compile` verifies the lock (warn/`--frozen` fail); a `resolve_within_root`
  (canonicalize + `starts_with`) gates dep paths/source roots/file collection. Slice hint:
  1–2 cards. Deps: none.

---

## TIER 2 — durability & determinism substrate

### ▢ NW-T2-1 · seq_id + CAS + fsync (highest structural leverage)
- **L6 · M · tbackend §B2/B3 + machine §B-C1/B-C3.** Server-assigned monotonic `seq_id`
  (fixes idempotency/ordering/replay + restores O(log N) reads); `prepared`-as-durable-CAS
  via the existing `pure_core::push_once` (multi-process exactly-once → delete `single_flight`);
  fsync group-commit (no acked-but-lost).
- Acceptance: append returns a monotonic `seq_id`; two processes on one key execute the effect
  once; an acked write survives power-loss (fsync). Slice hint: 3 cards (seq_id / CAS-on-prepared /
  fsync). Deps: none — but unblocks NW-T3-2 (PROP-008 conformance).

### ▢ NW-T2-2 · det_* trig + qemu golden-bit PROOF
- **L8 · S-M · vm §I4 + stdlib §I1 + frame-ui §determinism-crux.** Route VM/3D trig through
  `det_*`; canonicalize f64 before any digest; run the golden-bit suite (already in the VM
  tests) under qemu aarch64/riscv64.
- Anchors: `igniter-3d/src/lib.rs:72` (std `sin/cos`); `igniter-frame` `world_digest` over raw
  f64; `vm/tests/stdlib_math_det_tests.rs` + `stdlib_random_tests.rs` (the golden vectors).
- Acceptance: the golden-bit + PRNG suites pass bit-identically under qemu aarch64 (and
  riscv64 if available) → the determinism CLAIM becomes a PROOF. Slice hint: 2 cards (det_*
  routing+digest canonicalization / qemu CI runner). Deps: NW-T0-3 (exact decimal) for clean
  numeric digests.

### ▢ NW-T2-3 · Global step budget / runtime termination
- **L7 · S · vm §B-C1 + compiler §B-U6.** No global instruction budget in the bytecode VM →
  termination is a compiler-only convention. Add one `steps_executed` counter in
  `execute_with_grants` → termination becomes a real runtime property.
- Acceptance: an unbounded loop / non-shrinking recursion errors at a budget, not spins. Slice
  hint: 1 card (can merge into NW-T0-1). Deps: none.

### ▢ NW-T2-4 · Interprocedural effect-summary (compiler)
- **compiler §B-U5.** A `pure` contract can do IO via a `def` (purity = inline `stdlib.IO.`
  prefix scan only). Compute a per-`def` transitive effect summary over the call graph already
  built for Tarjan SCC; have purity consult it.
- Acceptance: `pure` contract calling a `def` that does IO → `OOF-M1`. Slice hint: 1 card.
  Deps: none.

### ▢ NW-T2-5 · Non-silent recovery (TBackend + machine WAL)
- **tbackend §B8/P5-class + machine §B-C2.** Recovery `break`s silently on the first bad record,
  dropping all subsequent intact records with no signal.
- Acceptance: recovery surfaces partial/corrupt with a count + quarantines the bad record,
  continuing past it where safe. Slice hint: 1–2 cards. Deps: NW-T2-1 (seq_id makes "continue
  past" safe).

---

## TIER 3 — deep soundness + product unpause (parallel, larger)

### ▢ NW-T3-1 · enum IgType (compiler soundness keystone)
- **L9 · LARGE · compiler §root R1 + S1.** Replace the stringly-typed `serde_json::Value`
  type-IR with a real `enum IgType` → name-only soundness holes (record/variant fields, `==`,
  user-`def` calls, match-widening) become unrepresentable.
- Acceptance: `Collection[Integer]` no longer assignable to `Collection[Text]` at a record
  field; user-`def` calls are arity+type-checked; the `Unknown` leakage stops being silent.
  Slice hint: a multi-card sub-wave (its own track). Deps: do after the cheap T0 correctness
  wins.

### ▢ NW-T3-2 · TBackend → PROP-008 canon promotion
- **tbackend + Hub plan.** With `seq_id` (NW-T2-1) align the lab adapter to the canon
  `TBackend[T]` contract (read/append/replay/snapshot/compact/subscribe + AppendReceipt +
  outcome model) → the canon-promotion path + the Hub "minimize delta toward TBackend" thesis.
- Slice hint: a sub-wave (the C0–C6 conformance track already sketched in
  `project-tbackend-distribution-wave`). Deps: NW-T2-1.

### ▢ NW-T3-3 · frame-ui unpause (4 moves)
- **frame-ui audit §UNPAUSE.** (a) **Re-point the IDE preview off the 91k-LOC Ruby
  `igniter-view-engine` onto the Rust projector** — retires legacy + promotes the Rust stack
  into the live IDE (the paused→developing lever); (b) recursive container + integer layout
  vocab; (c) enrich the frame data model (3D pos+topology+z+material) → a wgpu/canvas RenderHost
  + a dt tick driver; (d) make the console an EDITOR.
- Slice hint: 4 separate cards/sub-tracks; (a) needs its own IDE-preview-rehome scoping card
  first. Deps: (c) pairs with NW-T2-2 for the cross-arch differentiator.

---

## Status legend & dependency summary

`▢ todo · ◐ verifying/slicing · ▷ dispatched · ✔ done`

```text
T0: all independent, ungated → first sprint = T0-1,3,5,6,7
T1: T1-1 (signed authority) → unblocks T1-2 (gate) ; T1-3 standalone ; T1-4 reuses T1-1's verifier
    ⛔ ALL of T1 + human checklist sign-off REQUIRED before any non-loopback bind
T2: T2-1 (seq_id) → unblocks T3-2 ; T2-2 (det_*+qemu) ← needs T0-3 ; unblocks frame-ui differentiator
T3: parallel, larger ; T3-1 after the cheap T0 wins ; T3-2 after T2-1 ; T3-3(c) pairs with T2-2
```

Curator: keep this section's statuses current as you dispatch. When a focus card's agent
cards all close, mark it ✔ and record the closing evidence pointer (test/PR) inline.
