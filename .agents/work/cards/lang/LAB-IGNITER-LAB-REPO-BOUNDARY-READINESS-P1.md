# LAB-IGNITER-LAB-REPO-BOUNDARY-READINESS-P1 — lab repo boundary readiness

Status: CLOSED (readiness packet)  
Lane: standard / readiness / repository-boundary design  
Opened: 2026-06-19  
Closed: 2026-06-19  
Delegate label: OPUS-LAB-REPO-BOUNDARY-A  
Skill: idd-agent-protocol  

## Why This Card

`igniter-lab` has become a productive but noisy warehouse:

- language/toolchain crates sit beside machine/runtime crates;
- IgWeb/server work now has its own shape;
- frame/UI/console/3D work has its own axis;
- IDE/plugin work is a separate platform track;
- app fixtures and generated proof outputs are mixed with active crates;
- `igniter-view-engine` appears in more than one place and is especially unclear.

Before IgWeb runner polish continues, we need a **repo-boundary readiness map**:
what belongs together, what is live vs stale, what should split first, and what
must not move yet.

This is a planning card only. Do **not** move files, create repos, or rewrite
Cargo/workspace topology in this card.

## Authority

Readiness/design only.

Allowed:
- Inspect the live repository tree and git state.
- Inspect `Cargo.toml`, `README`, `IMPLEMENTED_SURFACE.md`, test files, and
  recent proof docs as needed.
- Produce one readiness packet and close this card with findings.
- Add thin pointers only if a living map/front-door already clearly wants one.

Not allowed:
- No `git mv`, file moves, directory deletion, or repo extraction.
- No package/workspace manager implementation.
- No `Cargo.toml` dependency rewiring.
- No cleanup of `target/`, generated outputs, `.idea`, `node_modules`, or old
  proof artifacts.
- No new public repo names as authority. Proposed names are recommendations.
- No canon claim and no live deployment claim.

## Verify First

Live code and git state outrank memory and old docs.

Start with:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
git status --short
find . -maxdepth 2 -type d | sort
find .. -maxdepth 2 -type d | sort
rg -n "name =|members|igniter-view-engine|igniter-web|igniter-server|igniter-machine" \
  Cargo.toml */Cargo.toml */*/Cargo.toml 2>/dev/null
```

Then inspect, at minimum:

- `igniter-compiler/`
- `igniter-vm/`
- `igniter-stdlib/`
- `igniter-machine/`
- `igniter-tbackend/`
- `igniter-server/`
- `igniter-web/`
- `igniter-frame/`
- `igniter-ui-kit/`
- `igniter-console/`
- `igniter-3d/`
- `igniter-gui/`
- `igniter-design-system/`
- `igniter-jetbrains-plugin/`
- `igniter-ide/`
- `igniter-apps/`
- `igniter-view-engine/`
- `igniter-compiler/igniter-view-engine/`
- `../igniter-view-engine/` if present
- `lab-docs/`
- `.agents/work/cards/lang/`

If a directory has a `Cargo.toml`, capture its package name and direct path
dependencies. If it has no manifest, classify by evidence: `src/`, `lib/`,
`tests/`, `fixtures/`, `proofs/`, `out/`, `docs/`, or only generated state.

## Questions To Answer

### 1. What domains actually exist?

Propose a domain map. Start from these candidate buckets, but correct them if
live evidence disagrees:

- `language-core`: compiler, VM, stdlib, parser/lowering, language tests.
- `machine-runtime`: machine, tbackend, capability-IO, effect substrate.
- `server-web`: igniter-server, igniter-web, IgWeb runner/builder.
- `frame-ui`: frame, ui-kit, console, 3D, GUI, design-system.
- `ide-tools`: JetBrains plugin, Tauri/IDE shells, editor integrations.
- `apps-fixtures`: pressure apps, examples, fixtures, benchmarks.
- `lab-evidence`: lab-docs, cards, proof packets, daily checkpoints.
- `archive-or-unknown`: old duplicates, generated outputs, stale experiments.

For each domain, name the owner surface, the active crates/directories, and the
primary reason it should or should not be split.

### 2. What is live, stale, proof-only, or generated?

Classify every top-level directory:

```text
LIVE_CRATE        actively built/tested crate
LIVE_TOOL         active tool/plugin but maybe separate ecosystem
PROOF_FIXTURE     authored example/pressure app/proof harness
DOC_EVIDENCE      cards/proofs/docs/checkpoints
GENERATED_OUTPUT  target/out/build/proofs that should not guide architecture
STALE_DUPLICATE   likely obsolete duplicate of a newer surface
UNKNOWN           needs human decision
```

Do not guess quietly. If evidence is weak, mark `UNKNOWN` and explain the next
cheap verification.

### 3. What is the `igniter-view-engine` situation?

This is a special focus.

Compare:

- `igniter-lab/igniter-view-engine/`
- `igniter-lab/igniter-compiler/igniter-view-engine/`
- workspace-level `../igniter-view-engine/` if present

Answer:

- Are these duplicates, forks, generated copies, or distinct tracks?
- Which one has current live use, if any?
- Is "view-engine" still the right name, or has the frame/ui line superseded it?
- What is the safest next action: archive-map, delete-candidate, move-candidate,
  or keep-as-is?

No deletion in this card.

### 4. What cannot move yet?

List dependencies and coupling that block an immediate split:

- path dependencies between crates;
- tests importing sibling fixtures;
- generated fixture paths;
- cards/proof docs with hardcoded paths;
- IDE/run scripts;
- local target/build assumptions;
- workspace root assumptions;
- dirty or untracked files if any.

Separate **hard blockers** from **search-and-replace cleanup**.

### 5. What should split first?

Recommend one first physical split candidate and explain why it is low-risk.

Possible candidates:

- extract `igniter-web` + related examples after IgWeb runner stabilizes;
- extract `frame-ui` cluster;
- extract `ide-tools`;
- separate `lab-docs/.agents` from active crates;
- extract language core.

Choose one, or say none should split before a cleanup pass. The answer must
be evidence-based, not aesthetic.

### 6. What should stay together for now?

Name domains that look separable but should stay together until a boundary is
stronger. For example: if `igniter-web` still needs tight iteration with
`igniter-server` and `igniter-machine`, say so.

### 7. What is the repo topology target?

Propose a target shape. Keep it concrete but non-binding:

```text
igniter-lang-rs        language compiler/vm/stdlib
igniter-machine        runtime substrate/capability IO
igniter-server-web     generic server + IgWeb builder/runner
igniter-frame-ui       frame/ui-kit/console/3d/gui
igniter-ide-tools      JetBrains/Tauri/editor tooling
igniter-lab-evidence   docs/cards/proof archive
igniter-apps-fixtures  pressure apps/examples
```

If different names are better, propose them. Names are recommendations only.

### 8. How does this relate to package/workspace direction?

Keep this distinct from package-manager implementation.

Explain how repo-boundary cleanup interacts with the current direction:

- workspace/import ownership first;
- no registry/lockfile/install hooks yet;
- app-local packages later;
- projection dialects and IgWeb packaging later.

### 9. What should Gemini/Sonnet/Codex/Opus do?

Produce a parallelization plan that can use available agents without chaos:

- **Opus:** final synthesis, risk ranking, first split recommendation.
- **Gemini:** broad inventory shards. Good for directory census, stale/duplicate
  detection, path references. Must output one lab artifact only; no gov writes.
- **Sonnet:** reviewer/critic. Challenge split candidates and naming; look for
  hidden coupling and docs drift.
- **Codex:** live verifier. Run exact git/status/rg/cargo tree checks and, if
  later authorized, execute mechanical moves.

Do not ask every model to solve the same question in isolation. Shard by lens.

### 10. What are the next cards?

Propose at most three next cards. At least one must be a no-code cleanup card
and at most one may be a physical move card.

Examples:

- `LAB-IGNITER-LAB-REPO-BOUNDARY-CHECKPOINT-P2`
- `LAB-IGNITER-VIEW-ENGINE-DISPOSITION-P2`
- `LAB-IGNITER-WEB-REPO-SPLIT-P3`
- `LAB-IGNITER-LAB-GENERATED-OUTPUT-HYGIENE-P2`

## Deliverable

Write one packet:

```text
lab-docs/lang/lab-igniter-lab-repo-boundary-readiness-p1-v0.md
```

Recommended structure:

1. Executive summary.
2. Verified inventory table.
3. Domain map.
4. `igniter-view-engine` disposition.
5. Dependency/coupling map.
6. Split candidates and risk ranking.
7. Recommended first move.
8. What remains in `igniter-lab`.
9. Agent parallelization plan.
10. Next cards.

Then update this card with a closing report.

## Acceptance

- Live tree and git state were checked.
- Every top-level directory is classified.
- Every `Cargo.toml` package/path-dependency relevant to split is listed or
  explicitly scoped out.
- `igniter-view-engine` is investigated across all observed locations.
- Generated/output/noise directories are separated from architectural claims.
- The packet recommends a first split/cleanup move with risk reasoning.
- The packet states what must not move yet.
- Package-manager/workspace-import direction is related but not conflated.
- Agent-use guidance is concrete for Codex, Opus, Sonnet, and Gemini.
- No files are moved and no build/dependency topology is changed.

## Closing Report Template

Report:

- command evidence;
- inventory count by classification;
- domain map summary;
- `igniter-view-engine` conclusion;
- first recommended move;
- what not to move;
- agent parallelization recommendation;
- next cards.

---

## Closing report — 2026-06-19

**Deliverable:** `lab-docs/lang/lab-igniter-lab-repo-boundary-readiness-p1-v0.md` (10 sections). No files
moved; no Cargo/dependency topology changed; git clean (only this card untracked).

**Command evidence:** `git status --short` (1 untracked = this card); `find -maxdepth 1 -type d` (28 top
dirs); Cargo census (`grep name` over `*/Cargo.toml`) → 12 Rust crates, **no root workspace**; path-dep
extraction (`grep path=`); `du -sh` on the 3 view-engine locations; `find -name '*.rb'/*.ig/*.rs/*.kt`
file-type census of non-Rust dirs; `rg` for `../ln`/apps/view-engine coupling in tests; `igniter-ide`
Cargo at `src-tauri/`.

**Inventory by classification:** LIVE_CRATE 12 · LIVE_TOOL 2 (jetbrains-plugin, ide) · PROOF_FIXTURE ~6
(igniter-apps, view-engine, 3d-poc, gui-engine, research, tools/acts-as-tbackend) · DOC_EVIDENCE 2
(lab-docs 457 md, .agents 459 cards) · GENERATED_OUTPUT/STALE ~5 (compiler/igniter-view-engine 0B,
nested igniter-lab, igniter-site README-only, ../igniter-view-engine copy, .codex-local/.idea).

**Domain map:** language-core (compiler/vm/stdlib) → machine-runtime (machine/tbackend) → server-web
(server/web) + frame-ui (frame/ui-kit/console/3d/gui), all `../`-path-coupled with **no workspace root**;
ide-tools + apps-fixtures + lab-evidence + noise sit beside them.

**view-engine conclusion:** not three live forks — lab copy (11M) = historical JS fixtures (source of
`web_router`), superseded in name by frame-ui; `compiler/igniter-view-engine` (0B/out) = generated
delete-candidate; `../igniter-view-engine` (432K) = stale sibling archive-candidate. Disposition = a
dedicated no-code card; no deletion.

**First recommended move:** a **no-code cleanup pass** (view-engine disposition + generated/stale
hygiene), NOT a crate split. Structural enabler for later splits = a **Cargo workspace root** (additive).
Only low-risk physical extraction available = `igniter-jetbrains-plugin` (zero Cargo coupling), not urgent.

**What must not move yet:** the entire Rust constellation (every `../` path dep breaks on relocation
without a workspace root); machine↔apps (`../ln` test fixtures), machine↔frame-ui (dev E2E), server↔web
(dev cycle), web→compiler+machine; docs/cards (hardcoded-path sweep needed first).

**Agent plan:** Opus synthesis/risk/first-move (done) · Gemini census + stale/dup + path-ref shards (one
lab artifact, no gov) · Sonnet critic (hidden coupling/symlinks/docs drift) · Codex live verifier
(confirm `../ln` target + view-engine out/source split; mechanical moves only if later authorized).

**Next cards:** (1) `LAB-IGNITER-VIEW-ENGINE-DISPOSITION-P2` (no-code), (2)
`LAB-IGNITER-LAB-GENERATED-OUTPUT-HYGIENE-P2` (no-code), (3) `LAB-IGNITER-CARGO-WORKSPACE-ROOT-P3`
(at-most-one structural move — additive workspace root, no dir moves; precondition for crate splits +
host for the `.ig` import-ownership workspace).

**Acceptance:** all boxes met — live tree + git checked; every top dir classified; the 12 Cargo packages +
path-deps listed; view-engine investigated across all 3 locations; generated/noise separated from
architecture; first move + risk reasoning given; what-must-not-move stated; package/workspace direction
related but not conflated; concrete agent guidance; no files moved, no topology changed.

