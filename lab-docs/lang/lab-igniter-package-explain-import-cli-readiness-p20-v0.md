# lab-igniter-package-explain-import-cli-readiness-p20-v0 — proactive import explanation command

**Card:** `LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-READINESS-P20` · **Delegation:** `OPUS-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-READINESS-P20`
**Status:** READINESS / DESIGN (v0) — go/no-go on a proactive import-explanation command. **Recommendation:
qualified GO** — a small, single-edge `igc package explain-import` command closes a *genuine* gap that P19
cannot (allowed + hypothetical imports), reusing the existing rule engine; but it is **lower priority** than
the remote/registry wave, so it is dispatched as a ready-to-run card (`…-P21`), not urgent. **No production
code here.**

---

## 1. Executive summary

P19 made **denied authored** imports actionable (`OOF-IMP6`/`OOF-IMP7` carry `details` + `fix` at compile /
`verify --strict`). Two questions remain genuinely unanswerable today:
- **Allowed:** "why is `App.Main` *allowed* to import `Mid.Public`?" — a passing import produces **no**
  diagnostic, so nothing explains it.
- **Hypothetical:** "*would* `Mid.M` be allowed to import `Leaf.Private`?" — answering requires editing source
  and recompiling.

`igc package graph` (P18) exposes the *data* (nodes/edges/exports) but **not the verdict** — an agent must
re-implement the OOF-IMP6/7 rules client-side to decide. A one-edge `explain-import` runs the **real** rule
server-side and returns `allowed`/`denied`/`unresolved` + reason, reusing P19's `details` for the denied case.
That single-source-of-truth verdict (no client rule re-derivation) is the command's real value. The closed
scope of this card explicitly *permits* "explaining one requested import edge" — so the command is in-bounds
by design.

## 2. Verify-first findings

| Fact | Evidence | Consequence |
|---|---|---|
| Denied authored imports already explained | P19 `details` on `OOF-IMP6`/`OOF-IMP7` (compile + `verify --strict`) | command must NOT duplicate this — it adds *allowed* + *hypothetical* |
| No diagnostic for a passing import | `index_integrity` only emits on a violation | "why allowed?" needs a query, not a diagnostic |
| `igc package graph` gives data, not verdict | `workspace_graph_value` (P18) emits nodes/edges/exports | agent must re-derive rules → a server-side verdict is the gap-filler |
| The rule is a per-edge predicate | `index_integrity`: scope = `graph.nodes[importer].deps.contains(provider)` (or same package); export = provider's `exports` + root `exports_default` | a single-edge `explain_import(from,to)` reuses the SAME predicate — factor it out, do not fork |
| Module→package mapping needs the full index | `by_module: module → ScannedFile{package}` (private) | command needs `build_module_index`, not graph-only — a new `pub` accessor in `project.rs` |
| Unresolved import = no provider | `OOF-IMP2` is `compile_units`' domain; an import with no module in the index | explain returns `unresolved` (no provider), **no name guessing** |
| Duplicate module = ambiguous | `OOF-IMP4` (dup_acc) blocks clean assembly | explain returns the `OOF-IMP4` assembly fault, not a guess |

## 3. Shape comparison (≥3)

| Shape | Pros | Cons | Verdict |
|---|---|---|---|
| **A. `igc package explain-import --from <module> --to <module>`** | explicit edge; matches the bias's exact form; symmetric with `package graph`; JSON verdict | new subcommand | **SELECTED** |
| B. `igc package explain --module <m> --import <i>` | reads naturally | "explain" is vague (explain what?); two near-synonym flags | rejected |
| C. No command — extend `igc package graph` consumers to derive verdicts client-side | zero new surface | forces every agent to re-implement OOF-IMP6/7; not authoritative; drifts from the engine | rejected (the gap is exactly "give me the verdict") |
| D. A `--explain <from>,<to>` flag on `verify` | reuses a command | overloads the CI gate with a query mode; awkward | rejected |

## 4. Recommended command (v0)

```text
igc package explain-import --project-root <dir> --from <module> --to <module>
```

- **Hypothetical by design:** `--from`/`--to` are module *names*; the pair need not be an actual import edge.
  This answers both "why is this authored import allowed?" and "would this *new* import be allowed?".
- **Exact module names only** — not a scan, not a linter (closed scope; Q8).
- **JSON only** (matches `package graph`); no `--json` flag.

### JSON schema
```jsonc
{
  "kind": "igniter_explain_import",
  "from": "Mid.M",
  "to": "Leaf.Private",
  "decision": "allowed" | "denied" | "unresolved",
  "reason": "same_package" | "declared_edge_exported"        // allowed
          | "scope" | "export"                               // denied (→ OOF-IMP6 / OOF-IMP7)
          | "unresolved_provider",                           // to-module not in the index
  "importer": { "module": "Mid.M", "package": "mid", "path": "../mid" },
  "provider": { "module": "Leaf.Private", "package": "leaf", "path": "../leaf" },   // omitted if unresolved
  "details": { … P19 schema (kind import_scope/import_export + fix) … }             // present only when denied
}
```
- **allowed** → `reason: same_package` or `declared_edge_exported`; include provider + (for cross-package) the
  provider's `exports` surface as evidence.
- **denied** → reuse the **P19 `details`** block verbatim (`import_scope` for scope, `import_export` for
  export, including the closed-default seal distinction) — single rule source.
- **unresolved** → `to` resolves to no module in the index → `decision: "unresolved"`, no `provider`, no
  guessing.

### Exit codes
- **0** for any *successful explanation* — `allowed`, `denied`, or `unresolved` are all valid answers (mirrors
  `package graph`: a view succeeds even when it reports a fault).
- **1** for *command errors*: `--from` module not found in the index; an assembly fault (`OOF-IMP9` missing
  dep, or `OOF-IMP4` duplicate module that makes the requested module ambiguous) — emitted as structured
  `{ "kind": "igniter_explain_import", "ok": false, "error": <diag> }`.

## 5. Card questions — answers

1. **Still needed after P19?** Yes — for *allowed* + *hypothetical* (P19 covers only denied-authored).
2. **Shape?** `explain-import --from --to` (Shape A).
3. **Current or hypothetical?** Hypothetical (evaluate any from/to pair).
4. **Allowed reasons?** `same_package` / `declared_edge_exported` (+ provider exports evidence).
5. **Denied reuse P19?** Yes — emit the same `details` block.
6. **Unresolved (`OOF-IMP2`)?** `decision: "unresolved"`, no provider, no name guessing.
7. **Duplicate module (`OOF-IMP4`)?** Assembly fault → exit 1 with the `OOF-IMP4` diagnostic (ambiguous).
8. **Scan or exact?** Exact module names only.
9. **Graph-only or full index?** Full module index (needs module→package mapping); reuses `build_module_index`.
10. **JSON + exit?** §4 — exit 0 for allowed/denied/unresolved, exit 1 for command/assembly errors.

## 6. Solver / auto-fix boundary

The command explains **one requested edge** and returns the rule outcome + (for denied) the P19 static `fix`
string. It does **not**: scan for problems, rank fixes, suggest alternatives ("did you mean"), resolve
versions, or apply anything. Evidence only — identical discipline to P19. (Closed scope honored.)

## 7. Proposed implementation card — `LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-P21`

**Implementation:**
- Factor the per-edge **scope predicate** (`edge_declared(importer_canon, provider_canon, graph)`) and the
  **export predicate** (`export_status(provider_canon, module, graph, exports_default)`) out of
  `index_integrity` into shared helpers — `index_integrity` and `explain_import_value` both call them (no
  forked rules).
- Add `pub fn explain_import_value(root, from: &str, to: &str) -> Result<Value, ProjectError>` in
  `project.rs` (builds the index; assembly faults → `Err`; `from` missing → `Err`).
- Add `igc package explain-import --from --to [--project-root]` in `main.rs` (subcommand of `package`).

**Acceptance matrix:**
- [ ] Allowed same-package edge → `decision:"allowed", reason:"same_package"`.
- [ ] Allowed declared+exported cross-package edge → `decision:"allowed", reason:"declared_edge_exported"`,
      with provider exports evidence.
- [ ] Denied undeclared edge → `decision:"denied", reason:"scope"`, `details.kind:"import_scope"` (P19).
- [ ] Denied non-exported edge → `decision:"denied", reason:"export"`, `details.kind:"import_export"` (P19);
      closed-default seal distinguished.
- [ ] Hypothetical (a `--to` not actually imported by `--from`) is evaluated correctly.
- [ ] Unresolved `--to` → `decision:"unresolved"`, no provider, exit 0.
- [ ] `--from` not found / `OOF-IMP4` ambiguous / `OOF-IMP9` missing dep → structured error, exit 1.
- [ ] `index_integrity` still emits identical OOF-IMP6/7 (shared predicate refactor is behavior-preserving).
- [ ] Full `igniter-compiler` suite green; `git diff --check` clean.

## 8. Acceptance — mapping (this readiness)

- [x] Live P19/P18/P16 behavior verified (§2).
- [x] ≥3 command/API shapes compared (§3).
- [x] JSON schema + exit-code policy drafted (§4).
- [x] Allowed / denied / unresolved / duplicate-module cases addressed (§4–§5).
- [x] Solver/auto-fix boundary stated (§6).
- [x] No production code changes.

## 9. Closed scope (honored)

No implementation; no registry/remote/semver; no auto-fix; no rename/refactor; no linter beyond the single
requested edge.

---

*Lab readiness packet. Verify-first confirms P19 covers only denied-authored imports; allowed + hypothetical
remain a real (if modest) gap that `igc package graph` data alone cannot close without client-side rule
re-derivation. Recommendation: **GO (small, lower-priority)** — `igc package explain-import --from --to`,
JSON, hypothetical, reusing P19 `details` for denied and a factored shared predicate. Next card
`…-EXPLAIN-IMPORT-CLI-P21` with a 9-point acceptance matrix.*
