# Card: LAB-MACHINE-CAPSULE-MANAGER-P1 — capsule control panel (first slice)

**Status: IMPLEMENTED (steps 1, 2, 4) 2026-06-15; step 3 (MCP) next.** The agent
control-panel foundation: snapshot machine state into immutable capsules, fork what-ifs,
activate any, cycle them like a filmstrip.

## Model (accepted)

- **Capsule = immutable frame** — a deterministic byte image of full machine state
  (contracts + facts + observations).
- **Activation = a pure pass over a frame:** `(capsule, request) -> result`, or
  `-> result + forked capsule`. Frames are never mutated in place; a fork is a new
  frame (a new fact/branch, not a mutation of the past).
- This makes the **filmstrip deterministic** and **parallel-safe** (immutable inputs).
- Naming: agent-facing = **capsule**; internal = `SemanticImage` / capsule bytes. NOT
  "container" (avoids Docker/process-isolation connotations).

## Done

**Step 1 — machine bytes API** (`machine.rs`): `checkpoint_bytes()` / `resume_bytes()`
(in-memory capsules, no file needed). Made it **deterministic** for content-addressable
frames: `SemanticImage.contracts` is a `BTreeMap`, facts sorted by
`(store, key, transaction_time, id)`. `checkpoint`/`resume` are now thin file wrappers.
Proof `test_machine_checkpoint_bytes_roundtrip`: **byte-identical roundtrip**
(`checkpoint_bytes → resume_bytes → checkpoint_bytes` equal, under out-of-order facts);
file `.igm` bytes == `checkpoint_bytes`; resumed frame still dispatches + preserves facts.

**Step 2 — `CapsuleManager`** (`src/capsule.rs`, Rust-local, no MCP yet): named registry
of frames. `snapshot(name, &machine)`, `put(name, bytes)`, `list()`, `instantiate(name)`
(materialize a fresh independent machine), `activate(name, contract, inputs)` (read-only
dispatch over a frame), `fork(from, new_name, extra_facts)` (branch + patch + freeze).

**Step 4 — filmstrip proof** `test_capsule_filmstrip`: one `base` frame → forked into
`hi` (balance 1000) / `lo` (balance 10); the **same activation diverges** per frame;
**base is untouched** (immutability); dispatch works on resumed frames; registry lists
all. **11/11 machine tests pass.**

## Next

**Step 3 — MCP thin tools** (facade over `CapsuleManager`): `capsule_snapshot`,
`capsule_list`, `capsule_activate`, then `capsule_fork`, then `capsule_diff`. This is
where the agent gets the live control panel. (`capsule_diff` = frame A vs B fact/state
delta — the debugger lens.)

## Closed surfaces (this card)

- No durable DB; no scheduler; no distributed worker.
- No live mutation of a capsule (forks only).
- No MCP authority beyond a local tool facade.
- No debugger UI yet.
- No production semantics / canon claim.
