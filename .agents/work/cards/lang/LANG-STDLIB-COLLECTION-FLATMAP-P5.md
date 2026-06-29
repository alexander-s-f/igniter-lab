# LANG-STDLIB-COLLECTION-FLATMAP-P5

Status: CLOSED (2026-06-29) — inventory entry + digest landed; new digest 31934924…ddc1a86a
Lane: lang / stdlib / collection / inventory
Mode: bounded implementation
Skill: idd-agent-protocol

## Goal

Promote the now-implemented `stdlib.collection.flat_map` surface into the canon stdlib inventory:

- add or update the `stdlib.collection.flat_map` entry in
  `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json`;
- recompute `stdlib_surface_digest`;
- prove the inventory entry matches the live Ruby + Rust + VM surface;
- keep this card **inventory/proof only**.

This is the follow-up explicitly named by `LANG-STDLIB-COLLECTION-FLATMAP-P4`.

## Context

The implementation chain is now:

1. `LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1` — readiness/proposal packet.
2. `LANG-STDLIB-COLLECTION-FLATMAP-P3` — canon Ruby `typechecker.rb` implementation.
3. `LANG-STDLIB-COLLECTION-FLATMAP-P4` — lab Rust parity:
   - Rust TC: `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]`;
   - lambda param binds to collection element type, not the old Integer placeholder;
   - one-level unwrap, no double-wrap;
   - `OOF-COL1`, `OOF-COL2`, `OOF-COL9`;
   - emitter emits `stdlib.collection.flat_map`;
   - `and_then` remains Result/Option-monadic.

`P4` commit: `bd6f84c lang: add collection flat_map parity`.

Existing precedent:

- `LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5` — map/filter/count inventory + digest.
- `LANG-STDLIB-COLLECTION-APPEND-PROP-P4` — append inventory/digest update after parity.
- `LANG-STDLIB-COLLECTION-CONCAT-PROP-P3` — concat inventory/digest update.

## Required Verify-First Pass

Before editing, verify live state from source, not from stale docs:

1. In `igniter-lang`, inspect:
   - `lib/igniter/typechecker.rb` for `flat_map` support and diagnostics;
   - `docs/spec/stdlib-inventory.json` current shape/digest;
   - any existing scripts/tests used to recompute `stdlib_surface_digest`.
2. In `igniter-lab`, inspect:
   - `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`;
   - `lang/igniter-compiler/src/emitter.rs`;
   - `lang/igniter-compiler/tests/collection_flat_map_tests.rs`;
   - `LANG-STDLIB-COLLECTION-FLATMAP-P4.md`.
3. Confirm whether `stdlib.collection.flat_map` is absent from inventory or present but stale.

Do not infer entry fields from memory alone.

## Implementation Scope

### Expected inventory entry

Use the exact schema already present in `stdlib-inventory.json`. The entry should be consistent with
map/filter/append/concat style.

Expected semantic shape:

- `canonical_name`: `stdlib.collection.flat_map`
- `semantic_ir_name`: `stdlib.collection.flat_map`
- `aliases`: source alias `flat_map`
- `category`: `collection`
- `lifecycle_status`: likely `lab-implemented` unless the inventory convention proves another value
- `semantic_stability`: use the nearest collection-HOF precedent
- `lowering_status`: `dual-toolchain`
- `compatibility_status`: use collection precedent
- `fragment_class`: use collection precedent
- `purity`: `pure`
- `deterministic`: `true`
- `totality`: use collection-HOF precedent; if partial/recovering, explain diagnostics
- `type_params`: `["T", "U"]`
- `input_signature`: `["Collection[T]", "T -> Collection[U]"]` or exact local convention
- `output_signature`: `Collection[U]`
- `diagnostics`: `["OOF-COL1", "OOF-COL2", "OOF-COL9"]`
- `failure_behavior`: wrong arity/non-lambda/non-collection/scalar body reported by diagnostics;
  Unknown remains permissive where existing TC policy requires it
- `authority_surface`: `none`
- `proof_lineage`: include P1/P3/P4 and the new P5 proof
- `examples`: include one one-level-unwrap example, e.g.
  `flat_map([[1], [2]], xs -> xs) -> [1, 2]`
- `compatibility_note`: mention `and_then` is a separate Option/Result-monadic surface and is not
  aliased to collection `flat_map`
- `owner_surface`: Ch8 / stdlib collection surface, following local convention

If the live inventory uses different field spelling or status vocabulary, follow live inventory and
explain the delta in the closing report.

### Digest

Recompute `stdlib_surface_digest` using the existing canonical method. Do **not** hand-edit a guessed
digest.

If no script exists, derive the method from the existing inventory note:

> canonical re-serialization of entries sorted by canonical_name with entry_digest fields stripped

Then write a tiny local proof script only if necessary, and keep it in the same proof location/style
used by existing collection inventory cards.

## Out Of Scope

- No compiler behavior changes.
- No Ruby behavior changes unless verify-first proves the inventory entry cannot honestly describe live Ruby.
- No VM/runtime changes.
- No parser/classifier/emitter changes.
- No app fixture edits.
- No broad collection algebra work (`zip`, `take`, `drop`, `find`, `any`, `all`, `group_by`).
- No promotion to production/stable unless the inventory precedent explicitly requires it.

## Acceptance

- [x] `stdlib.collection.flat_map` entry exists in `stdlib-inventory.json` (was absent; added).
- [x] Entry fields match P3/P4 behavior (mirrors the `filter_map` precedent: `type_params [T,U]`,
      `input_signature ["Collection[T]","(T) -> Collection[U]"]`, `output_signature "Collection[U]"`).
- [x] `aliases` includes source alias `flat_map`.
- [x] `diagnostics`: `["OOF-COL1","OOF-COL2","OOF-COL9"]`.
- [x] `lowering_status: "dual-toolchain"` (Ruby P3 + Rust P4 both implement it).
- [x] `proof_lineage` names P1/P3/P4/P5.
- [x] `stdlib_surface_digest` recomputed by the canonical method (verified: the same method
      reproduces the OLD digest before update — proving the reproduction is correct, not guessed).
- [x] Bidirectional: the entry names the live dispatch/SIR surface (`stdlib.collection.flat_map` in
      Ruby `COLLECTION_HOF_FNS` + Rust TC arm + emitter qualification + VM handler) and that live
      surface now has an inventory entry.
- [x] `and_then` stays a separate Option/Result-monadic surface (compatibility_note states it; it is
      NOT aliased to collection flat_map).
- [x] P4 regression green: `collection_flat_map_tests` 7/7.
- [x] Proof script added + passes (`verify` reproduces stored digest; `update` recomputes).
- [x] `git diff --check` clean in both repos.
- [x] Closing report + next route below.

## Report (2026-06-29)

Inventory promotion of `stdlib.collection.flat_map` in canon (`igniter-lang`). Verify-first
confirmed flat_map was absent from the inventory and live in both compilers + VM (P3/P4).

Digest method (no script existed): the inventory note + `LANG-STDLIB-ENTRY-CONTRACT-P3` §4.4 define
it as `sha256(canonical_json(entries.sort_by{canonical_name}.map{reject "entry_digest"}))` with
`canonical_json` = recursively key-sorted compact JSON. I wrote a guarded recompute script
(`igniter-lang/experiments/stdlib_collection_flatmap_proof/inventory_digest_p5.rb`, gitignored like
every sibling proof runner) that **first proves it reproduces the CURRENT stored digest**
(`f7964a7b…fe966f`) before trusting it — then adds the entry and recomputes.

- OLD digest: `f7964a7b868c7756cecc41268cddf8aa8d158aec83e20e7610401c4497fe966f`
- NEW digest: `31934924da8a451687830feb1f9a6d3eabe524b69248b068ae70d663ddc1a86a` (re-reproduces
  idempotently in `verify` mode after the write).

Entry mirrors the `filter_map` precedent (closest `[T,U]` collection HOF): `lab-implemented` /
`experiment-pass` / `dual-toolchain` / `pure` / `total`, diagnostics COL1/COL2/COL9, example
`flat_map([[1],[2]], xs -> xs) -> [1, 2]`, and a compatibility_note recording one-level unwrap, the
Unknown-permissive policy, the `and_then` separation, and the lab-Rust array-literal-in-lambda caveat.
The file change is surgical (50 ins / 2 del — only the entry + digest + note; `pretty_generate`
matched the existing format, no full reformat).

Repo boundaries: only `igniter-lang/docs/spec/stdlib-inventory.json` changed in the authority repo;
the proof script is gitignored; `igniter-lab` carries this card only (no compiler/runtime changes).
`git diff --check` PASS in both.

Next route: **broad collection algebra parity** — `LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1`
(promote the lab-ahead, proven, deterministic ops `zip`/`take`/`drop`/`find`/`any`/`all` to canon)
from the horizon roadmap. The flat_map wave (P1 PROP → P3 Ruby → P4 Rust → P5 inventory) is complete.

## Suggested Verification

Minimum:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_flat_map_tests
git diff --check
```

If a proof runner exists or is created:

```bash
ruby <proof-runner>
```

Also verify the target repo:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lang
git diff --check
```

## Deliverables

- Updated `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json`.
- Optional proof runner/doc if required by local inventory precedent.
- This card closed with a concise report and exact digest value.

## Notes For Agent

Be careful with repository boundaries:

- The card lives in `igniter-lab`.
- The inventory authority lives in `igniter-lang`.

If both repos are touched, report both `git status --short` outputs and keep commits logically separated
unless the curator explicitly asks for a cross-repo commit bundle.
