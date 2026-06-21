# lab-igniter-package-import-explain-readiness-p18-v0 — explain why an import is allowed or denied

**Card:** `LAB-IGNITER-PACKAGE-IMPORT-EXPLAIN-READINESS-P18` · **Delegation:** `OPUS-IGNITER-PACKAGE-IMPORT-EXPLAIN-READINESS-P18`
**Status:** READINESS / DESIGN (v0) — picks the smallest shape to make `OOF-IMP6`/`OOF-IMP7` actionable and
specifies the next implementation card. **No production code.** Authority: lab readiness, grounded in live
`project.rs` diagnostics.

---

## 1. Executive summary

Prefer **diagnostic enrichment** over a new command. A *denied* import already produces a structured
diagnostic at `igc compile` / `igc verify --strict`; what it lacks is **machine-actionable sub-fields** (the
provider's path + exports surface, a declared-edge boolean, the active policy, and a concrete **fix**) —
those live only in the prose `message` today. Add a **single generic `details` escape-hatch** to
`ProjectDiagnostic` (P11-safe: one generic field, not N package-specific ones) and populate it for
`OOF-IMP6`/`OOF-IMP7`. This makes denied imports fully actionable for agents and humans without parsing
English. A proactive **`igc package explain-import`** command (for *allowed* / hypothetical queries, Q5) is
**deferred** — the enriched diagnostic covers the 80%; a command is only worth it if live use shows the
denied-path output is still insufficient. Recommended next card: **`LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19`**
(§6).

## 2. Verify-first — current `OOF-IMP6`/`OOF-IMP7` diagnostics

`ProjectDiagnostic` (generic) carries: `rule`, `severity`, `message`, `node`, `module_path`, `source_paths`,
`entry_module?`, `original_path?`, `overlay_path?` (`to_value` emits them conditionally). The package rules
populate:

| Field | OOF-IMP6 | OOF-IMP7 |
|---|---|---|
| `rule` | `OOF-IMP6` | `OOF-IMP7` |
| `message` | "out-of-scope import: module 'App.Main' (package <root>) imports 'Leaf.Public' (package leaf), which it does not declare as a dependency" | "non-exported import: module 'Mid.M' imports 'Leaf.Private' (package leaf), which package 'leaf' does not export" (or "…declares no exports ([package] exports = \"closed\")") |
| `node` | `import:App.Main->Leaf.Public` | `export:Mid.M->Leaf.Private` |
| `module_path` | importer module | importer module |
| `source_paths` | [importer file] | [importer file] |

**Already structured:** rule, importer module, importer→imported edge (`node`), importer source path,
severity. **Only in prose (`message`):** importer **package label**, provider **package label**, the
**reason**, and — *not present at all* — provider **path**, provider **exports surface** (the allowlist),
a **declared-edge** boolean, the active **closed-default policy**, and a **fix**. P11 deliberately did NOT
add package-specific fields to the generic diagnostic — so enrichment must use a **generic** carrier.

**Allowed imports:** there is **no** diagnostic for an import that passes — it simply compiles. So "why is
`X` *allowed*?" cannot be answered by enrichment; only a query command can (Q5).

## 3. UX-shape comparison (≥3)

| Shape | Pros | Cons | Verdict |
|---|---|---|---|
| **A. Diagnostic enrichment via generic `details`** | zero new surface; auto-flows through compile + `verify --strict` (P11 `to_value`); makes *denied* imports actionable; P11-safe (one generic field) | does not explain *allowed*/hypothetical imports | **SELECTED (v0)** |
| B. New `igc package explain-import --from M --to I` | answers allowed + denied + hypothetical; proactive | new CLI surface; module-selection + unresolved handling; only needed for the *allowed* case | **deferred** (later card; only if A proves insufficient) |
| C. Richer prose `message` only | trivial | not machine-actionable; agents still parse English; no fix field | rejected |
| D. Both A now + B now | complete | over-builds while the *denied* path (the actual pain) is solved by A alone | rejected (phase it: A → maybe B) |

## 4. Recommended v0 — enrich `OOF-IMP6`/`OOF-IMP7` with a generic `details`

Add `pub details: Option<Value>` to `ProjectDiagnostic` (default `None`; `to_value` emits it when present).
This is **generic** (any diagnostic kind may use it) — it does NOT spread package fields across the type, so
it honors P11. Populate it for the two import rules:

```jsonc
// OOF-IMP6 (scope): Mid.M imports Lib2.B; mid did not declare lib2
"details": {
  "kind": "import_scope",
  "importer": { "module": "Mid.M", "package": "mid",  "path": "../mid" },
  "provider": { "module": "Lib2.B", "package": "lib2", "path": "../lib2" },
  "declared_edge": false,
  "fix": "declare 'lib2' in the [dependencies] of package 'mid' (e.g. lib2 = { path = \"../lib2\" })"
}

// OOF-IMP7 (exports): Mid.M imports Leaf.Private; leaf exports only Leaf.Public
"details": {
  "kind": "import_export",
  "importer": { "module": "Mid.M",      "package": "mid",  "path": "../mid"  },
  "provider": { "module": "Leaf.Private","package": "leaf", "path": "../leaf" },
  "declared_edge": true,
  "provider_exports": { "mode": "allowlist", "modules": ["Leaf.Public"] },
  "exports_default": "open",
  "fix": "add 'Leaf.Private' to [exports] modules in package 'leaf', or import an exported module"
}
// closed-default seal variant: provider_exports.mode = "open", exports_default = "closed",
//   fix = "declare [exports] modules in 'leaf' (or set the root [package] exports = \"open\")"
```

`fix` is a **static template from the rule** (not a search / ranking) → stays *evidence*, not a solver
(Q7). The data is all already computed inside `index_integrity` (importer/provider `PackageId`, the graph's
`deps`/`exports`, `exports_default`) — enrichment only stops discarding it.

## 5. Card questions — answers

1. **New command or enrichment?** **Enrichment** for v0 (solves denied — the 80%); command deferred.
2. **Minimal command form (if any)?** `igc package explain-import --from <module> --to <module>` — **deferred**
   to a later card; covers allowed + hypothetical.
3. **Module selection under duplicates (OOF-IMP4)?** Not an issue: `OOF-IMP4` fires **before** IMP6/7 and
   blocks assembly, so explanations run only on an unambiguous graph. A future `explain-import` errors with
   `OOF-IMP4` if the module is duplicated. Documented.
4. **Explanation contents?** importer {module,package,path}, provider {module,package,path}, `declared_edge`
   bool, `provider_exports` {mode,modules}, `exports_default`, `fix`. (§4.)
5. **Allowed imports too?** Not via enrichment (no diagnostic for a pass) → **deferred** to the optional
   `explain-import` command.
6. **Unresolved imports (`OOF-IMP2`)?** Out of scope for enrichment — an unresolved import has **no provider**
   in the graph; it is `compile_units`' `OOF-IMP2`. A future `explain-import` would honestly say "unresolved:
   no package in the graph provides '<module>'" **without guessing** a provider by name.
7. **How to avoid a solver/linter?** `fix` is a single deterministic template per rule (no search, no
   ranking, no "did you mean", no auto-apply). Explanations are **evidence only** (closed scope honored).

## 6. Proposed implementation card — `LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19`

**Goal:** enrich `OOF-IMP6`/`OOF-IMP7` with the `details` block (§4); auto-surfaces in compile + `verify
--strict`.
**Implementation:** add `ProjectDiagnostic.details: Option<Value>` (+ `to_value` conditional emit, defaulting
`None` so all other diagnostics are byte-unchanged); populate it in the IMP6/IMP7 branches of
`index_integrity` from the graph data already in hand; static `fix` templates.
**Acceptance matrix:**
- [ ] OOF-IMP6 carries `details.kind = "import_scope"`, importer/provider {module,package,path},
      `declared_edge:false`, a `fix` mentioning `[dependencies]` of the importer package.
- [ ] OOF-IMP7 (allowlist miss) carries `details.kind = "import_export"`, `provider_exports.modules`,
      `declared_edge:true`, a `fix` mentioning `[exports]`.
- [ ] OOF-IMP7 (closed-default seal) carries `exports_default:"closed"` + the seal-specific `fix`.
- [ ] Transitive edges produce correct importer/provider packages + paths.
- [ ] `details` surfaces in `verify --strict` `integrity.diagnostic` (P11 path) and in compile diagnostics.
- [ ] Diagnostics without `details` (OOF-IMP4/IMP8/IMP9, all non-package rules) are byte-unchanged (no
      `details` key).
- [ ] Full `igniter-compiler` suite green; `git diff --check` clean.

Later (optional, gated): `LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-P20` — the proactive query command for
allowed/hypothetical/unresolved cases, only if P19 proves insufficient in practice.

## 7. Acceptance — mapping (this readiness)

- [x] Current `OOF-IMP6`/`OOF-IMP7` diagnostics characterized from live code (§2 table).
- [x] ≥3 UX shapes compared (§3: A/B/C/D).
- [x] Recommendation preserves local-only semantics, no solving (`fix` = static template, evidence only).
- [x] Actionable field/schema proposal included (§4).
- [x] No production code changes.

## 8. Closed scope (honored)

No implementation; no registry/remote/semver; no auto-fix (the `fix` string is advice, never applied); no
rename/refactor tooling; explanations are evidence only.

---

*Lab readiness packet. Grounded in the live generic `ProjectDiagnostic` + the P10/P12/P14 import rules.
Selected v0: enrich `OOF-IMP6`/`OOF-IMP7` with a generic `details` block (importer/provider/path/declared_edge/
provider_exports/policy/fix), surfacing through compile + `verify --strict`; defer a proactive
`explain-import` command. Next card `…-DIAGNOSTIC-DETAILS-P19` with an 8-point acceptance matrix.*
