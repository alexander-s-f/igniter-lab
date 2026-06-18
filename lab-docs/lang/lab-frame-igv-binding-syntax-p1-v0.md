# lab-frame-igv-binding-syntax-p1-v0 — `.igv` text → ViewArtifact JSON

**Card:** `LAB-FRAME-IGV-BINDING-SYNTAX-P1` (in `igniter-ui-kit`)
**Status:** CLOSED — implemented + proven. A tiny lab-only `.igv` text syntax lowers
DETERMINISTICALLY to the already-proven ViewArtifact JSON manifest, which the existing binding host
(P16) and the P17/P18 bridges consume unchanged. `.igv` is SUGAR — not Igniter canon, no `.ig`
change, machine-free.

> `.igv` is classified as a **Projection Dialect** (status: lab; target: ViewArtifact JSON; no hidden
> runtime authority) under `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`.

## What it proves

The stack already had code proof for `ViewArtifact JSON → ui-kit/FrameRuntime → console lineage →
host-side `.ig` bridges`. P1 adds the smallest text authoring layer on top:

```text
.igv text  ──lower_igv──►  ViewArtifact JSON (serde_json::Value)  ──►  existing consumers
```

Behavior belongs entirely to the existing JSON consumers; `.igv` only produces the JSON.

## Implementation (`igniter-ui-kit/src/igv.rs`, machine-free)

A line-oriented parser + deterministic lowering. Grammar:

```text
view <screen> <layout> {
  source <name> = <Contract>                       // → sources.<name> = {contract, mode:"read"}
  field <id> <kind> "<label>" [a, b, c] required   // → regions.main.fields[]
  action <name> = <Contract> {                     // → actions.<name>
    input <key> = <expr>                            //   …input.<key>
    validate <Contract>                             //   …validate (optional)
    effect <capability_id> <operation> <scope>      //   …effect{capability_id, operation, scope}
  }
  sidebar list <source> on_select <action>          // → regions.sidebar (List)
  inspector keyvalue <bind>                          // → regions.inspector (KeyValuePanel)
  submit <action>                                    // → regions.main.submit
}
```

- `lower_igv(src) -> Result<Value, IgvError>` / `lower_igv_to_string` — the lowering.
- A small tokenizer handles `"quoted labels"` and `[option, lists]`; `//` comments + blank lines are
  ignored.
- `IgvError{ line, msg }` — 1-based source line + a stable message (`impl Display`).
- **Deterministic**: serde_json's default `Map` is sorted-key, arrays keep order → the same `.igv`
  always yields byte-identical JSON. Depends only on `serde_json`.

The canonical fixture `web/lead_review.igv` lowers to the same shape as the hand-written
`web/lead_review_bound.view.json`.

## Proof

**Native** (8 tests, `igniter-ui-kit/tests/igv_tests.rs`; the existing 34 ui-kit tests stay green →
42 total):

| acceptance | test |
|---|---|
| 1 — parser/lowering returns ViewArtifact JSON | `parse_minimal_workbench_igv` |
| 2, 4 — lowered JSON accepted by the binding host; source runs through the fixture | `igv_bound_source_runs_through_the_fixture_host` |
| 5 — actions lower to the P16/P17/P18 shape (`contract`/`input`/`effect{capability_id,operation,scope}`) | `igv_action_manifest_matches_p18_bridge_expectations` |
| (shape) — sources/regions/fields lower to the proven shapes (order preserved) | `igv_lowers_to_existing_viewartifact_shape` |
| 3 — lowering is deterministic / byte-stable | `lowering_is_deterministic_byte_stable` |
| 6 — invalid `.igv` reports a stable, line-positioned error | `invalid_igv_reports_stable_error`, `parse_error_implements_display` |
| 7 — `.igv` ≡ the hand-written bound artifact (byte-identical workbench digest) | `igv_lowers_equivalently_to_the_handwritten_bound_artifact` |

## Verification (exact)

```text
cd igniter-ui-kit && cargo test                                                   → 42 passed, 0 failed
        (8 new igv + 34 existing: binding 8 / composition 8 / forms 9 / view_artifact 9)
cd igniter-ui-kit && cargo check --features wasm --target wasm32-unknown-unknown  → Finished
rg "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport|TBackend|RocksDB" igniter-ui-kit/src
        → no machine references (clean)
```

## Acceptance vs. card (all 8)

1 ✅ parser/lowering in ui-kit returns ViewArtifact JSON · 2 ✅ a minimal `.igv` fixture lowers to a
valid artifact accepted by `binding` · 3 ✅ deterministic / byte-stable · 4 ✅ sources lower to the
P16 shape + run the fixture host · 5 ✅ actions lower to the P16/P17/P18 shape (contract/input/effect)
· 6 ✅ invalid `.igv` → stable, line-positioned diagnostics · 7 ✅ existing ViewArtifact JSON behavior
unchanged (34 tests green; `.igv` ≡ hand-written artifact) · 8 ✅ `igniter-ui-kit` stays machine-free.

## Decisions

- **lowering target is the existing JSON**: `.igv` is purely a front-end that emits the proven
  manifest; it adds no behavior and no new consumer. The same `.igv` ≡ the hand-written bound
  artifact (proven via equal workbench render digest).
- **deterministic by construction**: sorted-key `Map` + ordered arrays + `serde_json` only.
- **smallest grammar**: one bound workbench (source + fields + action with effect + regions). No full
  DSL ambition; no `.ig` change; not canon.
- **effect block is the P17/P18 object shape** (`{capability_id, operation, scope}`), so the lowered
  action is ready for the host bridges; the fixture `BoundViewHost` ignores `effect` and still runs.

## Next (gated — not started)

- richer `.igv` (multiple actions / regions / nested forms) once a second real screen needs it;
- an `.igv` → console demo (lower in the browser, run the workbench), if a live authoring demo is
  wanted;
- real executor over local TLS / SparkCRM stays behind the existing human-gated machine live gate.
