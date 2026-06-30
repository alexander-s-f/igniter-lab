# LAB-IGNITER-COMPILER-LOCK-DEFAULT-POLICY-READINESS-P4

Date: 2026-06-28
Status: DONE (readiness/policy — no default flipped)
Lane: igniter-lab / compiler / package trust policy
Skill: idd-agent-protocol
Card: `.agents/work/cards/lang/LAB-IGNITER-COMPILER-LOCK-DEFAULT-POLICY-READINESS-P4.md`
Decides: audit-control-board row **A12** follow-up (the "default policy" half).
Depends-On: `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`, `LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P3`.

## Authority Boundary

This is a **readiness/policy** packet. It decides the default-policy question and does **not**
change compiler behavior, CLI defaults, `.ig` semantics, or any committed fixture. No
registry / semver / signing / remote-source / solver work. Live source wins; the current
behavior below is verified by live CLI tests and a tempdir smoke transcript, not by recall.

## Current Behavior (verified)

### CLI surface (`lang/igniter-compiler/src/main.rs`)

- `compile --project-root ROOT --entry M --out O [--locked|--frozen] [--overlay a=b ...]`
  — project mode. The lock gate runs **only** when `--locked` (or its CI alias `--frozen`)
  is present: `let locked = args.iter().any(|a| a == "--locked" || a == "--frozen")`
  (`main.rs:478`); `if locked { enforce_project_lock(root)? }` runs **before** entry
  resolution and emit (`main.rs:506`).
- Positional / single-file compile has **no lock concept** at all (unchanged).
- `igc lock [--project-root ROOT] [--frozen]` — write a deterministic `igniter.lock`
  (idempotent); `--frozen` is the CI check mode (never writes; `reason: up-to-date |
  missing | out-of-date`).
- `igc verify [--project-root ROOT] [--strict]` — drift report; `--strict` adds workspace
  assembly integrity (OOF-IMP*).
- No environment variable gates locking. (`IGNITER_*` env vars are liveness budgets, unrelated.)

### Default = unlocked project compile

`enforce_project_lock` (`main.rs:556`) is reached only under `--locked`. Without the flag a
project compile proceeds even with **no** `igniter.lock`. Proven by:

- live test `cli_compile_without_locked_allows_missing_lock`
  (`package_lockfile_cli_tests.rs:432`) — `status: ok`, `.igapp` written, no lock present;
- tempdir smoke transcript (below).

### Smoke transcript (tempdir copy of the `workspace` fixture, committed tree untouched)

```text
(1) DEFAULT  compile, no lock present   → status: ok   | diagnostics: 0   | out written: YES
(2) --locked compile, no lock present   → status: oof  | rule: OOF-LOCK-MISSING | out written: no
(3) igc lock; --locked compile          → status: ok   | out written: YES
```

### Lock-gate diagnostics (Q5)

Under `--locked`, `enforce_project_lock` fails closed before emit with a structured
`compiler_result { status:"oof" }` carrying one `project_lock` diagnostic:

| Condition | Rule | Notes |
|---|---|---|
| no `igniter.lock` | `OOF-LOCK-MISSING` | message names the `igc lock …` fix. |
| unparseable lock | `OOF-LOCK-MALFORMED` | |
| stale lock (content/manifest/toolchain drift) | `OOF-LOCK-DRIFT` | `details.drift[]` = `{kind:changed|added|removed|toolchain, name, …}`. |
| verify I/O error | `OOF-LOCK-IO` | |
| workspace integrity fault | `OOF-IMP4/6/7/8` (or `OOF-LOCK-INTEGRITY` on I/O) | reuses `check_workspace_integrity` — same gate as `verify --strict`. |
| explicit unlocked mode | *(none)* | compile proceeds silently; absence of `--locked` **is** the unlocked mode. |

Containment (P3): local dependency paths are confined to the workspace trust root
(absolute / lexical `..` / symlink escapes refused, `OOF-IMP10`), so the lock digests a
bounded, non-escaping source set. This is what makes a future default-on *meaningful* rather
than merely strict.

## Blast Radius if Default-On Were Flipped Today (Q6)

- **Zero committed `igniter.lock` exist anywhere in the repo** (`find . -name igniter.lock`
  outside `target/` → none). Every test mints its lock in a tempdir first.
- All **26** `tests/fixtures/project_mode/*` trees ship without a lock → default-on ⇒
  `OOF-LOCK-MISSING` for each project-mode compile, and the regression test
  `cli_compile_without_locked_allows_missing_lock` would invert.
- **No `apps/`, `examples/`, or `xtask/` script/doc currently invokes project-mode compile
  or `--locked`** (grep clean). The consuming surface that would benefit from default-on does
  not exist yet; the dev inner loop (`compile` between edits without re-locking) would be the
  party most disrupted.

## Policy Alternatives Compared

| # | Policy | Pros | Cons / cost |
|---|---|---|---|
| **A** | **Default-on** for all project compiles + `--no-lock` escape hatch. | Supply-chain-safe by default; matches Cargo's `--locked`-in-CI intuition inverted to default. | Breaks all 26 lockless fixtures + every lockless project build; needs a new escape-hatch flag and re-locking everywhere; **premature** — the threat it guards (remote/registry tampering) does not exist in the LOCAL-only package model. Large, not tiny-safe. |
| **B** | **Warning-only default**: lockless project compile emits a non-fatal warning, still compiles; `--locked` stays the hard gate. | Zero breakage; nudges toward locking; reversible. | Warnings are ignorable; adds a warning surface to plumb and test; ambiguous "is this enforced?" signal. |
| **C** | **Keep explicit `--locked` (status quo)** + document the CI/operator recipe; defer default-on. | Zero risk; matches LOCAL-v0 maturity; the hard gate + `lock --frozen` already deliver protection for opt-in users; honors "observe before switching authority". | Safety is opt-in; relies on CI discipline to actually run the gate. |
| **D** | **Auto-enforce iff a lock is present** ("if you locked, stay locked") + `--no-lock`. | No breakage for never-locked projects; auto-protects locked ones without a flag. | Silent behavior change: a locked project's dev inner loop fails on an intentionally-stale lock; a deleted lock silently downgrades; still needs an escape hatch + new tests. A real authority change — not trivially safe. |

## Recommendation

**Adopt C — keep the explicit `--locked` gate for now; do not flip the default in this card.**

Reasoning:
- The card forbids flipping the default unless it is *tiny and safe*. It is neither: A and D
  both require a new escape-hatch flag, re-locking 26 fixtures, and new tests, and both change
  authority (what a bare `compile` means). That fails the "tiny safe implementation" bar.
- The protection default-on buys is against **untrusted/remote** sources. The package model
  is **LOCAL feature-complete v0** with **no registry / remote / semver / signing** yet, so
  default-on would impose cost without a live threat. Enforcement should arrive *with* the
  trust surface it protects, not before it.
- The opt-in stack already delivers the guarantee for anyone who wants it today:
  `compile --locked` (build gate, fail-closed before emit) + `igc lock --frozen` (CI lock
  freshness) + `igc verify --strict` (drift + integrity). Nothing is missing for a security-
  conscious operator; only the *default* is conservative.

No code, CLI, fixture, or test change is made by this card.

## CI / Dev / Operator Consequences (named)

- **CI (recommended recipe, available today):** run `igc lock --frozen --project-root ROOT`
  (fails if the committed lock is missing/stale, never rewrites) and build with
  `igc compile --project-root ROOT --locked …` (fails closed on missing/stale/integrity
  before emit). Optionally `igc verify --strict` for integrity-only gating.
- **Dev inner loop:** unaffected — bare `compile` stays fast and lockless; developers opt into
  `--locked` when they want reproducibility.
- **Operator / release:** `package admit --require-lock --match-toolchain` already enforces
  lock presence + toolchain match at node admission (P23); release flows should lean on that
  plus `--locked` builds rather than a global compiler default.

## Exact Next Card (when the trust surface lands)

`LAB-IGNITER-COMPILER-LOCK-DEFAULT-ENFORCE-P5` — flip project-compile lock policy once a
non-local trust surface exists (registry / remote source / signing). Scope to evaluate:

- choose between **A** (hard default-on) and **D** (auto-enforce-when-present) as the default;
- add the `--no-lock` escape hatch (dev opt-out) with a clear single name;
- re-lock the project-mode fixtures (or teach the harness to mint+commit a lock) and update
  `cli_compile_without_locked_allows_missing_lock` to the new contract;
- gate landing on the remote/registry readiness card so enforcement ships with its threat.

Trigger condition: a registry / remote-source / signing readiness card is opened
(currently out of scope — see A12 "Remaining").

## Questions Answered

1. **Current default project compile?** Unlocked — the lock gate runs only under
   `--locked`/`--frozen`; single-file compile has no lock at all.
2. **Should project compile require a lock by default?** Not now — recommend C; defer to P5
   with the registry/remote trust surface.
3. **Local-dev escape hatch?** None exists today *because* there is no default enforcement
   (no `--locked` = unlocked). A future default-on would add `--no-lock`.
4. **Interaction with `igc lock --frozen` and CI?** Composes: `lock --frozen` (freshness
   check, no write) + `compile --locked` (build gate) + `verify --strict` (integrity). This
   is the recommended CI recipe today.
5. **Diagnostics distinguishing the cases?** `OOF-LOCK-MISSING` / `OOF-LOCK-MALFORMED` /
   `OOF-LOCK-DRIFT` / `OOF-LOCK-IO` / integrity `OOF-IMP*` (or `OOF-LOCK-INTEGRITY`); explicit
   unlocked mode emits nothing.
6. **What breaks if default-on changed today?** All 26 `project_mode` fixtures (zero committed
   locks), every lockless project build, the dev inner loop, and the
   `cli_compile_without_locked_allows_missing_lock` regression test.

## Verification

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_lockfile_cli_tests
  55 passed; 0 failed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_workspace_tests
  53 passed; 0 failed
git diff --check  → PASS (no code changes; docs/card only)
```
