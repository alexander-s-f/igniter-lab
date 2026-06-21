# lab-igniter-package-introspection-readiness-p17-v0 — `igc package` introspection CLI

**Card:** `LAB-IGNITER-PACKAGE-INTROSPECTION-READINESS-P17` · **Delegation:** `OPUS-IGNITER-PACKAGE-INTROSPECTION-READINESS-P17`
**Status:** READINESS / DESIGN (v0) — chooses the smallest useful `igc package` surface and fully specifies the
P18 implementation card. **No production code.** Authority: lab readiness, grounded in live `main.rs`/`project.rs`.

---

## 1. Executive summary

Ship **one boring command**: `igc package graph --project-root <dir>` — a **structural**, JSON-only view of
the assembled local package graph (P14 truth: nodes, edges, source roots, exports surface, root policy). It
exposes what agents/users need to *see* the workspace without re-running a build. **`status` is already
`verify --strict`** (drift + integrity), and **`explain-import` is a separate later card**. The internal
`PackageGraph`/`PackageNode`/`collect_package_graph` stay **private**; P18 adds one public accessor returning
a stable JSON value — the JSON schema is the contract, not the Rust types. Recommended next card:
**`LAB-IGNITER-PACKAGE-GRAPH-CLI-P18`** (§7).

## 2. Verify-first findings (live)

| Fact | Evidence | Consequence |
|---|---|---|
| Command dispatch is `match command.as_str()` (`compile`/`lock`/`verify`) | `main.rs` `fn main` | Adding a `"package"` arm with a `graph` subcommand is trivial and consistent. |
| All commands emit pretty JSON `{ "kind": "...", … }` by default; flags via positional scan; `--project-root` defaults `.` | `run_lock`/`run_verify`/`project_root_arg` | `igc package graph` should be **JSON-only** (no `--json` flag) and use `--project-root`. |
| `collect_package_graph`, `PackageGraph`, `PackageNode`, `PackageId` are **private** | `project.rs` (no `pub`) | Introspection needs a **new public accessor** returning a serializable view; internal structs stay private (Q9). |
| Public surface today: `resolve_entry`, `check_workspace_integrity`, `workspace_lock`/`verify_lock`, `ProjectConfig::load`, `current_toolchain` | `rg '^pub fn'` | None exposes the graph structurally → P18 adds `project::workspace_graph_value(root) -> Result<Value, ProjectError>`. |
| `collect_package_graph` returns `Err(OOF-IMP9)` on a missing dep path; succeeds (visited-bounded) on a cycle | P16 / P14 | `graph` returns the structured error for OOF-IMP9, but emits the full graph for a cycle (edges visible) + an optional `faults` note. |
| Assembly diagnostics already render structurally in `lock`/`verify` (`error: d.to_value()`, P16) | `main.rs` | `graph` reuses the same error convention for OOF-IMP9. |

## 3. Command-shape comparison (≥3)

| Shape | Pros | Cons | Verdict |
|---|---|---|---|
| **A. `igc package graph` only** | smallest; directly exposes P14 truth; agent-friendly; `package` namespace future-proofs `status`/`explain` | no import-debug yet | **SELECTED (v0)** |
| B. `igc package {graph,status,explain-import}` | full DX | `status` duplicates `verify --strict`; `explain-import` is a larger design (rules engine output) — premature | rejected for v0 (explain → later card) |
| C. `igc graph` (top-level, no namespace) | shortest | pollutes the top-level command space; no room for `package explain`/`status` later | rejected |
| D. `igc verify --graph` (flag on verify) | reuses verify | overloads a *check* command with a *read-only view*; graph is not pass/fail | rejected |

## 4. Recommended v0 — `igc package graph --project-root <dir>`

**Structural** view (no integrity checks, no digests). JSON schema:

```jsonc
{
  "kind": "igniter_package_graph",
  "root": ".",                          // root-relative; the root node's path
  "exports_default": "open",            // the ROOT's [package] exports policy: "open" | "closed"
  "packages": [                          // sorted by path; each package ONCE (diamond → one node)
    {
      "label": "<root>",                 // "<root>" for the workspace root; else smallest declaring edge name
      "path": ".",                       // root-relative canonical path (stable across machines)
      "source_roots": ["src"],
      "exports": { "mode": "open" },     // "open" (no block) | "sealed" ([]) | "allowlist" (+ "modules")
      "dependencies": [ { "label": "mid", "path": "../mid" } ]   // declared edges, by label + path
    },
    {
      "label": "mid", "path": "../mid", "source_roots": ["src"],
      "exports": { "mode": "allowlist", "modules": ["Mid.Public"] },
      "dependencies": [ { "label": "leaf", "path": "../leaf" } ]
    },
    { "label": "leaf", "path": "../leaf", "source_roots": ["src"],
      "exports": { "mode": "open" }, "dependencies": [] }
  ],
  "faults": []                           // e.g. ["OOF-IMP8 cycle: a -> b -> a"] if detect_cycle finds one
}
```

**Field decisions (Q3/Q4/Q5):**
- **Root included** (Q4) — label `<root>`, path `.` — so the graph is self-describing.
- **No digest** (Q3) — digests are the **lock's** job (`igc lock`); keeping `graph` structural avoids
  duplicating provenance and keeps it cheap. Documented carve-out.
- **Diamond dedup** (Q5) — each package appears **once** in `packages` (keyed by path); multiple parents each
  list it under their `dependencies`. **No version field** → no implication of version solving.
- `exports` mode mirrors P10/P12: `open` (no `[exports]`), `sealed` (`modules=[]`), `allowlist` (+ list).
- `exports_default` exposes the **root** closed-default policy (P12).

## 5. Error / diagnostic behavior (OOF-IMP6/7/8/9)

| Fault | In `igc package graph`? |
|---|---|
| **OOF-IMP9** (missing dep path) | `collect_package_graph` fails → emit the **structured error** (`{kind, error: d.to_value()}`, exit 1), same as `lock`/`verify` (P16). No partial graph. |
| **OOF-IMP8** (cycle) | graph **assembles** (visited-bounded) → emit the full structure (cyclic edges visible) **plus** a `faults` entry; exit 0 (it's a view, not a gate). The authoritative failure stays `verify --strict`. |
| **OOF-IMP6 / OOF-IMP7** (scope / export *import* violations) | **NOT reported** — these are import-level faults requiring a module scan + `index_integrity`; `graph` is **structural only**. Boundary documented: `graph` shows *what is declared*; `verify --strict` shows *what is violated*. |

This crisp split (structure vs. violations) is the whole point: `igc package graph` = "what is the graph",
`igc verify --strict` = "is it healthy". Q7 → **no separate `status`** is needed; `verify --strict` is status.

## 6. Card questions — answers

1. **One command or three?** One — `graph`. (`status` = `verify --strict`; `explain` = later card.)
2. **Output format?** JSON-only, `--project-root` default `.` (consistent with `lock`/`verify`).
3. **Fields?** label, path, source_roots, exports{mode,modules?}, dependencies[{label,path}]; **no digest**.
4. **Include root?** Yes (`<root>`, path `.`).
5. **Diamond?** One node per path; parents reference it; no version field.
6. **Cycle/missing → partial or fail?** OOF-IMP9 → fail (structured error). Cycle → full graph + `faults`.
7. **Does `verify --strict` answer `status`?** Yes → no `status` command in v0.
8. **`explain-import`?** Separate later card (`LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-P19+`): given importer+import,
   say allowed (same-package / declared-edge / exported) or denied (OOF-IMP6 / OOF-IMP7) with reasons.
9. **Private/internal?** `PackageGraph`/`PackageNode`/`PackageId`/`collect_package_graph` stay private; only the
   JSON value (via one `pub fn`) is stable. Don't stabilize the Rust types.
10. **First impl card?** `LAB-IGNITER-PACKAGE-GRAPH-CLI-P18`.

## 7. Proposed implementation card — `LAB-IGNITER-PACKAGE-GRAPH-CLI-P18`

**Goal:** `igc package graph --project-root <dir>` emits the §4 JSON.
**Implementation:** `project::workspace_graph_value(root) -> Result<Value, ProjectError>` (builds the graph via
the existing private `collect_package_graph`, projects nodes→JSON sorted by path, runs `detect_cycle` for
`faults`); `main.rs` `package` command + `graph` subcommand; OOF-IMP9 → structured error arm (reuse P16
helper shape).
**Acceptance matrix:**
- [ ] `igc package graph` on `workspace_transitive_ok` → root + mid + leaf, edges `<root>→mid`, `mid→leaf`,
      `leaf` exports `open`/`mid` exports `allowlist`/etc.
- [ ] Diamond (`workspace_transitive_diamond`) → `c` appears once; both `a` and `b` list `c` as a dependency.
- [ ] Closed-default workspace → `exports_default: "closed"`; sealed package → `exports.mode: "sealed"`.
- [ ] Cycle (`workspace_transitive_cycle`) → full graph + `faults: ["OOF-IMP8 …"]`, exit 0.
- [ ] Missing dep (`workspace_missing_root_dep`) → structured `error.rule = OOF-IMP9`, exit 1.
- [ ] JSON deterministic (sorted by path) across runs; `--project-root` default `.`.
- [ ] No digest field; root included; internal structs stay private (only the JSON `pub fn` added).
- [ ] Full `igniter-compiler` suite green; `git diff --check` clean.

## 8. Acceptance — mapping (this readiness)

- [x] Live CLI/project surfaces verified (dispatch style, private graph types, public accessors).
- [x] ≥3 command shapes compared (§3: A/B/C/D).
- [x] Recommended v0 command + exact JSON schema drafted (§4).
- [x] Error/diagnostic behavior for OOF-IMP6/7/8/9 addressed (§5).
- [x] Implementation card proposed with bounded tests (§7).
- [x] No production code changes.

## 9. Closed scope (honored)

No implementation; no registry/remote/semver; no publishing/install UX; no lock-format change (digest stays
the lock's concern, deferred as a future option not taken here).

---

*Lab readiness packet. Grounded in live `main.rs` dispatch + the private `project.rs` graph. Selected v0:
one structural `igc package graph` (JSON), root included, no digest, diamond = one node, cycle → graph +
faults, missing path → structured OOF-IMP9 error; `verify --strict` remains status; `explain-import` deferred.
P18 card + acceptance matrix enumerated.*
