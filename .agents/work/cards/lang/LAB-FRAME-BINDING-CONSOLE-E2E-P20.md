# LAB-FRAME-BINDING-CONSOLE-E2E-P20

Status: CLOSED 2026-06-16 — implemented + proven (host-side e2e, no live IO)
Lane: frame / host-bridge / console demo
Owner: Opus

## Result

Proof doc: `lab-docs/lang/lab-frame-binding-console-e2e-p20-v0.md`. Added a tiny host-side helper
`FrameBindingEffectResult::to_host_action_json(...)` (in `igniter-machine/src/frame_binding_effect.rs`)
that projects the P18 bridge result into a plain `HostActionRecord` JSON (effect_receipt_id /
effect_state=`WriteState::as_str()` / invoke_digest; no secret). Integration test in
`igniter-machine/tests/frame_binding_console_e2e_tests.rs` drives the FULL loop: real Add capsule
invoke + fake capability-IO effect → receipt → `to_host_action_json` → `Console::attach_action_json`
→ `lineage_json` + `render_svg` show "action: record" + "receipt: committed IO.FrameFixture:idem-1".
The e2e is a DEV-dep (machine→console/ui-kit) — kernel test reaching up; console/ui-kit stay
machine-free (frame `default-features=false` → no `machine` feature → no cycle).

**Verification:** `cd igniter-machine && cargo test --no-default-features` → **279 passed, 0 failed**
(276 + 3 e2e). `cd igniter-console && cargo test` → **21** (unchanged). `cd igniter-ui-kit && cargo
test` → **42** (unchanged). Boundary `rg ... igniter-console igniter-ui-kit` → only a comment line in
ui-kit Cargo.toml (no dependency). All 8 acceptance: committed receipt, plain-JSON conversion, console
accepts+stores, lineage_json full fields, render compact action+receipt, idempotent replay one
receipt-id, unknown→`unknown_external_state` no panic, console/ui-kit machine-free. The whole
`.ig`-binding contour is now proven end-to-end in lab (UI path machine-free at every layer). Next
gates (NOT started): live browser demo (presentation), richer `.igv`, real executor (human-gated).
Skill: idd-agent-protocol

## Intent

Prove the full lab loop, without live IO:

```text
.igv / ViewArtifact action
  -> P17/P18 host bridge
  -> real capsule invoke
  -> fake capability-IO effect receipt
  -> HostActionRecord JSON
  -> igniter-console attach_action
  -> console lineage panel shows action + receipt
```

This is the first end-to-end demo glue between the host-side binding bridge and the machine-free
console. It must preserve the boundary: the console consumes plain data only.

## Verify-First Inputs

Read live code before designing:

- `igniter-ui-kit/src/igv.rs`
- `igniter-ui-kit/src/binding.rs`
- `igniter-ui-kit/web/lead_review.igv`
- `igniter-console/src/lib.rs`
- `igniter-console/src/wasm.rs`
- `igniter-console/tests/console_action_lineage_tests.rs`
- `igniter-machine/src/frame_binding.rs`
- `igniter-machine/src/frame_binding_effect.rs`
- `igniter-machine/tests/frame_binding_effect_tests.rs`
- `lab-docs/lang/lab-frame-igv-binding-syntax-p1-v0.md`
- `lab-docs/lang/lab-frame-console-action-lineage-p19-v0.md`
- `lab-docs/lang/lab-frame-ig-binding-effect-bridge-p18-v0.md`

Live code wins over old docs.

## Required Boundary

- `igniter-console` must not depend on `igniter-machine`.
- `igniter-ui-kit` must not depend on `igniter-machine`.
- Any host glue that knows about `FrameBindingEffectBridge`, passports, receipts, or
  `CoordinationHub` must live outside console/ui-kit.
- No real HTTP/TLS/SparkCRM/live executor.
- Use a fake/local executor only.

The point is to serialize host bridge output into `HostActionRecord` data and feed that into the
console.

## Suggested Shape

Prefer the smallest proof harness:

1. Reuse the P18 fixture: real Add capsule / `FrameBindingEffectBridge` / fake executor.
2. Run a declared action and get `FrameBindingEffectResult`.
3. Convert that result into a `HostActionRecord` JSON value:

```json
{
  "action_id": "frame-action-1",
  "action_name": "record",
  "contract": "Add",
  "pool_id": "svc",
  "invoke_digest": "...",
  "effect_receipt_id": "IO.FrameFixture:idem-1",
  "effect_state": "committed",
  "idempotency_key": "idem-1",
  "correlation_id": "frame-corr-1"
}
```

4. Feed that JSON to `Console::attach_action_json` or `WasmConsole.attach_action`.
5. Assert `lineage_json` and rendered SVG show the action/receipt lineage.

If adding a tiny helper type makes sense, keep it host-side. Do not put machine concepts inside
`igniter-console`.

## Acceptance

1. A host-side proof runs the P18 bridge and produces a committed fake effect receipt.
2. The proof converts the bridge output to a plain `HostActionRecord` JSON.
3. `Console::attach_action_json` accepts the JSON and stores it on the selected/live frame.
4. `Console::lineage_json` includes full action/receipt fields.
5. `Console::render_svg` shows compact action + receipt state/id.
6. Same idempotency key replays through the host bridge and console still shows one receipt id.
7. Unknown/timeout fake executor maps to `effect_state = "unknown_external_state"` and renders
   without panic.
8. Boundary grep proves console/ui-kit remain machine-free.

## Tests

Add tests wherever the dependency direction is cleanest. Likely options:

- a host-side integration test in `igniter-machine/tests/...` that depends on console only if that
  dependency already exists or is acceptable;
- a proof-local harness/doc if adding crate dependencies would invert architecture.

Do not force a bad crate dependency just to make a single test convenient. If direct Rust integration
would create a dependency cycle, write a deterministic JSON handoff proof instead:

- machine test proves bridge result -> `HostActionRecord` JSON shape;
- console test proves that exact JSON shape renders.

Document the split clearly.

## Verification

Run at minimum:

```bash
cd igniter-machine && cargo test --no-default-features
cd igniter-console && cargo test
cd igniter-ui-kit && cargo test
rg -n "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport|TBackend|RocksDB" igniter-console igniter-ui-kit
```

If a browser/WASM demo is touched:

```bash
cd igniter-console && cargo build --release --target wasm32-unknown-unknown --features wasm
```

## Deliverables

- host/demo glue or split proof, whichever preserves dependencies;
- tests/proof for the acceptance list;
- proof doc: `lab-docs/lang/lab-frame-binding-console-e2e-p20-v0.md`;
- close this card with exact commands and pass counts.

## Closed Surface

Not in this card:

- no live SparkCRM executor;
- no HTTP/TLS/network;
- no new `.igv` grammar beyond P1;
- no console dependency on machine;
- no product IDE shell;
- no canon language change.

This card proves the handoff from host bridge receipts to console-visible lineage, nothing more.
