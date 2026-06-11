# Lab Governance Doc: Packaging & Library Reuse — Proposal Readiness

**Track:** lab-packaging-and-library-reuse-proposal-readiness-v0 (out-of-track research)
**Card:** LAB-LANGFORM-RESEARCH-P1 (doc 2 of 3)
**Category:** governance / lang
**Date:** 2026-06-10
**Route:** PROPOSAL READINESS / RESEARCH / LAB-ONLY / NO CANON PROP AUTHORED
**Status:** CLOSED — gap mapped; keystone identified; phased route recommended; nothing authored

---

## Scope note

Proposal-readiness research (not a canon PROP). Doc 2 of 3 (stdlib / packaging / application-form).
This is the **keystone** of the triad: its first item unblocks the other two.

---

## 1. Headline — `import` parses but is **semantically inert**; reuse is copy-paste

The lexer has `module`/`import` keywords; the parser builds a full `Import { module_path, names,
hiding, overriding }` struct (parser.rs:136-143). And then **nothing happens**: grep finds **zero**
references to imports in `classifier.rs` or `typechecker.rs`. Imports are stored and never resolved.

**Smoking gun:** `availability_projection.ig` does
`import SparkCRM.Types.{ GeoSignal, TimeSlot, ScheduleFact, AvailabilitySnapshot }` — and
`SparkCRM.Types` **is never defined anywhere in the codebase**, yet compilation produces **no
error**. Import is a no-op. There is no cross-file symbol resolution at all.

The direct consequence is **reuse-by-copy-paste**, visible across the corpus:

- `QueryResult` is re-declared **8+ times** across the query-execution fixtures, with comments
  literally admitting it: *"Re-declared locally from LAB-QUERY-P3 for lab independence."*
- LAB-PURSUIT-P1, LAB-EPISTEMIC-OUTCOME, FRONTIER-DECISION each re-define their own `*Receipt` /
  envelope record types inline; nothing is shared even when the *shapes* are near-identical.

Every fixture is a self-contained island. The language has a `module` *name* but no module
*system*.

---

## 2. What exists vs what is absent

| Concern | State | Evidence |
|---------|-------|----------|
| `module` decl | ✅ parsed; **namespacing only** (a dotted string; no semantics, no fs mapping) | parser; emitter.rs `"module":"…"` |
| `import` decl | ⚠️ **parsed, NOT resolved** — inert; selective/hiding/overriding syntax all parse, none act | zero classifier/TC refs; undefined import → no error |
| `.igapp` | ✅ per-source-file artifact; **one program, multiple contracts**; content-addressed (`source_hash`, `artifact_hash`) | assembler.rs; manifest `contract_index` |
| cross-`.igapp` linking | ❌ absent — `.igapp` cannot reference another | assembler scope |
| trait / contract_shape / impl / type_params | ⚠️ **parsed only** — "no trait coherence, typechecking, or SemanticIR claim" | polymorphic_add.ig:3 |
| monomorphizer | ✅ exists (Rust) for explicit type-args | main.rs:91 |
| package / library / dependency / registry | ❌ **absent** — zero grammar, zero manifest field | grep |
| visibility (public/private/internal/export) | ❌ **absent** | grep; `affects external/internal` is effect-target, not visibility |
| versioning / semver | ❌ absent — only sha256 hashes | manifest |

---

## 3. The decomposition — three concerns wrongly fused under "packaging"

"Packaging" is really three layers with very different cost and urgency. Conflating them is the
trap; the readiness call is to sequence them.

| Layer | What it is | Cost | Urgency |
|-------|-----------|------|---------|
| **(a) Module resolution** | compile-time cross-file symbol lookup: `import M.{T}` actually binds `T` from another file's `module M` | medium | **keystone — unblocks everything** |
| **(b) Visibility / export** | which symbols a module *offers* (public surface) vs keeps internal | medium | high (also a structure concern — doc 3) |
| **(c) Distribution** | named, versioned, fetchable reusable units; a registry; dependency resolution | **large** | low (far future) |

Today the lab has **none** of (a), (b), (c). The minimum that ends copy-paste is **(a) alone** —
and (a) is the same unlock that lets a *numeric stdlib* (doc 1) be importable rather than re-declared
per file, and that gives the *public/internal* boundary (doc 3) something to act on across files.

---

## 4. Design lean — content-addressed reuse (Unison/Nix-style), not semver-first

A genuinely Igniter-idiomatic insight: the language **already content-addresses everything**
(`source_hash`, `program_id`, `artifact_hash`, `contract_ref = contract/Name/sha256:…`). That is
exactly the substrate of **content-addressed code** (cf. Unison, Nix). It fits the Covenant's
determinism/honesty/replay philosophy far better than a mutable semver+registry model:

- A reused unit is identified by the **hash of its semantic content**, not a mutable version string
  → no "dependency hell", no version-range SAT-solving, perfect reproducibility (the
  deterministic-replay property the frontier report flagged extends naturally to dependencies).
- A module's public surface becomes a **content-addressed interface**; a consumer pins the exact
  hash it compiled against → an upgrade is an explicit, auditable swap, never a silent drift
  (an "unnamed dependency" would be exactly the kind of hidden assumption the Covenant forbids).
- Human-facing names (a registry, semver) can be a *thin naming layer over hashes*, added last and
  optionally — not the foundation.

**Recommendation: build reuse on content-addressed module interfaces; treat names/versions/registry
as a deferred convenience layer over the hashes.** This is a distinctive, philosophy-aligned bet,
not a copy of npm/cargo.

---

## 5. `.igapp` evolution

`.igapp` is one-program-one-file today. Two viable directions for multi-module reuse (pick later):

- **Bundle:** `.igapp` carries transitive dependencies inline (self-contained, hermetic — good for
  embed/airgap; larger artifacts).
- **Link-reference:** `.igapp` references other content-addressed units by hash, resolved from a
  store (smaller; needs a resolution step). Content-addressing makes either safe.

Either way the manifest gains a `dependencies` section keyed by `contract_ref`/module hash, and a
`provides` (public interface) section. No decision needed now — flagged for the distribution layer.

---

## 6. Forbidden / closed surfaces

- No registry, no network fetch, no dependency-resolution algorithm in the first route (layer (c)
  is deferred).
- No mutable/semver version semantics adopted as the foundation (content-address first).
- No grammar changes authored here; `import` resolution semantics are *designed*, not implemented.
- No trait-coherence / generics typechecking promised here (separate, large; parser-only today).
- No canon PROP authored; no stable API.

---

## 7. Recommended route

1. **PROP-IMPORT-RESOLUTION (keystone)** — make `import M.{T}` actually resolve `T` from another
   `module M`: a cross-file symbol table, name-collision detection, and *"unknown import is an
   error"* (the OOF-M2 the spec already names but never enforces). Start single-store, content-
   addressed. **This one item ends the copy-paste and unblocks docs 1 & 3.**
2. **PROP-MODULE-VISIBILITY** — `public`/`internal` on contracts/types (shared with doc 3 §
   visibility): a module's `import`-able surface is its declared public set; internal symbols are
   resolution-invisible across modules. (Covenant-aligned: the public API is a declared, auditable
   boundary — an undeclared one is a hidden assumption.)
3. **PROP-CONTENT-ADDRESSED-INTERFACE** — formalize the module interface as a content-addressed
   unit; `.igapp` gains `provides`/`dependencies`.
4. **(deferred) PROP-DISTRIBUTION** — names, versions, registry as a thin layer over hashes.

Dependency on the other docs: **stdlib (doc 1)** becomes the first real client of step 1 (a
shared numeric/Text library you import, not re-declare). **Application-form (doc 3)** shares step 2
(visibility) and is the within-module complement to this cross-module work.

---

## Gap Packet

```
doc:       igniter-packaging-and-library-reuse-proposal-readiness / v0  (2 of 3)
status:    CLOSED — readiness; no canon PROP authored
authority: governance / lang / lab_only
date:      2026-06-10

headline:  import PARSES but is INERT (zero classifier/TC resolution; undefined import → no error)
           → reuse = copy-paste (QueryResult re-declared 8+×, "for lab independence"; every
           Receipt/envelope re-defined inline across pursuit/epistemic/decision fixtures)
state:     module=namespacing-only | import=inert | .igapp=1-program-multi-contract content-addressed |
           trait/shape/impl=parser-only | package/version/visibility/registry/dependency=ABSENT
decompose: (a) module resolution [KEYSTONE] | (b) visibility/export | (c) distribution [deferred-large]
design_lean: CONTENT-ADDRESSED reuse (Unison/Nix-style) over semver-first — fits Igniter's
           hash-everything + determinism/replay/honesty; names/registry = thin deferred layer
route:     PROP-IMPORT-RESOLUTION (keystone, ends copy-paste, unblocks docs 1&3) →
           PROP-MODULE-VISIBILITY → PROP-CONTENT-ADDRESSED-INTERFACE → (deferred) PROP-DISTRIBUTION
closed:    registry/network-fetch/dep-resolution (layer c) | semver-as-foundation | grammar impl |
           trait-coherence | canon PROP authoring
canon_changed: NO   implementation_authorized: NO
```

---

## Authority

lab-only — proposal-readiness research; no canon claim, no stable surface, no PROP authored, no
code/compiler changes. `module`/`import`/`.igapp`/trait surfaces referenced as-is; their inertness
is documented, not changed. Lab behavior not accepted as canon. Informs future gate decisions; does
not make them.
