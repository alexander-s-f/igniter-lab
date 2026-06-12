# Lab: DSA Compilation Baseline

**Track:** LAB-DSA-BASELINE-P1
**Date:** 2026-06-12
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_dsa_baseline_p1.rb`
**Result:** 81/81 PASS

---

## Purpose

Freeze `dsa` as the second canonical Rust multi-file regression baseline. Unlike `vector_math`
(37 contracts, pure numeric geometry), DSA exercises collection construction from array literals,
cross-module import of `stdlib.collection.{ map, filter }`, multi-file type references, and
algorithmic patterns (indexed arrays, sets, graphs, string character lookup). It is the first
baseline that proves array literals compile as `Collection[T]` in Rust and that collection
concat syntax compiles without diagnostic (DSA-P03 note: semantic mislabeling exists but does not
block compilation).

---

## App Structure

| File | Module | Contracts | Types |
|------|--------|-----------|-------|
| `types.ig` | DSATypes | 0 | IndexedElement, ArrayIndexed, IntSet, Edge, Graph, CharString, SearchResult |
| `arrays.ig` | DSAArrays | 3 | — |
| `sets.ig` | DSASets | 2 | — |
| `graphs.ig` | DSAGraphs | 2 | — |
| `strings.ig` | DSAStrings | 1 | — |
| `example.ig` | DSAExample | 4 | — |

**Total:** 6 source units, 12 contracts, 7 named types.

Imports used:
- `arrays.ig`: `import DSATypes`, `import stdlib.collection.{ map, filter }`
- `sets.ig`: `import DSATypes`, `import stdlib.collection.{ filter }`
- `graphs.ig`: `import DSATypes`, `import stdlib.collection.{ filter }`
- `strings.ig`: `import DSATypes`, `import stdlib.collection.{ filter }`
- `example.ig`: `import DSATypes`, `import DSAArrays`, `import DSASets`, `import DSAGraphs`, `import DSAStrings`

---

## Baseline Numbers (frozen 2026-06-12)

Hashes computed with absolute source paths (as used by the proof runner).

| Metric | Value |
|--------|-------|
| status | ok |
| source units | 6 |
| contracts | 12 |
| stages | parse ok / classify ok / typecheck ok / emit ok / assemble ok |
| diagnostics | 0 |
| warnings | 0 |
| source_hash | `sha256:06afdd6e758f3c687af95051f54b69689709cdbc9c75642c66044a16b029e490` |
| artifact_hash | `sha256:7afc3a520876f01e94a0d5b8ff6fc5eba2cad86a43a46170f41fee9104580310` |

Artifact hash verified stable across two independent compilation runs of identical sources.

**Note on hash variants:** Compiling with relative paths (e.g., from `igniter-compiler/`) produces
a different source_hash (`sha256:94b3376fd224ea...`) because source paths are included in the hash
input. The proof runner always uses absolute paths; use it — not manual cargo invocations — to
verify against these constants.

---

## Proof Matrix

| Section | Topic | Checks |
|---------|-------|--------|
| A | Preconditions (compiler binary + 6 source files) | 7 |
| B | Compilation status + diagnostics | 4 |
| C | Pipeline stages (all 5 ok) | 6 |
| D | Source units (count, modules, hashes, paths) | 10 |
| E | Contracts (count, names, SIR, manifest, index) | 8 |
| F | Artifact files (manifest, SIR, sourcemap, report, diag) | 8 |
| G | Hash stability (2 runs) | 9 |
| H | Semantic IR integrity | 6 |
| I | Sourcemap | 3 |
| J | Array literals as Collection[T] (DSA-P02) | 5 |
| K | Collection concat compiles in Rust (DSA-P03 note) | 4 |
| L | Ruby parity gap (documented, not failure) | 4 |
| M | Manifest metadata | 7 |
| **Total** | | **81** |

---

## Array Literals as Collection[T] (DSA-P02)

The app uses array literal syntax in five places:

| Location | Literal | Contract |
|----------|---------|----------|
| `RunArrayExample.c2` | `[e0, e1, e2]` | RunArrayExample |
| `RunSetExample.c1` | `[100, 200]` | RunSetExample |
| `RunGraphExample.c2` | `[edge1, edge2, edge3]` | RunGraphExample |
| `SetInsert.new_elements` (concat arg) | `[new_elem]` | SetInsert |
| `RunStringExample.c1` | `[c_h, c_i]` | RunStringExample |

The Rust SIR emits these as `"kind": "array_literal"` nodes with an `items` list of refs.
All 5 produce zero diagnostics. This is an existence proof that array literals are valid
`Collection[T]` constructors in Rust without requiring `empty`/`append` bootstrapping.

---

## Collection Concat — Semantic Mislabeling (DSA-P03)

`SetInsert` uses `concat(s.elements, [new_elem])`. Rust compiles this with zero diagnostics, but
the SIR emits:

```json
"fn": "stdlib.text.concat",
"resolved_type": { "name": "Text", "params": [] }
```

The typechecker resolved bare `concat` as `stdlib.text.concat`. This is a semantic mislabeling:
the intent is collection concat, but the Rust typechecker dispatches to the text concatenation
function. The output type is `Text` rather than `Collection[Integer]`.

**Impact:** `SetInsert` appears to compile but is semantically incorrect — the output would not
be a valid `Collection[Integer]`. This is documented as DSA-P03 and routes to
`LANG-STDLIB-COLLECTION-CONCAT-P1` to distinguish collection concat from text concat and add
proper dispatch.

**This does not affect the compilation baseline.** Zero diagnostics in Rust is the frozen fact.
The mislabeling is a pressure note, not a regression signal.

---

## Ruby Parity Gap

The Ruby toolchain fails to compile this app with a JSON encoding error:

```
JSON::GeneratorError: "\xE2" on US-ASCII
```

The cause is the UTF-8 box-drawing characters (`──`, U+2500) in `types.ig` comment decorators.
The Ruby multifile merger passes source text through a JSON serialization path that is configured
for US-ASCII, causing the generator to reject the non-ASCII bytes.

This prevents Ruby from reaching semantic analysis for this app. Separately, the `dsa/report.md`
documents 25 semantic diagnostics that would surface once encoding is resolved:

| Diagnostic | Count | Route |
|-----------|-------|-------|
| `Unknown function: call_contract` | 9 | LAB-RUBY-CALL-CONTRACT-PARITY-P1 |
| `Unsupported operator: ==` | 6 | LANG-STDLIB-TEXT-EQUALITY-P1 (Integer path) |
| Other (cascade) | 10 | — |

Neither the encoding error nor the semantic parity gaps affect the Rust baseline. They are
documented here as pressure, not as baseline failure.

---

## Closed Surfaces

- No DSA stdlib promotion (IndexedElement, IntSet, Graph, etc. remain app-local types)
- No indexed access implementation (`col[i]` syntax gap remains; DSA-P07 watch)
- No Ruby parity implementation (encoding gap and semantic gaps documented above)
- No source edits to the app (all 6 source files read-only for this proof)
- No new stdlib inventory entries
- No new OOF codes

---

## App Pressure Map (frozen with baseline)

| ID | Status | Pressure | Route |
|----|--------|---------|-------|
| DSA-P01 | BASELINE | Full Rust multi-file compilation | this card |
| DSA-P02 | POSITIVE | Array literals as Collection[T] | collection baseline |
| DSA-P03 | ACTIVE | concat resolves as stdlib.text.concat — semantic mislabeling | LANG-STDLIB-COLLECTION-CONCAT-P1 |
| DSA-P04 | ACTIVE | Ruby: == for Integer/Bool | LANG-STDLIB-TEXT-EQUALITY-P1 (P3 scope) |
| DSA-P05 | ACTIVE | is_empty / non_empty for set semantics | LANG-STDLIB-IS-EMPTY-PROP-P2/P3 |
| DSA-P06 | ACTIVE | find_one / head for scalar extraction | LAB-STDLIB-FIND-ONE-P1 |
| DSA-P07 | WATCH | Indexed access as O(n) scan | indexed access backlog |
| DSA-P08 | ACTIVE | Ruby: Unknown function: call_contract × 9 | LAB-RUBY-CALL-CONTRACT-PARITY-P1 |

---

## Next Route

This baseline is a freeze, not an implementation milestone. Any future regression runner for
multi-file compilation, stdlib.collection imports, or array literal handling should verify
against these constants. If the app is extended, re-freeze under a new P-number.

Active routes from this baseline:
- `LANG-STDLIB-COLLECTION-CONCAT-P1` — collection vs text concat disambiguation (DSA-P03)
- `LANG-STDLIB-TEXT-EQUALITY-P1` — Integer/Bool == parity (DSA-P04)
- `LANG-STDLIB-IS-EMPTY-PROP-P2/P3` — emptiness guard for Set semantics (DSA-P05)
- `LAB-STDLIB-FIND-ONE-P1` — scalar extraction from filtered collection (DSA-P06)
- `LAB-RUBY-CALL-CONTRACT-PARITY-P1` — Ruby invocation parity (DSA-P08)
