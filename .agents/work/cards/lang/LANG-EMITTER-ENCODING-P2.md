# Agent Card: LANG-EMITTER-ENCODING-P2

**Lane:** lang / emitter / encoding  
**Mode:** IMPLEMENTATION  
**Status:** CLOSED — PROVED 18/18 PASS  
**Date closed:** 2026-06-12  
**Proof runner:** `igniter-lang/experiments/emitter_encoding_proof/verify_emitter_encoding_p2.rb`

---

## Goal

Apply the UTF-8 read fix to all 6 bare read sites identified in P1, then prove the
DSA `types.ig` + `sets.ig` multifile crash is resolved with no collateral changes.

---

## Fix Applied (6 sites)

| File | Line | Before | After |
|------|------|--------|-------|
| `compiler_orchestrator.rb` | 56 | `File.read(source_path)` | `File.read(source_path, encoding: "utf-8")` |
| `multifile_resolver.rb` | 96 | `source = path.read` | `source = path.read(encoding: "utf-8")` |
| `cli.rb` | 83 | `JSON.parse(path.read)` | `JSON.parse(path.read(encoding: "utf-8"))` |
| `experimental_igc_run.rb` | 136 | `JSON.parse(path.read)` | `JSON.parse(path.read(encoding: "utf-8"))` |
| `experimental_igc_run.rb` | 147 | `JSON.parse(path.read)` | `JSON.parse(path.read(encoding: "utf-8"))` |
| `experimental_igc_run_vm_candidate.rb` | 260 | `JSON.parse(path.read)` | `JSON.parse(path.read(encoding: "utf-8"))` |

Note: `multifile_resolver.rb:208` already had `encoding: "utf-8"` and was not modified.

---

## Proof Coverage (18/18 PASS)

| Section | Content | Checks |
|---------|---------|--------|
| A (static audit) | Each of 6 sites has `encoding: "utf-8"` kwarg | 6 |
| B (DSA regression) | types.ig has box-drawing bytes; multifile compile → `ok` under `LANG=C` | 2 |
| C (hash stability) | ASCII fixture hash is byte-identical after fix; SHA256 is encoding-tag-independent | 3 |
| D (Unicode acceptance) | Box-drawing multifile ok; no normalization applied on read | 3 |
| E (single-file safe) | Clean + box-drawing single-file compile still ok | 2 |
| F (Rust unaffected) | `read_to_string` confirmed in main.rs + multifile.rs; no Ruby-side patch | 2 |

---

## Closed Surfaces

- No Unicode normalization
- No parser syntax change
- No source rewriting (.ig files unchanged)
- No app source edits
- Rust compiler: immune by design, no changes

---

## Acceptance Criteria (all met)

- [x] Replace bare reads with `read(encoding: "utf-8")` at all 6 DSA types.ig + sets.ig sites
- [x] DSA types.ig + sets.ig multi-file no longer crashes (returns `ok`)
- [x] source_hash stable for ASCII fixtures
- [x] Unicode source accepted without normalization changes
- [x] Single-file path unchanged
- [x] Rust unaffected
