# LANG-CONTRACT-NAMESPACE-P1: Module-Qualified Contract Namespace Boundary

**Track:** module-qualified-contract-identity-and-duplicate-declaration-boundary-v0
**Route:** RESEARCH / DESIGN BOUNDARY / BLOCKER ANALYSIS / NO IMPLEMENTATION
**Date:** 2026-06-11
**Status:** CLOSED — READY FOR P2

---

## 1. Problem Statement

The Igniter language currently treats contract names as a **globally unique namespace** across
the entire compilation universe. Any two source units that both declare a contract named
`ValidateInput` fail compilation with `OOF-DECL-DUP-CONTRACT` — regardless of whether those
units belong to different modules.

This is package-hostile. Two packages that both define common names like `ValidateInput`,
`Mapper`, or `BuildRequest` cannot coexist in the same logical compilation universe:

```
Package A declares:
  module Users
    contract ValidateInput { ... }      # Users.ValidateInput

Package B declares:
  module Orders
    contract ValidateInput { ... }      # Orders.ValidateInput

Compile both together → OOF-DECL-DUP-CONTRACT: "duplicate contract declaration 'ValidateInput'"
```

The modules are fully distinct (`Users` ≠ `Orders`). Their `ValidateInput` contracts have
different signatures, different bodies, different `contract_ref` hashes. There is no actual
naming conflict — only a conflict in the flat duplicate check.

The same problem applies to type names (`OOF-DECL-DUP-TYPE`): two modules cannot define a
type named `Address` or `Item` in the same compilation universe.

This card identifies the exact code surfaces where the global uniqueness assumption lives,
evaluates alternative identity models, and recommends a concrete design that unblocks
packages and typed reference resolution.

---

## 2. Current Behavior Inventory

### 2.1 Duplicate Declaration Check — MultifileResolver

`lib/igniter_lang/multifile_resolver.rb` lines 32–36:

```ruby
duplicate_contract = duplicate_declaration(sorted, "contract_names")
return failure(sorted, [declaration_diagnostic("OOF-DECL-DUP-CONTRACT", "contract", duplicate_contract)]) if duplicate_contract

duplicate_type = duplicate_declaration(sorted, "type_names")
return failure(sorted, [declaration_diagnostic("OOF-DECL-DUP-TYPE", "type", duplicate_type)]) if duplicate_type
```

`duplicate_declaration` (lines 261–267) scans ALL source units in the flattened sorted array
and groups by short name:

```ruby
def duplicate_declaration(units, key)
  owners = Hash.new { |hash, name| hash[name] = [] }
  units.each do |unit|
    unit.fetch(key).each { |name| owners[name] << unit }
  end
  owners.sort.find { |_name, refs| refs.length > 1 }
end
```

This method is **module-unaware**: it matches by bare name, not by `(module, name)` pair.
Two units from different modules with the same contract name trigger the same error as two
units in the same module with the same name.

The `declaration_diagnostic` helper (lines 305–314) does surface `module_paths` in the
emitted diagnostic — but the triggering predicate (`refs.length > 1`) does not consult
module identity.

### 2.2 Module Duplicate Check (Correct — No Change Needed)

`OOF-IMP4` fires when two units share the same `module` declaration string (lines 22–23):

```ruby
duplicate_module = duplicate_by(sorted, "module")
return failure(sorted, [duplicate_module_diagnostic(duplicate_module)]) if duplicate_module
```

This check **is correct and must remain unchanged**: two source files in the same compilation
universe may not declare the same module name. Only duplicate CONTRACT/TYPE names across
DIFFERENT modules should be relaxed.

### 2.3 `contract_index` Keys — Assembler

`lib/igniter_lang/assembler.rb` lines 416–425:

```ruby
def contract_index_for(contracts)
  contracts.sort_by { |contract| contract.fetch("contract_id") }.to_h do |contract|
    entry = {
      "contract_ref"   => contract.fetch("source_contract_ref"),
      "contract_path"  => "contracts/#{snake_case(contract.fetch("contract_id"))}.json",
      "fragment_class" => contract.fetch("fragment_class")
    }
    [contract.fetch("contract_id"), entry]
  end
end
```

**Keys are short contract names** (`"ValidateInput"`, `"Mapper"`, etc.). If two contracts
from different modules share a short name, the `contract_index` would silently overwrite —
the last-sorted entry wins. This is an implicit assumption that short names are globally
unique.

The `contract_refs` field at line 246 also uses `contract_name` (short) as the key:

```ruby
"contract_refs" => semantic_ir.fetch("contracts").to_h do |contract|
  [contract.fetch("contract_name"), contract.fetch("contract_ref")]
end
```

### 2.4 `contract_ref` Hash — SemanticIR Emitter

`lib/igniter_lang/semanticir_emitter.rb` lines 862–864:

```ruby
def contract_ref(contract_ir)
  body = contract_ir.reject { |key, _value| key == "contract_ref" || key == "diagnostics" }
  "contract/#{contract_ir.fetch("contract_name")}/sha256:#{Digest::SHA256.hexdigest(canonical_json(body))[0, 24]}"
end
```

The path label uses the **short contract name**: `"contract/ValidateInput/sha256:abc123"`.
Two contracts with the same short name but different module origins would produce different
hash suffixes (because their bodies differ), but the same path prefix. In the filesystem
assembler, this would cause a file path collision: both write to
`contracts/validate_input.json`.

### 2.5 Entrypoint Resolution — TypeChecker

`lib/igniter_lang/typechecker.rb` lines 188–217 (`validate_entrypoint`):

```ruby
target_contract = contracts.find do |contract|
  target == contract.fetch("name") || target == contract.fetch("contract_id")
end
```

Entrypoint resolves by **short name** (`"ValidateInput"`) or short `contract_id`. In a
multifile compilation where two modules both declare `ValidateInput`, this `find` returns the
first match — not a deterministic module-qualified resolution. No disambiguation error fires.

PROP-ENTRYPOINT-P4 (Rust lab) demonstrated that `entrypoint Mod.ValidateInput` qualified
targets can be parsed and resolved by module-qualified `contract_id` — the infrastructure
exists but is not enforced in the Ruby canon typechecker.

### 2.6 Typed Reference Resolution — TypeChecker

`typecheck_uses_contract` (lines 512–650):
- **PATH 0** (self-reference): uses short name
- **PATH 1** (dotted): `"Lab.TypedRef.Query.Validator"` → splits on last dot; resolves via
  `@cross_module_registry[mod_path][contract_name]` — already module-qualified
- **PATH 2a** (unqualified local): `@same_module_registry[target]` (short name lookup)
  then `@per_contract_module` check for disambiguation
- **PATH 2b** (unqualified import scan): scans `@cross_module_registry` by short name
  across imports; fires OOF-REF2 if ≥2 modules export the same short name

**The P5 typed-ref resolution infrastructure already treats `(module, contract_name)` as the
canonical identity.** `per_contract_module` maps short name → originating module; the PATH 1
resolution is fully module-qualified. The gap is only in the pre-typecheck declaration check.

### 2.7 Import Resolution — MultifileResolver

`validate_imports` (lines 129–162) checks OOF-IMP3 for unknown import names:

```ruby
exported = target.fetch("type_names") + target.fetch("contract_names")
names.reject { |name| exported.include?(name) }.map { ... }
```

Imports use **short names** — `import Lab.Query.{Validator}` imports `"Validator"`, not
`"Lab.Query.Validator"`. This is correct: inside the importing module, the local alias IS
the short name. No conflict here as long as import resolution stays selective.

### 2.8 Inventory Summary

| Surface | Current key | Module-aware? | Package-hostile? |
|---------|-------------|---------------|-----------------|
| `duplicate_declaration` check | short name | NO | YES — must change |
| `contract_index` keys | short name | NO | YES — must change |
| `contract_refs` manifest field | short name | NO | YES — must change |
| `contract_ref` path label | `contract/short/sha256:` | NO | YES — causes file collision |
| Entrypoint resolution | short name | NO | YES (ambiguity) |
| Typed ref PATH 1 | `Mod.Contract` split | YES | — |
| Typed ref PATH 2a/2b | short name | NO (via `per_contract_module`) | OK in P5 |
| `same_module_registry` build | short name (in-module only) | implicit | OK |
| `per_contract_module` | short name → module | YES | OK |
| `cross_module_registry` | `module → { short_name → sig }` | YES | OK |
| Import OOF-IMP3 | short name | scoped to target module | OK |
| Module dup OOF-IMP4 | module path | YES | OK — unchanged |

---

## 3. Identity Candidates

### A. Global Contract Name: `"ValidateInput"`

Current behavior. Identity = short name only.

- Import resolution: works for single module
- Typed refs: breaks at module boundary (P5 workaround: `per_contract_module`)
- Entrypoint: breaks in multifile with same-name contracts
- Manifest contract_index: implicit overwrite collision
- Package identity: BLOCKS all same-name contracts across packages
- Backwards compatibility: zero change from current, but package-hostile

### B. Module-Qualified: `"Users.ValidateInput"`

Identity = `module_name + "." + contract_name`. Natural extension of dotted-name syntax
already used in PATH 1 typed refs.

- Import resolution: source syntax stays short; internal index uses qualified
- Typed refs: PATH 1 already uses this; PATH 2a/2b already have `per_contract_module`
- Entrypoint: `entrypoint Users.ValidateInput` for disambiguation; `entrypoint ValidateInput`
  remains valid when unambiguous
- Manifest contract_index: qualified key `"Users.ValidateInput"`
- Package identity: two packages with same contract short names coexist cleanly
- Backwards compatibility: single-file transparent (only one module in universe → qualified =
  `module.short = short`); multifile manifest format change to contract_index keys

### C. Package + Module + Contract: `"pkg_digest:Users.ValidateInput"`

Full three-level identity. Appropriate for runtime cross-package linking.

- Source syntax: too heavy for source-level syntax
- Diagnostic messages: difficult to read
- Appropriate for: lockfile graph edges, runtime loader, package P2 manifest
- Backwards compatibility: large breaking change

### D. Hybrid: Source-local short name + canonical qualified identity

Source syntax uses short names within a module (unchanged). Internal compiler identity uses
module-qualified names. External (manifest, dependency_edges, cross-package) uses qualified
or digest-pinned form.

This is the natural extension of the P5 model: `per_contract_module` already provides the
binding. Typed ref resolution already uses module-qualified identity internally. The gap is
surfacing it through the manifest and removing the global uniqueness constraint.

### E. Artifact-Ref Identity Only: `"contract/abc123/sha256:def456"`

Opaque content-addressed identity only. No human-readable name in keys.

- Error messages: unreadable
- Tooling: difficult to navigate
- Not viable as primary key

---

## 4. Recommended Identity Model

**Recommendation: Option D hybrid, staged.**

| Layer | Identity form | Where used |
|-------|---------------|------------|
| Source syntax | Short local name `ValidateInput` | `.ig` files, `uses`, `entrypoint` |
| Compiler internal | `(module_name, contract_name)` pair | Resolver, TypeChecker state |
| SIR / manifest | Module-qualified `module_name.contract_name` | `contract_index`, `contract_ref` path |
| Package / cross-package | Module-qualified + `package_digest` prefix | Package P2 manifest, lockfile |

**Governing rule:** A contract's canonical identity is the pair `(module_name, contract_name)`.
Source syntax is always local-short. Any surface that must disambiguate multiple modules uses
the qualified form. The duplicate check applies at the `(module, name)` scope.

**Key insight from P5:** The resolution infrastructure already implements this model
implicitly. `per_contract_module` maps `contract_name → module_name`; `cross_module_registry`
is keyed `module_name → { contract_name → sig }`. The gap is only in:
1. The declaration-level duplicate check (still flat)
2. The manifest output surfaces (contract_index, contract_refs, contract_ref path label)
3. Entrypoint disambiguation in multifile with same-name contracts

---

## 5. Duplicate Rule Proposal

| Situation | Rule | OOF Code | Change? |
|-----------|------|-----------|---------|
| Same contract name, same module | ERROR | OOF-DECL-DUP-CONTRACT | No change |
| Same contract name, different modules | ALLOWED | — (no error) | **CHANGE: remove block** |
| Same type name, same module | ERROR | OOF-DECL-DUP-TYPE | No change |
| Same type name, different modules | ALLOWED | — (no error) | **CHANGE: remove block** |
| Same module name, same compilation unit | ERROR | OOF-IMP4 | No change — unchanged |
| Duplicate entrypoint, same unit | ERROR | OOF-EP1 | No change |
| Same contract name, same entrypoint module, multifile | Resolve if unambiguous | — | Entrypoint logic update |

**Implementation shape for `duplicate_declaration`:** change from flat name scan to
`(module, name)` pair scan:

```ruby
# Current (package-hostile):
units.each { |unit| unit.fetch(key).each { |name| owners[name] << unit } }

# Required (module-scoped):
units.each { |unit|
  mod = unit.fetch("module")
  unit.fetch(key).each { |name| owners[[mod, name]] << unit }
}
# Find: owners.find { |_key, refs| refs.length > 1 }
```

The diagnostic message should report both the name and the originating module.

---

## 6. Diagnostic Mapping

| Code | Current behavior | Behavior under module-scoped check |
|------|------------------|------------------------------------|
| OOF-DECL-DUP-CONTRACT | Fires on same short name across ANY two units | Fires only when same short name in SAME module across two files (impossible in practice — one module per file is the rule, so this becomes unreachable in normal use) |
| OOF-DECL-DUP-TYPE | Same as above | Same narrowing |
| OOF-IMP4 | Fires on duplicate module name | UNCHANGED |
| OOF-EP2 | Unknown entrypoint target | Extended: also fires when short-name entrypoint is ambiguous across modules; message includes available qualified forms |
| OOF-REF2 | Ambiguous unqualified typed ref | UNCHANGED (already fires for ≥2 imported modules exporting same name) |

Diagnostic messages for OOF-DECL-DUP-CONTRACT and OOF-DECL-DUP-TYPE should include
`module_path` alongside `source_path` so users know which module declared the conflicting
name. The current diagnostic already surfaces `module_paths` — the trigger logic changes, the
shape is already adequate.

---

## 7. Contract Index / Manifest

### Current shape (assembler `contract_index_for`):

```json
{
  "contract_index": {
    "ValidateInput": {
      "contract_ref": "contract/ValidateInput/sha256:abc123",
      "contract_path": "contracts/validate_input.json",
      "fragment_class": "core"
    }
  }
}
```

### Required shape (module-qualified keys):

```json
{
  "contract_index": {
    "Users.ValidateInput": {
      "contract_ref": "contract/Users.ValidateInput/sha256:abc123",
      "contract_path": "contracts/users.validate_input.json",
      "fragment_class": "core",
      "module": "Users"
    },
    "Orders.ValidateInput": {
      "contract_ref": "contract/Orders.ValidateInput/sha256:def456",
      "contract_path": "contracts/orders.validate_input.json",
      "fragment_class": "core",
      "module": "Orders"
    }
  }
}
```

Changes:
- Key: `module_name.contract_name` (fully qualified)
- `contract_ref` path label: `"contract/module_name.contract_name/sha256:..."` — eliminates file path collision
- `contract_path`: `snake_case("module_name.contract_name")` — disambiguated filesystem path
- Optional `"module"` field: redundant (derivable from key split on last dot) but useful for tooling

The `contract_refs` manifest field (currently `{ short_name → contract_ref }`) should also
adopt qualified keys:

```json
"contract_refs": {
  "Users.ValidateInput": "contract/Users.ValidateInput/sha256:abc123",
  "Orders.ValidateInput": "contract/Orders.ValidateInput/sha256:def456"
}
```

**Single-file compatibility:** in a single-file compilation, `module_name` is always the
declared module name (e.g., `"Lab.MyApp"`), so the qualified key becomes
`"Lab.MyApp.Validator"`. Existing single-file tooling reading `contract_index` by short name
must be updated to use qualified keys. This is a manifest breaking change but transparent at
the source level.

---

## 8. ContractRef / TypedRef Impact

### `uses ContractName` (unqualified local):
- PATH 2a: unchanged — if `per_contract_module[target] == per_contract_module[current]`, it
  is local; resolution_kind = "local"
- PATH 2a: `module_name` in `resolved_ref` is already set from `per_contract_module`
- `dependency_edges`: `to_module` already present — no change to edge shape

### `uses Mod.Contract` (qualified):
- PATH 1: unchanged — already fully module-qualified

### Ambiguity (OOF-REF2):
- Unchanged — already fires for ≥2 imported modules exporting same short name
- Error message already names the conflicting modules

### Manifest `dependency_edges`:
- Currently: `{ "from": "X", "to": "ValidateInput", "from_module": "App", "to_module": "Users", "resolution_kind": "qualified" }`
- No change needed — `to_module` is already present; callers can reconstruct qualified identity as `to_module.to`

### Cross-package typed refs:
- `dependency_edges` are the live evidence for cross-package references
- With module-qualified contract_index, a consumer can resolve `to_module.to` directly against the imported package's manifest

---

## 9. EntryPoint Impact

### Single module, short-name entrypoint:
No change. Only one module in universe; `ValidateInput` is unambiguous.

### Multifile, short-name entrypoint, unique across modules:
`validate_entrypoint` finds exactly one match by short name → resolve normally.

### Multifile, short-name entrypoint, SAME short name in two modules:
With module-scoped duplicate check removed, two modules CAN both define `ValidateInput`.
The entrypoint `entrypoint ValidateInput` is now ambiguous. Current behavior: returns the
first match silently (non-deterministic).

**Required behavior:** OOF-EP2 with disambiguation message:
> "entrypoint target 'ValidateInput' is ambiguous: found in modules Users, Orders;
>  qualify the target, e.g. entrypoint Users.ValidateInput"

**Implementation:** `validate_entrypoint` should count matches; if >1, emit OOF-EP2 with
`available_qualified_forms` list.

### Qualified entrypoint `entrypoint Users.ValidateInput`:
The parser already accepts dotted targets (PROP-ENTRYPOINT-P4 Rust proof). Ruby canon
`validate_entrypoint` compares target against `contract.fetch("name")` OR
`contract.fetch("contract_id")`. If module-qualified names become the canonical
`contract_id`, this resolution path works for free. If not, the resolver must split the
target on the last dot and match `(module_part, name_part)` against contracts.

### Manifest entrypoint:
`manifest_entrypoint_for` writes `"resolved_contract"` (short name currently). Should become
module-qualified. `"declared_target"` stays as-authored.

---

## 10. Package Impact

### Why this unblocks packages:

1. **Two packages with same-named contracts can coexist** in a compilation universe once the
   flat duplicate check is module-scoped. `pkg_a::Users.ValidateInput` and
   `pkg_b::Orders.ValidateInput` (same short name) are now distinct identities.

2. **Manifest exports list** becomes unambiguous. A package exports module-qualified names:
   `"exports": ["Users"]` identifies the module; consumers resolve contracts as
   `"Users.ValidateInput"` etc.

3. **Digest-pinned package manifests** reference contracts by module-qualified names in
   `contract_index` — no collision possible even if two packages both export a contract
   called `"Validator"`.

4. **Package identity** (`package_digest`) is computed over source units (unchanged formula
   from IMPORT-P5). Module-qualified contract identity lives in the manifest, not the hash
   formula — no change to the hash mechanism.

5. **Lockfile graph edges** reference packages by `package_digest`; contracts within each
   package are identified by module-qualified names. The `dependency_edges` shape
   (`from_module`, `to_module`, `resolution_kind`) already carries the module context needed
   to reconstruct cross-package edges.

6. **LANG-CONTRACT-NAMESPACE-P1 → LAB-PACKAGE-MODEL-P2 path:**
   Once the namespace check is module-scoped, two real packages (`pkg_core` and `pkg_app`)
   can be compiled together in the P2 proof. Cross-package `dependency_edges` can be asserted
   with correct `to_module` attribution. Package manifests can carry module-qualified
   `contract_index` without collision.

---

## 11. Migration / Compatibility

**Classification:** pre-v1 breaking correction, not a feature addition.

| Consumer | Impact |
|----------|--------|
| Single-file `.ig` programs | Transparent — only one module; qualified = `module.short` |
| Multifile programs (no same-name contracts across modules) | Manifest format change only; `contract_index` keys become module-qualified |
| Multifile programs (same-name contracts, previously blocked) | Now allowed — additive, not breaking |
| Tooling reading `contract_index` by short name | Must update to qualified keys |
| Assembler `contracts/validate_input.json` path | Becomes `contracts/users.validate_input.json` etc. |
| `contract_ref` hashes | Will change (path label changes → different hash); not a semantic regression |

**Migration approach:** single integrated change — no feature flag, no shim. The multifile
resolver and assembler changes are co-deployed. Test suite validates both old single-file
shape (short name = qualified name) and new multifile shape (qualified key required).

**Semver note:** since Igniter is pre-v1, this is routine. A note in the proof packet is
sufficient.

---

## 12. Proof Requirements For P2

P2 will be a bounded Ruby-canon implementation proof in `LAB-PACKAGE-MODEL-P2`. The
namespace fix is a prerequisite that P2 exercises. Required proof checks:

| Check | Focus |
|-------|-------|
| Same short name, different modules: compilation succeeds | OOF-DECL-DUP-CONTRACT NOT emitted |
| Same short name, same module: compilation fails | OOF-DECL-DUP-CONTRACT still emitted |
| Same type name, different modules: compilation succeeds | OOF-DECL-DUP-TYPE NOT emitted |
| `contract_index` keys are module-qualified | `module_name.contract_name` key format |
| `contract_ref` path uses qualified name | `"contract/Users.ValidateInput/sha256:..."` |
| No file path collision in `.igapp` output | Two same-short-named contracts write distinct files |
| `entrypoint ValidateInput` unambiguous (one module) | Resolves correctly |
| `entrypoint ValidateInput` ambiguous (two modules) | OOF-EP2 with qualified forms in message |
| `entrypoint Users.ValidateInput` qualified | Resolves to correct contract |
| `uses ValidateInput` (local) resolves correctly | PATH 2a unchanged |
| `uses ValidateInput` (imported, one match) resolves correctly | PATH 2b unchanged |
| `uses Orders.ValidateInput` (qualified cross-module) resolves correctly | PATH 1 unchanged |
| IMPORT-P5 regressions pass | 99/99 baseline |
| TYPED-REF-P5 regressions pass | 71/71 baseline |
| `dependency_edges` carry correct `to_module` | Module attribution correct in manifest |
| `per_contract_module` correct for both modules | Attribution map not conflated |

---

## 13. Recommendation

**CLOSED — READY FOR P2.**

The problem is precisely scoped. The fix is:

1. **In MultifileResolver:** narrow `duplicate_declaration` from flat-name scan to
   `(module, name)` pair scan. Contract/type names are duplicate only within the same module.
   OOF-IMP4 (module-level dup) is unchanged.

2. **In Assembler:** change `contract_index_for` to use `module_name.contract_name` as the
   key. Update `contract_refs` manifest field similarly. Update `snake_case` path generation
   to include module prefix.

3. **In SemanticIR Emitter:** change `contract_ref` path label from
   `"contract/short/sha256:"` to `"contract/module_name.short/sha256:"`. The hash itself
   changes because the body label changes — this is a clean break, not a regression.

4. **In TypeChecker `validate_entrypoint`:** detect ambiguity when `contracts.count { |c| ... } > 1`
   and emit OOF-EP2 with qualified disambiguation hints.

No parser changes. No VM/runtime changes. No capability/profile changes. No public API
widening. No package manager. The change is internally contained within the five canonical
compiler stages (resolver, typechecker, emitter, assembler, orchestrator).

**Why not SPLIT or HOLD:**
- Not a split: the contract and type cases are symmetric; implementing them together is less
  risky than two separate changes.
- Not a hold: the blocker is empirically confirmed (hit directly in P5 fixture work). The
  fix is bounded and reversible. Single-file programs are transparent.

**Immediate next route:**
- LAB-PACKAGE-MODEL-P2: proof-local two-package implementation using the module-scoped
  namespace. The namespace fix is implemented as part of P2 setup. TYPED-REF-P5 and
  IMPORT-P5 regressions serve as the baseline.

---

## Appendix A: Code Shape for Module-Scoped Duplicate Check

```ruby
# multifile_resolver.rb — DESIGN ONLY, no implementation authorized in P1

def duplicate_declaration_module_scoped(units, key)
  owners = Hash.new { |hash, name| hash[name] = [] }
  units.each do |unit|
    mod = unit.fetch("module")
    unit.fetch(key).each { |name| owners[[mod, name]] << unit }
  end
  # Should never find length > 1 if OOF-IMP4 already passed,
  # but guard against edge cases (module loaded from two files).
  owners.sort.find { |_key, refs| refs.length > 1 }
end
```

## Appendix B: Impact on `compatibility_fingerprints` (from a1)

The a1 research introduced `compatibility_fingerprints` keyed by `"Module.Contract"` — the
module-qualified form. This is consistent with the design above. The a2 research abstracted
this as `exports_digest` (API fingerprint over the exports set). Both are compatible:
`compatibility_fingerprints` is a per-contract fine-grained form; `exports_digest` is a
coarser whole-package fingerprint. Both should be keyed by module-qualified names.
