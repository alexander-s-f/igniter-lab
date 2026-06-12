# Agent Card: LANG-EMITTER-ENCODING-P1

**Lane:** lang / emitter / encoding  
**Mode:** READINESS PROOF  
**Status:** CLOSED — PROVED 30/30 PASS  
**Date closed:** 2026-06-12  
**Proof runner:** `igniter-lang/experiments/emitter_encoding_proof/verify_emitter_encoding_p1.rb`

---

## Goal

Readiness proof for the Ruby emitter JSON UTF-8 crash.  Reproduce the crash, isolate the failing layer, compare Rust behavior, decide the fix, and classify the bug.

---

## Crash Summary

**Symptom:** `JSON::GeneratorError: "\xE2" on US-ASCII`  
**Trigger:** Multi-file Ruby compilation of any `.ig` file containing UTF-8 non-ASCII bytes (box-drawing chars `─` U+2500 in comments).  
**Environment:** Any Ruby process with non-UTF-8 external encoding — typical CI with `LANG=C` / `LC_ALL=C`.  
**Known affected apps:** DSA (`types.ig`, `sets.ig`), arch_patterns, dataframes, decision_tree, view-engine fixtures (≥15 files).

---

## Crash Path (Confirmed)

```
multifile_resolver.rb:96
  source = path.read           ← no encoding spec → US-ASCII in CI
    ↓ source string tagged US-ASCII with 0xe2 bytes
multifile_resolver.rb:317
  "sha256:#{Digest::SHA256.hexdigest(canonical_json(material))}"
    ↓ canonical_json calls JSON.generate on hash containing raw source
  JSON::GeneratorError: "\xE2" on US-ASCII
```

**Caught by:** `compile_sources` rescue block → returns `{"status" => "error"}` (does not propagate as exception to caller).

---

## Layer Isolation

| Step | Crash? | Evidence |
|------|--------|----------|
| `Lexer.tokenize` | No | C-01: tokenizes US-ASCII source with 0xe2 bytes safely |
| `ParsedProgram.to_h` | No | C-02: to_h contains only `source_hash` (64-char hex, all ASCII); raw source excluded |
| `Digest::SHA256.hexdigest` | No | B-04: SHA256 is byte-safe, returns 64-char hex on ASCII-8BIT input |
| `JSON.generate(canonical_json(material))` | **Yes** | B-02, D-01: US-ASCII string with 0xe2 raises `JSON::GeneratorError` |

**Single-file path (`compile`):** Safe — `File.read(source_path)` result is parsed but raw source is NOT JSON-serialized; `ParsedProgram.to_h` strips it to `source_hash` only.  
**Multi-file path (`compile_sources`):** Crashes — `source = path.read` result is stored as `unit["source"]`, passed into `composite_source_hash → canonical_json → JSON.generate`.

---

## JSON Gem Version Note

| json version | ASCII-8BIT behavior | US-ASCII behavior |
|---|---|---|
| 2.x (current: 2.19.9) | warns (deprecation) | **raises** `JSON::GeneratorError` |
| 3.x (upcoming) | **raises** | **raises** |

The production crash uses US-ASCII encoding (standard CI locale).

---

## Rust Comparison

`fs::read_to_string` always returns a Rust `String` (guaranteed valid UTF-8).  No encoding option or workaround needed.  If the file contains invalid UTF-8, `read_to_string` returns `Err(...)`.  Ruby's `File.read` / `Pathname#read` defaults to the Ruby process external encoding — locale-dependent behavior.

---

## Fix Decision

**Chosen fix: force UTF-8 read at all source-file read sites.**

| Site | Current | Fixed |
|------|---------|-------|
| `compiler_orchestrator.rb:56` | `File.read(source_path)` | `File.read(source_path, encoding: "utf-8")` |
| `multifile_resolver.rb:96` | `source = path.read` | `source = path.read(encoding: "utf-8")` |

**Additional sites** (CLI + experimental runners, also need fix in P2):
- `cli.rb:83`
- `experimental_igc_run.rb:136`, `:147`
- `experimental_igc_run_vm_candidate.rb:260`

**Rejected alternatives:**
- Scrub non-ASCII from source before serialization — lossy, affects source_hash reproducibility
- `JSON.generate` encoding option — no such option; JSON encodes to UTF-8 by design
- Source map encoding policy — addresses symptoms downstream, not the read boundary

---

## Classification

**Correctness** (not hygiene).  
A `.ig` source file with only box-drawing characters in comments is syntactically valid, parses clean, and compiles correctly in single-file mode — yet crashes in multi-file mode on CI. A crash on valid input is a correctness bug regardless of the frequency or obscurity of the triggering locale.

---

## Proof Coverage (30/30 PASS)

| Section | Content | Checks |
|---------|---------|--------|
| A (survey) | DSA types.ig has box bytes; two bare read sites confirmed; external encoding documented | 4 |
| B (crash) | US-ASCII string constructible; JSON raises; error message pattern; SHA256 safe; json version | 5 |
| C (isolation) | Lexer safe; to_h no raw source; single-file ok; source_hash hex; to_json ok | 5 |
| D (multifile) | canonical_json raises; clean multifile ok; box-drawing file → error status; JSON layer confirmed | 4 |
| E (fix) | force_encoding fix; path.read encoding kwarg; JSON on UTF-8 string ok; file round-trip; end-to-end sim | 5 |
| F (Rust) | main.rs uses read_to_string; multifile.rs uses read_to_string; no encoding workarounds | 3 |
| G (classify) | correctness classification; locale-dependent; 6 total sites; no parser/TC/emitter change | 4 |

---

## Closed Surfaces

- No language syntax changes
- No Unicode normalization semantics
- No app source rewrite (.ig files remain unchanged)
- No Rust changes (immune by design)

---

## Next Route

**LANG-EMITTER-ENCODING-P2** — Implementation:
- Fix 6 bare read sites in `lib/igniter_lang/` with `encoding: "utf-8"`
- Add regression proof: multifile compile of DSA `types.ig` + `sets.ig` returns `ok` (not `error`)
- Verify `stdlib-surface-digest` is unaffected (source_hash is SHA256 of file bytes, encoding-tag-independent)
- Upgrade `lowering_status` / notes if applicable
