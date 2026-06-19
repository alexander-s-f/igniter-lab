# lab-igniter-lab-repo-boundary-readiness-p1-v0 — repo boundary readiness map

**Card:** `LAB-IGNITER-LAB-REPO-BOUNDARY-READINESS-P1` · **Delegation:** `OPUS-LAB-REPO-BOUNDARY-A`
**Status:** READINESS / PLANNING (no moves). A boundary map of `igniter-lab`: what belongs together,
what is live vs stale vs generated, what blocks a split, and what to clean first. **No `git mv`, no
deletes, no Cargo/workspace rewiring, no canon.**
**Authority:** Lab planning. Verified against the live tree + git state 2026-06-19.

## 1. Executive summary

`igniter-lab` is a single directory holding **12 Rust crates** (no Cargo workspace root — all coupled by
**relative `../` path deps**), several **Ruby proof crates**, two **IDE tools** (Kotlin plugin + Tauri
shell), a large **fixtures** tree (`igniter-apps`, 120 `.ig`), **~916 docs/cards** (`lab-docs` 457 +
`.agents` 459), and assorted **stale/generated noise** (a 0-byte `igniter-compiler/igniter-view-engine/
out`, an empty nested `igniter-lab/igniter-lab/`, a sibling `../igniter-view-engine` copy, an `igniter-
site` with only a README, `.codex-local`/`.idea`). **The single hard blocker to any crate split is the
missing Cargo workspace root**: every `../igniter-x` path dep (and a machine-test `../ln` fixture
symlink) breaks the moment a crate dir relocates. **Recommended first move = a no-code cleanup pass**
(view-engine disposition + generated/stale hygiene), NOT a crate extraction; the structural enabler for
any later split is a **Cargo workspace root** (additive). Git is clean (only this card untracked).

## 2. Verified inventory (top-level)

| Dir | Classification | Evidence | Domain |
|---|---|---|---|
| `igniter-compiler` | LIVE_CRATE | `igniter_compiler`; no path deps | language-core |
| `igniter-vm` | LIVE_CRATE | `igniter_vm` → stdlib | language-core |
| `igniter-stdlib` | LIVE_CRATE | `igniter_stdlib`; leaf | language-core |
| `igniter-machine` | LIVE_CRATE | `igniter_machine` → compiler, vm, tbackend; (dev) console, ui-kit | machine-runtime |
| `igniter-tbackend` | LIVE_CRATE | `igniter_tbackend_playground`; leaf | machine-runtime |
| `igniter-server` | LIVE_CRATE | `igniter_server` → machine(opt); (dev) web | server-web |
| `igniter-web` | LIVE_CRATE | `igniter_web` → server, compiler, machine | server-web |
| `igniter-frame` | LIVE_CRATE | `igniter_frame` → machine(opt) | frame-ui |
| `igniter-ui-kit` | LIVE_CRATE | `igniter_ui_kit` → frame | frame-ui |
| `igniter-console` | LIVE_CRATE | `igniter_console` → frame, ui-kit | frame-ui |
| `igniter-3d` | LIVE_CRATE | `igniter_3d` → frame | frame-ui |
| `igniter-gui` | LIVE_CRATE | `igniter_gui` → frame | frame-ui |
| `igniter-ide` | LIVE_TOOL | `src-tauri/Cargo.toml` (Tauri; 15 `.rs`) | ide-tools |
| `igniter-jetbrains-plugin` | LIVE_TOOL | Kotlin/Gradle (46 kt/java + 6 `.ig`); **no Cargo coupling** | ide-tools |
| `igniter-apps` | PROOF_FIXTURE | 120 `.ig` + 8 `.rb` pressure apps; machine tests read via `../ln` | apps-fixtures |
| `igniter-research` | PROOF_FIXTURE / DOC | 18 `.rb` + 2 `.ig` | apps-fixtures |
| `igniter-3d-poc` | PROOF_FIXTURE | 2 `.rb` (Ruby math proof; superseded by Rust `igniter-3d`) | apps-fixtures |
| `igniter-gui-engine` | PROOF_FIXTURE | 13 `.rb` (Ruby; superseded by Rust `igniter-gui`) | apps-fixtures |
| `acts-as-tbackend` | PROOF_FIXTURE / UNKNOWN | 6 `.rb` (Ruby tbackend; relation to `igniter-tbackend` unclear) | apps-fixtures |
| `tools` | LIVE_TOOL / UNKNOWN | 2 `.rb` scripts | apps-fixtures |
| `igniter-view-engine` | PROOF_FIXTURE (11M) | README+lib+fixtures+proofs+`out`+JS runtime; source of `web_router` fixtures | apps-fixtures (historical) |
| `igniter-compiler/igniter-view-engine` | GENERATED_OUTPUT | **0 bytes**, only `out/` | noise |
| `igniter-site` | STALE_DUPLICATE / UNKNOWN | only `README.md`; superseded by `../igniter-org` | archive |
| `igniter-lab/igniter-lab` (nested) | STALE_DUPLICATE | empty but for one `.agents` dir (Jun 9) | noise |
| `lab-docs` | DOC_EVIDENCE | 457 `.md` | lab-evidence |
| `.agents` | DOC_EVIDENCE | 459 cards | lab-evidence |
| `.codex-local`, `.idea`, `.git` | GENERATED_OUTPUT / VCS | tooling state | noise |

Workspace siblings (`../`): `igniter-gov`, `igniter-lang`, `igniter-org`(+`-jekyll`), `igniter-ruby`,
`igniter-sparkcrm`, `igniter-archive`, `igniter-experiments`, **`igniter-view-engine`** — i.e. the
authority repos (gov/lang) + product (sparkcrm) + sites + an archive + a view-engine copy already live
*outside* `igniter-lab`.

## 3. Domain map

- **language-core** (compiler, vm, stdlib): tight triangle (`vm→stdlib`); `compiler`/`stdlib` are leaves.
  Owner surface = `igniter-compiler`. Splittable in principle, but everything above depends on it.
- **machine-runtime** (machine, tbackend): `machine → compiler+vm+tbackend` → **depends DOWN into
  language-core**; not independent. Also (dev) → console/ui-kit (frame-ui) for the P20 E2E test, and
  reads `../ln` fixtures.
- **server-web** (server, web): `web → server+compiler+machine`, `server → machine`, `server →(dev) web`
  (cycle). Depends on BOTH language-core and machine — cannot stand alone.
- **frame-ui** (frame, ui-kit, console, 3d, gui): rooted at `frame → machine` (machine-free core via
  `default-features=false`); `ui-kit/console/3d/gui → frame`.
- **ide-tools** (jetbrains-plugin, ide): separate ecosystems (Kotlin/Gradle; Tauri) — the **least
  Cargo-coupled** to the constellation.
- **apps-fixtures** (igniter-apps + Ruby proofs + view-engine + tools + research): pressure apps,
  fixtures, and **superseded Ruby originals** (3d-poc, gui-engine, possibly acts-as-tbackend) whose Rust
  successors are live.
- **lab-evidence** (lab-docs, .agents): ~916 docs/cards — the lab's process memory, the biggest volume.
- **noise** (compiler/igniter-view-engine/out, nested igniter-lab, .codex-local, .idea, igniter-site).

## 4. `igniter-view-engine` disposition (special focus)

Three locations, **not three live forks** — one substantive, one generated stub, one sibling copy:

| Location | Size | Contents | Verdict |
|---|---|---|---|
| `igniter-lab/igniter-view-engine/` | **11M** | README + `lib` + `fixtures` + `proofs` + `out` + `igniter_view_runtime.js` + browser proof | **historical PROOF_FIXTURE** — the JS view-engine experiment; **source of the `rack_core`/`web_router` fixtures** still cited. The live UI line (frame/ui-kit/console + ViewArtifact/`.igv`) has **superseded the "view-engine" name** for Rust UI work. Keep as archived fixtures; most of 11M is likely `out`/proofs (generated) that can be pruned. |
| `igniter-lab/igniter-compiler/igniter-view-engine/` | **0 B** | only `out/` | **GENERATED_OUTPUT / delete-candidate** — a stray empty compile-out dir under the compiler; pure noise. |
| `../igniter-view-engine/` (sibling) | 432K | `fixtures` + `out` + `proofs` (no `lib`/README) | **STALE_DUPLICATE / archive-candidate** — a smaller sibling copy of proofs; needs a human keep/archive decision. |

**Conclusion:** "view-engine" is superseded by the frame-ui line for live work; the lab copy is valuable
only as historical fixtures. **Safest next action = a dedicated disposition card** (archive-map the lab
copy, name the 0-byte compiler stub + sibling copy as delete/archive candidates). **No deletion here.**

## 5. Dependency / coupling map

**Hard blockers (block an immediate split):**
- **No Cargo workspace root** + **relative `../` path deps** across all 12 crates. Relocating any crate
  dir changes its `../` depth and **breaks every crossing path dep**. This is THE blocker.
- **`machine` tests read `../ln/...`** (`../ln/web_router`, `../ln/fixtures/storage_capability/…`) — `ln`
  is a sibling (likely a symlink, not listed as a dir) into the fixtures tree (`igniter-apps`/view-engine).
  Splitting machine from fixtures breaks these tests; the symlink itself is fragile.
- **`machine →(dev) console + ui-kit`** (P20 binding-console E2E) — splitting frame-ui breaks a machine
  dev test.
- **`server ↔ web` dev-cycle** and `web → compiler+machine` — server-web is internally + downward coupled.

**Search-and-replace cleanup (NOT hard blockers):**
- ~916 cards/proof docs with hardcoded `igniter-x/...` paths (fixable by sweep).
- IDE/run assumptions, `.idea`, local `target/` — regenerable.
- The `../ln` symlink — re-point or replace with an explicit relative path.

## 6. Split candidates & risk ranking (low → high)

1. **Cleanup/hygiene (view-engine + generated/stale)** — *lowest risk, highest noise reduction.* No
   build impact: 0-byte compiler stub, nested empty `igniter-lab`, `.codex-local`, `igniter-site`
   README-only, and the 11M view-engine `out`/proofs.
2. **`igniter-jetbrains-plugin`** — *low risk physical split.* Separate Kotlin/Gradle ecosystem, **zero
   Cargo path coupling**; IGC integration is via discovery (`IGNITER_COMPILER`/PATH), not path deps. The
   single cleanest crate-ish extraction — but premature without the cleanup + a value reason.
3. **lab-evidence (`lab-docs` + `.agents`)** — *low build risk, medium process risk.* No build coupling,
   but it's the lab's working memory; relocating needs the path-sweep + agent-process update.
4. **Any Rust cluster (frame-ui / server-web / language-core / machine)** — *high risk.* All `../`-coupled
   with no workspace root; every split breaks path deps. **Precondition: a Cargo workspace root** (so
   members relocate while `[workspace]` keeps deps resolvable), or convert `../` → workspace/registry deps.

## 7. Recommended first move

**A no-code cleanup pass — `igniter-view-engine` disposition + generated/stale hygiene — NOT a crate
split.** Rationale: it removes the loudest noise (0-byte stub, nested empty lab, 11M of likely-generated
view-engine output, README-only site) with **zero build/dependency impact**, and it sharpens the
inventory before any structural move. The **structural enabler** for later crate relocation is a **Cargo
workspace root** (additive; doesn't move dirs) — proposed as the *at-most-one* structural next card, to
be done before any frame-ui/server-web/lang-core extraction. If a single physical extraction is forced
now, `igniter-jetbrains-plugin` is the only low-risk one (no Cargo coupling) — but it is not urgent.

## 8. What remains in `igniter-lab` (stays together for now)

The **entire Rust constellation** — language-core (compiler/vm/stdlib) + machine-runtime
(machine/tbackend) + server-web (server/web) + frame-ui (frame/ui-kit/console/3d/gui) — **must stay
co-located until a Cargo workspace root exists**, because of the `../` path-dep web. In particular:
**server-web stays with machine + compiler** (web depends on both; tight IgWeb↔server↔machine
iteration is still active, P5–P12); **machine stays near apps-fixtures** (the `../ln` test coupling) and
near frame-ui (dev E2E) until those are decoupled. `igniter-apps` fixtures stay (machine + compiler tests
read them). Docs/cards stay until a path-sweep is planned.

## 9. Relationship to package/workspace direction (kept distinct)

Repo-boundary cleanup is **not** the package manager. But they share **one precondition**: a **Cargo
workspace root** at the Rust level is the natural place to *also* host the `.ig` **import-ownership
workspace** (`LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3`, the validated/independent first slice —
import-ownership first, **no registry/lockfile/install hooks**, app-local packages + dialect/IgWeb
packaging later). Sequence: introduce the Cargo workspace root (repo-boundary), then layer the `.ig`
workspace resolver (package direction) on the same root. Do not conflate the two cards.

## 10. Agent parallelization plan

- **Opus:** final synthesis, risk ranking, first-move recommendation (this packet) + future split arch.
- **Gemini:** broad inventory shards — directory census, stale/duplicate detection, hardcoded-path
  reference scans (esp. across the 916 docs + the `../ln` symlink + the 3 view-engine locations). **One
  lab artifact only; no gov writes.**
- **Sonnet:** reviewer/critic — challenge the domain map + split candidates + names; hunt hidden coupling
  (dev-deps, symlinks, fixture paths) and docs drift the census misses.
- **Codex:** live verifier — run exact `git`/`cargo tree`/`rg`/`find` checks (confirm the `../ln` target,
  view-engine `out` vs source split, jetbrains-plugin coupling) and, **only if a later card authorizes**,
  execute mechanical moves.

Shard by lens, not by re-asking the same question.

## Next cards (≤3; ≥1 no-code, ≤1 structural move)

1. **`LAB-IGNITER-VIEW-ENGINE-DISPOSITION-P2`** *(no-code)* — classify + archive-map the 3 view-engine
   locations; name the 0-byte compiler stub + sibling copy as delete/archive candidates; decide whether
   the lab copy stays as archived fixtures. No deletion.
2. **`LAB-IGNITER-LAB-GENERATED-OUTPUT-HYGIENE-P2`** *(no-code)* — inventory `out/`/`target/`/`proofs/` +
   the nested `igniter-lab/igniter-lab` + `.codex-local` + `igniter-site`; audit the `../ln` symlink;
   propose `.gitignore`/archive plan. No deletion.
3. **`LAB-IGNITER-CARGO-WORKSPACE-ROOT-P3`** *(at-most-one structural move)* — add a Cargo `[workspace]`
   root listing the 12 crates as members so `../` path deps become workspace deps (additive; **no dir
   moves**). This is the precondition that unblocks every later crate extraction AND hosts the `.ig`
   import-ownership workspace.

---

*Readiness/planning only. Compiled 2026-06-19 against the live tree + git (clean but this card). No files
moved; no Cargo/dependency topology changed. First move = no-code cleanup; structural enabler = a Cargo
workspace root before any Rust-crate split.*
