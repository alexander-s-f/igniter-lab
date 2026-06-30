# LAB-IGNITER-MIRROR-CRATE-LINKING-READINESS-P1 — sibling-checkout linking policy for core mirrors

Lane: distribution / repository split / core DX
Status: DONE (readiness/design) — verified topology + tier table + v0 layout + named next cards; **no code, no Cargo.toml rewrites**
Date: 2026-06-30
Card: `igniter-lab/.agents/work/cards/lang/LAB-IGNITER-MIRROR-CRATE-LINKING-READINESS-P1.md`

Authority boundary: `igniter-lab` remains the source-of-truth workspace. The mirror repos are
**team-facing source mirrors**, not release packages. Nothing here promotes a mirror, rewrites a
`Cargo.toml`, or introduces registry/semver/release policy. Live repo state wins over this packet.

---

## 1. Verified dependency topology (live, 2026-06-30)

Read from each crate's `Cargo.toml`. "Prefix class" is what decides flat-plane resolution (§3).

| Crate (lab path) | Mirror remote | Non-registry deps | Prefix class |
| --- | --- | --- | --- |
| `lang/igniter-stdlib` (`igniter_stdlib` 0.1.7) | `Igniter/igniter-stdlib` | none (serde, serde_json; dev: regex) | — (leaf) |
| `lang/igniter-compiler` (`igniter_compiler` 0.1.0) | `Igniter/igniter-compiler` | none (serde, serde_json, blake3, sha2, regex) | — (leaf) |
| `lang/igniter-vm` (`igniter_vm` 0.1.0) | `Igniter/igniter-vm` | `igniter_stdlib = ../igniter-stdlib` | **same-parent sibling** |
| `runtime/igniter-machine` (`igniter_machine` 0.1.0) | `Igniter/igniter-machine` | `../../lang/igniter-compiler`, `../../lang/igniter-vm`, `../igniter-tbackend`; **dev:** `../../frame-ui/igniter-console`, `../../frame-ui/igniter-ui-kit` | **mixed: cross-dir + cross-layer dev** |
| `runtime/igniter-tbackend` (`igniter_tbackend_playground` 0.1.0) | `Igniter/igniter-tbackend` (remote `tbackend`) | none (serde, serde_json, rmp-serde, blake3, …; optional magnus under `ffi`) | — (leaf) |
| `runtime/acts-as-tbackend` | `afokin/acts-as-tbackend` | **Ruby gem, no `Cargo.toml`**; runtime refs `../igniter-tbackend`, `../igniter-vm` | n/a (Ruby; already sibling-relative) |

Notes verified:
- Package name vs repo name drift: `runtime/igniter-tbackend` builds the crate **`igniter_tbackend_playground`** (legacy compat symbol) and the binary **`tbackend`**; the mirror remote is named `tbackend` → `Igniter/igniter-tbackend`. Machine depends on it as `igniter_tbackend_playground = { path = "../igniter-tbackend", default-features = false }`.
- `acts-as-tbackend` is **not a Rust crate** — it is the ActiveRecord↔TBackend Ruby adapter (`lib/`, `demo.rb`, `verify_shadow.rb`). It carries no cargo edge; its README already references siblings `../igniter-tbackend` and `../igniter-vm`.
- Mirror push helpers (`bin/push-*-mirror`) use `git subtree split` → a **verbatim** subtree copy. They do **not** rewrite `Cargo.toml` path prefixes. So every mirror root carries the monorepo-relative paths above, unchanged.
- All Igniter mirror remotes resolve to `ssh://git@git.int.avenlance.com:222/...` (`git remote -v` confirmed: stdlib, compiler, vm, machine under `Igniter/`; tbackend under `Igniter/igniter-tbackend`; acts-as-tbackend under `afokin/`).

## 2. Tier classification

| Crate | Tier | Build expectation after clone |
| --- | --- | --- |
| `igniter-stdlib` | **Standalone crate repo** | `cargo test` works alone — no sibling required. |
| `igniter-compiler` | **Standalone crate repo** | `cargo test` works alone — no sibling required. |
| `igniter-tbackend` | **Standalone crate repo** | `cargo build`/`cargo test` work alone (default features; `ffi` opt-in). |
| `igniter-vm` | **Sibling-buildable core repo** | Needs `igniter-stdlib` as a flat sibling; then `cargo test` works (path `../igniter-stdlib` resolves natively — §3). |
| `igniter-machine` | **Source mirror (not yet flat-buildable)** | Cross-dir core deps + cross-layer **dev**-deps do not resolve in a flat plane as-shipped (§3). Needs the P2 link step. |
| `acts-as-tbackend` | **Source mirror (Ruby)** | Not a cargo build; its sibling refs (`../igniter-tbackend`, `../igniter-vm`) are already flat-correct. Runtime needs the tbackend daemon + vm binary present as siblings. |

Every mirror is at least a **Source mirror**. None is a **Release package** — that tier is future and governed elsewhere (§7).

## 3. How path deps resolve in a flat plane (the crux)

A subtree mirror keeps its declared path prefix verbatim. Whether that prefix resolves in a flat
`igniter-core/` plane depends only on the **relative shape** of the dep in the monorepo:

| Dep edge | Declared prefix | Monorepo shape | Flat-plane (`igniter-core/<crate>`) | Resolves flat? |
| --- | --- | --- | --- | --- |
| vm → stdlib | `../igniter-stdlib` | siblings under `lang/` | siblings under `igniter-core/` | **yes** — identical relative path |
| machine → tbackend | `../igniter-tbackend` | siblings under `runtime/` | siblings under `igniter-core/` | **yes** — identical relative path |
| machine → compiler | `../../lang/igniter-compiler` | crosses `runtime/`→`lang/` | `igniter-core/../lang/...` (no such dir) | **no** |
| machine → vm | `../../lang/igniter-vm` | crosses `runtime/`→`lang/` | (no such dir) | **no** |
| machine **dev** → frame-ui | `../../frame-ui/igniter-console`, `…/igniter-ui-kit` | crosses into `frame-ui/` (a non-core layer) | (no such dir, never in core) | **no** |

**Rule:** a path dep that is a *same-parent sibling* in the monorepo (`../<crate>`) "just works" in the
flat plane; a path dep that *crosses a monorepo subdirectory* (`../../lang/...`, `../../frame-ui/...`)
breaks. Only `igniter-machine` has crossing deps. Everything else is already flat-correct.

### Why a `.cargo/config.toml` `paths` override does NOT fix it (verified)

A natural first instinct — drop a flat-plane `.cargo/config.toml` with a `paths = [...]` override so deps
redirect to the flat siblings — was **empirically disproven** (isolated probe, throwaway crates):

```text
[dependencies] dep = { path = "../../nonexistent/dep" }   # declared path missing
paths = ["leaf"]                                          # override present

cargo build → error: failed to load source for dependency `dep`
              Caused by: failed to read .../nonexistent/dep/Cargo.toml
```

Cargo loads the **declared** path before any override applies, so a `paths` override cannot rescue a dep
whose declared directory is absent. The same load happens for a missing **dev**-dependency path — so
machine's `../../frame-ui/...` dev-deps would fail resolution even for `cargo build`, not just `cargo test`.

**Consequence:** machine cannot be made flat-buildable by an override file alone. Its crossing paths must
either be *materialized* (a `lang/` shim of symlinks inside the plane) or *normalized* (the mirror's
`Cargo.toml` rewritten to `../igniter-compiler` / `../igniter-vm`), and its **frame-ui dev-deps must be
reconciled** (feature-gate or relocate the one E2E test) because frame-ui is a non-core layer that will
never live in the core plane. This is the central linking task and is **P2/P3 implementation**, not this
readiness card.

## 4. v0 recommendation — flat sibling plane

**Adopt the flat sibling-checkout plane as v0.** Canonical root name: **`igniter-core`** (matches "core
sibling plane"; `igniter-dev` is too broad — it invites lab/experiments/product to creep in, which §6
forbids). Recommended location `~/dev/projects/igniter-core/` (sibling to `igniter-workspace/`), overridable.

```text
~/dev/projects/igniter-core/
  igniter-stdlib/      # standalone
  igniter-compiler/    # standalone
  igniter-vm/          # + ../igniter-stdlib   (resolves natively)
  igniter-tbackend/    # standalone
  igniter-machine/     # + ../igniter-tbackend (native); ../../lang/* and frame-ui dev-deps need P2/P3
  acts-as-tbackend/    # Ruby; ../igniter-tbackend + ../igniter-vm (native)
```

Why sibling-checkout over the alternatives, for v0:

- **vs git dependencies:** git deps pin to a moving branch/SHA → every cross-crate edit becomes a
  commit-push-bump churn cycle. Sibling path deps let you edit stdlib and immediately `cargo test` vm with
  zero publish step. The whole point of the core plane is tight local iteration.
- **vs an internal registry / crates.io / semver solver:** premature. No versioning story is needed to
  read, review, and co-develop core crates; a registry adds operational weight and a version-bump treadmill
  before there is any external consumer.
- **vs `[patch]` / virtual workspace:** `[patch]` is for redirecting *registry/git* deps and adds an
  always-on indirection; a virtual workspace would still carry the members' crossing path prefixes
  unchanged (it does not rewrite them). Both are heavier than needed and the card explicitly defers
  `[patch]` complexity. Four of six mirrors need **nothing** beyond being cloned as flat siblings.

**Answer to Q5 (sibling-relative vs generated override):** keep mirror `Cargo.toml` files **verbatim**
(no per-crate rewrite, mirrors stay faithful subtree copies). The only crate that cannot resolve flat is
`igniter-machine`; resolve it with a **generated, deterministic** P2 artifact (symlink shim or a generated
flat overlay `Cargo.toml`), never a hand-maintained divergence — and treat the frame-ui dev-deps as a
layering fix (P3), not a path trick.

## 5. Local-development ergonomics (Q7)

In the flat plane, with the P2 link step for machine:

- *edit stdlib → test vm*: `cd igniter-core/igniter-vm && cargo test` — picks up `../igniter-stdlib` live.
- *edit compiler/vm → test machine*: works once P2 materializes the crossing paths; the frame-ui E2E test
  stays in the lab workspace until P3.
- *no remote-commit churn*: all edges are local path deps; nothing requires a push to be consumed.

## 6. Explicitly outside the core plane

The core plane is the six crates above **only**. These remain derivative layers and must not be folded in
(keeping core ≠ lab is a hard boundary):

- `igniter-lab` workspace itself (source-of-truth; superset build).
- `frame-ui/*` (console, ui-kit, render-html, frame) — a UI layer; machine only **dev**-depends on two of
  them for one E2E proof, which is exactly the cross-layer edge P3 must reconcile.
- experiments, `igniter-emergence` (public science), `igniter-home-lab`, product/app-specific work, demos.

## 7. Explicitly NOT v0

crates.io · internal Cargo registry · semver solver · git deps pinned to moving branches · `[patch]`
policy · published binary/release packages. The release tier is a **later layer**: a future
`LAB-IGNITER-MIRROR-RELEASE-PACKAGING-Px` governs versioning + artifacts once an external consumer exists.

## 8. First implementation card (Q8)

**`LAB-IGNITER-MIRROR-CORE-CHECKOUT-HELPER-P2`** — a small monorepo-owner helper (no dependency-policy
change) that:

1. creates/verifies the flat `igniter-core/` plane and clones any missing core mirror (remotes from §1);
2. prints each repo's remote + HEAD;
3. materializes machine's crossing core deps for the flat plane — **evaluate symlink-shim
   (`igniter-core/lang/{igniter-compiler,igniter-vm} -> ../<crate>`) vs a generated flat overlay**, and
   pick the one that needs no edit to a committed mirror `Cargo.toml` (the §3 probe shows an override file
   alone is insufficient);
4. runs a **bounded check matrix**: leaf checks (`stdlib`, `compiler`, `tbackend` build alone), the
   sibling check (`vm` with `stdlib`), and machine's **lib/build** check (excluding the frame-ui E2E test).

Then **`LAB-IGNITER-MIRROR-MACHINE-DEVDEP-RECONCILE-P3`** — reconcile machine's `frame-ui` dev-deps
(feature-gate the `frame_binding_console_e2e` test behind an off-by-default feature, or relocate it to the
lab workspace) so `igniter-machine` becomes fully flat-core-buildable without pulling a non-core layer.

## 9. README wording for mirrors (Q9)

Each mirror README should carry a short status banner so a team member never mistakes a source mirror for
an independent release package. `igniter-tbackend` already has mirror/preview wording and `acts-as-tbackend`
has an explicit status ladder; `igniter-stdlib`, `igniter-compiler`, `igniter-vm`, `igniter-machine` have
lab/not-production wording but **no mirror/preview note** — add one (wording only; a later doc card, not here):

> **Status: team-facing source mirror of an `igniter-lab` subtree — not an independent release package.**
> Source-of-truth is the `igniter-lab` monorepo. For local work, clone into the flat `igniter-core/` plane
> (see `LAB-IGNITER-MIRROR-CORE-CHECKOUT-HELPER-P2`). `igniter-vm` needs sibling `igniter-stdlib`;
> `igniter-machine` needs the P2 link step. No crates.io / registry / semver guarantee.

## 10. Acceptance trace

- Packet under `lab-docs/lang/` ✓ · verifies live `Cargo.toml` topology (§1) ✓ · classifies every mirror
  source-mirror / sibling-buildable / standalone (§2) ✓ · recommends sibling-checkout v0 with the reasons
  it beats git-deps/registry/`[patch]` (§4) ✓ · defines the canonical flat layout + name (§4) ✓ · states
  what's outside core (§6) ✓ · names the first implementation card and a follow-on (§8) ✓ · README wording
  (§9) ✓ · no code, no `Cargo.toml` rewrites, no registry/semver/release claim ✓.

## 11. Honest limitations / what changed vs the card's prior

- The card's hint that mirrors might just stay "sibling-relative" holds for 4 of 6 crates and for vm's edge,
  but **not** for `igniter-machine`: its `../../lang/*` (cross-dir) and `../../frame-ui/*` (cross-layer dev)
  edges break in a flat plane, and a `.cargo/config.toml` `paths` override does **not** rescue a missing
  declared path (§3, verified). So machine is the one crate needing real link work — surfaced here, owned by
  P2/P3. This is product-of-record planning for a lab repo split; no production/deploy claim.

## 12. Variant A — flatten core to root (recommended structural follow-up)

§3 showed the *only* reason `igniter-machine` breaks flat is that the monorepo groups crates into `lang/` /
`runtime/` subdirs, so machine→compiler is written `../../lang/igniter-compiler` (cross-dir). A path dep is
flat-safe **iff** the two crates share a parent in the monorepo. So the most direct fix is not a per-crate
link trick (§3/§8) but **making the core crates share a parent in the monorepo itself**: move the five core
Rust crates to the repo root.

```text
igniter-lab/
  igniter-stdlib/  igniter-compiler/  igniter-vm/  igniter-machine/  igniter-tbackend/   # core, flat = the mirror plane
  frame-ui/   server/   ide/   lab-docs/                                                  # derivative layers, stay grouped
```

This keeps the monorepo as source-of-truth (atomic cross-crate commits, whole-graph CI) **and** makes the
mirror plane resolve natively: after the move every core→core edge is `../<crate>`, identical in the
monorepo and in `igniter-core/`. **It does not change mirroring** — each crate still ships via
`git subtree split`; only the helper `PREFIX` changes (e.g. `lang/igniter-vm` → `igniter-vm`). Mirrors stay
verbatim subtree copies and become flat-buildable with **no shim, no overlay, no `paths` override**.

### Measured cost (full graph, 15 crates, verified 2026-06-30)

Path-dep edges that change when the five core crates move to root:

| Edge | Before → after | Why |
| --- | --- | --- |
| `machine → compiler` | `../../lang/igniter-compiler` → `../igniter-compiler` | core→core, now flat-resolvable |
| `machine → vm` | `../../lang/igniter-vm` → `../igniter-vm` | core→core, now flat-resolvable |
| `machine → tbackend` | `../igniter-tbackend` (unchanged) | already same-parent |
| `vm → stdlib` | `../igniter-stdlib` (unchanged) | already same-parent |
| `ide/src-tauri → machine, compiler, vm` | `../../../{runtime,lang}/X` → `../../../X` (×3) | non-core→core, prefix only |
| `server/igniter-web → compiler, machine` | `../../{lang,runtime}/X` → `../../X` (×2) | non-core→core, prefix only |
| `server/igniter-server → machine` | `../../runtime/igniter-machine` → `../../igniter-machine` | non-core→core, prefix only |
| `frame-ui/igniter-frame → machine` | `../../runtime/igniter-machine` → `../../igniter-machine` | non-core→core, prefix only |
| `machine **dev** → frame-ui/{console,ui-kit}` | `../../frame-ui/X` → `../frame-ui/X` (×2) | prefix simplifies; the cross-layer dep itself remains (still P3) |

Unaffected: all frame-ui-internal edges (`console/gui/3d/ui-kit → ../igniter-frame`), `server/igniter-web ↔
server/igniter-server`, and `web → ../../frame-ui/igniter-render-html` (both ends stay grouped).

Totals: **11 path-dep lines** across **5 `Cargo.toml`** (machine, ide-src-tauri, web, server, frame) ·
**5 `git mv`** (the `lang/` and `runtime/` dirs disappear) · **5 push-helper `PREFIX` edits** · zero logic
changes.

### What Variant A does and does not settle

- **Settles:** the entire §3 core path-resolution problem. `igniter-machine`'s `../../lang/*` edges become
  `../*`; the helper (§8) collapses to clone-plus-check with **no** link step. There is no longer a
  "machine is special" caveat for cargo path resolution.
- **Does not settle:** machine's **frame-ui dev-deps**. Flattening only shortens their prefix
  (`../../frame-ui/*` → `../frame-ui/*`); frame-ui is still a non-core layer absent from the core plane, so
  the `frame_binding_console_e2e` dev-dep still blocks a pure-core `cargo test`. **P3 stands unchanged**
  (feature-gate or relocate that one E2E test).

### Recommendation & boundary

Variant A is the recommended structural follow-up: small (11 lines + 5 moves + 5 prefixes), pure
relocation, and it eliminates the P2 link machinery rather than implementing it. But its blast radius is
**graph-wide** (5 dependent crates rebuild; directories move), so it is a deliberate one-time migration that
belongs in its **own implementation card with full `cargo build`/`cargo test` verification across all 15
crates** — not under this closed readiness card and not as an incidental edit. It supersedes the link-step
scope of the prior §8 `…-CHECKOUT-HELPER-P2`:

- **`LAB-IGNITER-MONOREPO-FLATTEN-CORE-P2`** — `git mv` the five core crates to root, apply the 11 path-dep
  edits + 5 helper-prefix edits above, rebuild/test the whole graph, confirm each mirror still
  `subtree split`s and now builds flat. After it lands, the checkout helper is trivial (clone + check) and
  `igniter-machine` joins the flat core plane modulo the P3 dev-dep reconcile.

This stays within the card's authority otherwise: still no registry/semver/release policy, igniter-lab
remains source-of-truth, core stays distinct from lab/derivative layers.
