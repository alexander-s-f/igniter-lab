# LAB-IGNITER-COMMAND-CENTER-AUTONOMY-READINESS-P1 — `igniter` as autonomous command center (Dev / DX / DevOps)

Lane: distribution / command center / autonomy
Status: DONE (readiness/architecture) — decision + taxonomy + named next wave; **no code, no repo merge, no Cargo.toml rewrites**
Date: 2026-07-01
Card: `.agents/work/cards/lang/LAB-IGNITER-COMMAND-CENTER-AUTONOMY-READINESS-P1.md`
Builds on: `lab-igniter-mirror-crate-linking-readiness-p1-v0.md` (P1) + monorepo flatten (P2) + machine devdep reconcile (P3);
prior distribution wave P6/P7/P8/P10/P14/P27/P31 (all CLOSED).

Authority boundary: `igniter-lab` stays source-of-truth; mirrors stay team-facing source mirrors. This packet
decides architecture only — it grants no authority, moves no authority, and merges no repos.

---

## 1. Executive decision

**Do not merge the core crates into one `igniter`/`igniter-core` code blob. Keep granular ownership and
promote `igniter` into the durable command center — and close the one real remaining gap by adding an
`igniter workspace …` Dev lane.** The DX and DevOps lanes are already substantially built in `bin/igniter`
(shell) and verified live; the Dev lane (contributor workflow over the flattened core + mirrors) is the only
axis with no front-door command today — its knowledge is scattered across six `bin/push-*-mirror` helpers.

The hypothesis from curation ("keep granular, promote `igniter` to command center") **survives contact with
live code.** P2/P3 already made a granular core-only checkout cleanly buildable, so the granular-repo tax the
card worried about ("users must remember the whole dependency graph") is a *tooling* gap, not a *structural*
one — exactly what a supervisor command solves without a merge.

## 2. Live surface verified (2026-07-01)

- **`bin/igniter`** (1183 lines, shell) — front door with verbs: `serve`, `check`, `doctor`, `toolchain
  {list,install,update}`, `package …` (argv-routes to `igc`), `app {bundle,admit}`, `agent` (MCP), `env
  {doctor,template,check}`, `stdlib {list,search,show}`, `explain`. **No `workspace` verb.** Flatten-correct
  (no stale `lang/`/`runtime/` paths). `LANG_SIBLING="$REPO_ROOT/../igniter-lang"`.
- **`doctor --json`** already emits a clean structured array — records `{scope, check, severity, detail,
  suggest}` — across `env` (mode/rustc/cargo/igniter-lang-sibling/PATH/manifest), `toolchain` (the 5-binary
  fleet + optional repl), and `app` scopes. Distinguishes **source-checkout vs installed-prefix** mode. This
  is a live seed of the machine-readable contract.
- **`bin/igniter-install`** (167 lines) — bootstrap-only; builds the **5-binary fleet** (`igc`←igniter-compiler,
  `igniter-vm`, `igweb-serve`←server/igniter-web, `igniter-mcp`←igniter-machine, `tbackend`←igniter-tbackend)
  package-locally, stages them + the front door, writes `igniter-manifest.json` (provenance, `public_release:
  false`), runs a no-network/no-DB smoke. Flatten-correct paths. Requires the canon `igniter-lang` inventory.
- **`agent` (MCP)** — a local stdio MCP surface exposing **8 safe, non-mutating tools** (`doctor`,
  `toolchain_list`, `check_app`, `package_verify`, `app_bundle`, `env_doctor`, `env_check`,
  `serve_app_bounded`), each delegating to the same front door → grants nothing new.
- **Mirrors** — 5 core remotes under `Igniter/*` (+ `afokin/acts-as-tbackend`) on
  `git.int.avenlance.com:222`; pushed via 6 `bin/push-*-mirror` `git subtree split` helpers (flatten-correct
  `PREFIX`es after P2).
- **Prior wave (all CLOSED):** P6 (`igniter` = shell dispatcher), P7 (control-center CLI skeleton, 9 tests),
  P8 (bootstrap install, 10 tests), P10 (full doctor text+json, 22 tests), P14 (`app bundle`), P31 (deploy
  ladder → next rung `igniter app release` local-symlink, no service control), P27/P28 (agent MCP structured
  responses = **shape C**: human text + a second JSON-envelope content item).

### Curation facts — re-verified live (one drifted)

1. **Fresh mirror checkout = `igniter-lang` canon sibling + the 5 core mirrors.** CONFIRMED. Strict probe
   (renamed BOTH `frame-ui/` AND `apps/` away, then `cd igniter-machine && cargo test --no-default-features`)
   → **366 passed, 1 failed** where the 1 is the known-flaky `wire_atomic_gate_tests::
   plain_run_write_effect_doubles_under_forced_interleave` (3/3 green rerun in isolation), not a missing
   sibling. So machine builds+tests with only core siblings present; `igc` additionally needs `igniter-lang`.
2. **Machine tests are mirror-local for fleet fixtures.** CONFIRMED (this corrects a stale note that still
   pointed at a root `apps/igniter-apps`): live `machine_tests.rs` reads
   `CARGO_MANIFEST_DIR/tests/fixtures/fleet_apps/…`, and `igniter-machine/tests/fixtures/` holds
   `fleet_apps/`, `storage_capability/`, `tls/` — all in-crate. The strict probe (apps/ removed) still passed
   the fleet sweep.
3. **`igniter-compiler` compile-time reads canon `igniter-lang/docs/spec/stdlib-inventory.json`.** CONFIRMED
   (`include_str!("../../../igniter-lang/…")` in `stdlib_surface.rs` + `multifile.rs`, and `LANG_INVENTORY` in
   both `bin/igniter` and `bin/igniter-install`). This is the ONE hard cross-repo edge: canon is a build input.

## 3. Three-axis requirements

| Axis | User | Success path | Command-center responsibility | Owner authority (unchanged) |
| --- | --- | --- | --- | --- |
| **Dev** | Igniter contributor | clone/sync/build/test the flat core + verify mirrors | `igniter workspace status\|sync\|build\|test\|doctor` — checkout layout, mirror remotes/heads, branch drift, dependency-graph + bounded core test matrix | each crate owns its own `cargo build`/`test`; git owns remotes |
| **DX** | app author | install toolchain, doctor, check/serve/package an app, read stdlib docs | `toolchain {install,update,list}` + `app` front door + `stdlib`/`explain` argv-routing | `igweb-serve` owns loopback/public-bind/bound; `igc` owns lock/verify/admit + `STDLIB_VERSION` |
| **DevOps** | operator | bundle → admit → env check → hand to systemd/Docker/AWS | `app {bundle,admit}` (assembly + provenance), `env {doctor,template,check}` (names only), `doctor --json` for CI/MCP, (later) `app release` | host owns secrets/DSN/TLS/public bind/systemd/Docker/AWS; bundler refuses inline secrets |

Live status per axis: **Dev = missing front door** (only scattered mirror helpers); **DX = built** (P6–P10,
P14); **DevOps = built through admit/env, deploy is a named ladder** (P31 → `app release` next, service
control stays host-owned).

## 4. Options compared

| Option | What it is | Verdict |
| --- | --- | --- |
| **A. Full repo merge** (`igniter-core` = one crate/workspace) | collapse the 5 core crates into one repo/workspace | **Reject.** Destroys the review/onboarding win of granular mirrors (P1) and the proven subtree-mirror workflow; re-introduces a monorepo-inside-a-mirror; contradicts the standing "granular ownership" constraint. The only merge upside (one clone) is delivered by `igniter workspace sync` without the downside. |
| **B. Granular repos + `igniter` command center** (add `workspace`) | keep `igniter-lab` source-of-truth + mirrors; `igniter` learns the Dev lane | **Recommend.** Smallest delta over live reality: DX/DevOps already live; add the missing Dev lane as orchestration-only. No authority moves. |
| **C. Separate `igniter-toolchain`/orchestration repo** | a distinct supervisor repo/tool | **Reject for v0.** Splits the front door from the checkout it supervises; a second thing to install/version before there is any external pressure for it. The command center already lives correctly next to the source (`bin/igniter`). |
| **D. Hybrid** (B now, extract C later) | ship `workspace` in `bin/igniter`; keep the door open to extract a standalone supervisor/binary once a Rust CLI exists | **Adopt as the trajectory.** B is the v0; the Rust-CLI readiness card (§10) is the pivot that could later justify a standalone distributable — decided by evidence, not now. |

## 5. Recommended architecture

**Option B, on the Hybrid (D) trajectory.** One front door, three lanes, zero authority in the center:

```text
                         igniter   (durable command center — orchestrate + report ONLY)
        ┌───────────────────┼────────────────────────┬───────────────────────────┐
   workspace (Dev, NEW)   toolchain + app + stdlib (DX)          app + env + doctor --json (DevOps)
   status/sync/build/       install/update/list · check/serve      bundle/admit · env {doctor,template,
   test/doctor over the     · package→igc · stdlib→igc             check} · (later) app release
   flat core + mirrors
        │                          │                                        │
   git remotes +              igweb-serve (bind/bound)                 bundler (no inline secrets) +
   cargo per-crate            igc (lock/verify/admit/STDLIB_VERSION)   host (secrets/TLS/systemd/Docker/AWS)
        └──────────────────────────┴────────────────────────────────────────┘
                         canon input: igniter-lang (compile-time stdlib-inventory)
```

Invariant: **the center shells to named owners and grants nothing.** `workspace` is read-mostly orchestration
(git + cargo), never a new authority; it must not become a second package manager (that's `igc`) or a second
deploy system (that's host + the P31 ladder).

## 6. Proposed command taxonomy

| Group | v0 (now) | Later | Explicitly NOT here |
| --- | --- | --- | --- |
| `igniter workspace` (**NEW**, Dev) | `status` (mirror remotes/heads, flat-core layout, `igniter-lang` sibling, branch drift — read-only), `doctor` (Dev-mode env: git, siblings, dirty tree), `build`, `test` (bounded core matrix over the 5 crates) | `sync` (clone/update missing core mirrors into the plane — write-ish, gated), `graph` (dep-graph check) | pushing mirrors (stays `bin/push-*-mirror`), registry/semver |
| `igniter toolchain` (DX) | `install` (→ `igniter-install` bootstrap), `update`, `list` | downloadable standalone `igniter` binary channel | building apps (that's `check`/`serve`) |
| `igniter app` (DevOps) | `bundle`, `admit` | `release` (local symlink, no service control — P31/P32) | systemd/Docker/AWS, public bind, secrets |
| `igniter env` (DevOps) | `doctor`, `template`, `check` (names only, values never printed) | — | reading/injecting `.env`, secret values |
| `igniter {serve,check,package,stdlib,explain,agent,doctor}` | as today | `doctor --json` extended to `workspace` scope | — |

## 7. Bootstrap / update lifecycle — role of `igniter-install`

**Keep `bin/igniter-install` as the bootstrap-only source-checkout installer; do NOT subsume it into
`igniter toolchain install` and do NOT replace it yet.** Verified live: `toolchain install` already delegates
INTO `igniter-install`, and `igniter-install` stages the front door so daily work becomes `igniter …`. The
clean lifecycle is:

```text
git checkout igniter-lab (+ igniter-lang sibling)   →   bin/igniter-install [--prefix ~/.igniter]   (bootstrap ONCE)
      →   export PATH=~/.igniter/bin:$PATH   →   igniter doctor   →   igniter toolchain update   (ongoing)
```

- **Bootstrap-only** because chicken-and-egg: you cannot run `igniter toolchain install` before `igniter`
  exists on PATH. `igniter-install` is the one script that must stand alone.
- A **downloadable standalone `igniter` binary** (skip the source build) is a *later* channel — it depends on
  the Rust-CLI decision (§10) and a release/signing story this card excludes.
- Dev contributors keep the **source-checkout fallback** (run from `bin/igniter` in-tree, no install).

## 8. JSON / MCP / CI contract

A machine-readable contract already exists and should be **unified, not reinvented**:

- **Doctor record shape** (live): array of `{scope, check, severity∈{ok,warn,fail,info}, detail, suggest}`.
  Adopt this as the canonical **diagnostic record** and extend it to a `workspace` scope (mirror/head/drift
  checks) so `igniter workspace doctor --json` and `igniter doctor --json` share one schema.
- **Agent MCP** (P27/P28, live): **shape C** — human-readable text PLUS a second JSON-envelope content item.
  New `workspace` tools (e.g. `workspace_status`) must follow shape C, not invent a third convention.
- **Exit-code + error contract:** keep the existing convention (0 report / 2 usage / non-zero gate for `env
  check`); a future card should enumerate structured error codes once `workspace` adds failure modes.
- CI/agents consume `--json`; they must never parse human text. This is also the **strongest signal for the
  Rust-CLI pivot** (§10): `bin/igniter` currently hand-rolls JSON (`json_escape`, `doc_emit`) and greps JSON
  with `grep -oE` — fragile as the structured surface grows.

## 9. Authority boundaries & non-goals

Owners (unchanged, must stay put): `igweb-serve` = loopback/public-bind/request-bound; `igc` = package
lock/verify/admit + STDLIB_VERSION + canon/stdlib provenance; `igniter-machine` = host capability execution +
receipts; **host/operator** = secrets, DSNs, TLS, public exposure, systemd/Docker/AWS. `igniter` orchestrates
and reports; it never mints a passport, opens a public listener, reads a secret value, or resolves a package.

**Non-goals (this card and the v0 `workspace` lane):**
- No repo merge; no `igniter-core` code blob.
- No registry / semver / signing / download channel.
- No second package manager (resolution stays in `igc`) and no second deploy system (service control stays
  host-owned; the deploy ladder is P31/P32).
- `workspace sync` must not push mirrors or rewrite crate `Cargo.toml`; pushing stays in `bin/push-*-mirror`.
- No secret/DSN/`.env` value ever printed or injected by the center.
- Do not break the current in-tree `bin/igniter` / source-checkout workflow.

## 10. Next implementation wave

Shell is **acceptable for the immediate `workspace` addition** (keep the proven front door + its ~22 wrapper
tests; the Dev lane is git + cargo orchestration that shell does well). But `bin/igniter` has crossed the
threshold **for structured output specifically** — so the Rust-CLI question is opened in parallel, evidence-
gated, not blocking. Smallest-value-first order:

1. **`LAB-IGNITER-WORKSPACE-STATUS-DOCTOR-P2`** — implement `igniter workspace status` + `workspace doctor`
   (READ-ONLY: mirror remotes/heads, flat-core layout, `igniter-lang` sibling presence, dirty/branch drift),
   text + `--json` reusing the doctor record shape. Highest value, zero authority, no mutation.
2. **`LAB-IGNITER-WORKSPACE-BUILD-TEST-MATRIX-P3`** — `igniter workspace build|test`: codify the bounded core
   test matrix proven in P2/P3 (the 5 crates, machine `--no-default-features` pure-core lane, flag the known
   flaky). Optionally `workspace sync` (gated clone/update) if evidence supports.
3. **`LAB-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P4`** — unify + specify the machine-readable contract: the
   diagnostic record schema (incl. the new `workspace` scope), shape-C MCP envelopes, and structured
   exit/error codes; a conformance check so agents/CI never parse text.
4. **`LAB-IGNITER-COMMAND-CENTER-RUST-CLI-READINESS-P5`** — evaluate porting `bin/igniter` to a Rust CLI,
   triggered by the hand-rolled-JSON fragility (§8) and surface growth; decide the standalone-binary channel
   (§7) and whether Hybrid (D) extracts a supervisor. Readiness only — NOT a rewrite mandate.

Suggested sequence: **P2 → P3 → P4 → P5** (P4 can start once P2 lands the first `workspace` records; P5 is
independent and can run any time after P4 surfaces the JSON pressure concretely).

---

**Acceptance trace:** packet under `lab-docs/lang/` ✓; verifies live `bin/igniter` + `bin/igniter-install`
(§2) ✓; compares merge vs command-center (§4) ✓; all three axes (§3) ✓; recommended architecture (§5) ✓;
commands under `workspace`/`toolchain`/`app`/`deploy` (§6) ✓; `igniter-install` v0 role (§7) ✓; shell-vs-Rust
decided (shell for `workspace` v0; Rust-CLI readiness card named — §10) ✓; machine-readable expectations (§8)
✓; explicit non-goals (§9) ✓; 4 next cards with order (§10) ✓; no code, no repo merge, no `Cargo.toml`
rewrites.

**Live-truth corrections vs the card's priors:** curation fact #2 was stated as still pointing at a root
`apps/igniter-apps`; live code has already moved fleet fixtures in-crate to
`igniter-machine/tests/fixtures/fleet_apps/` — verified and folded into §2. No other drift found.
